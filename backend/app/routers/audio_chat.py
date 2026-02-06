import logging
import os
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form
from google import genai
from google.genai import types
from app.services.gemini_engine import GeminiEngine
from app.services.academic_service import AcademicService
from app.features.audio_processor import process_audio_input
from backend_config import MODEL_NAME

router = APIRouter(prefix="/chat", tags=["Audio Chat"])
logger = logging.getLogger(__name__)

async def get_gemini_client():
    from main import app
    if not app.state.genai_client:
        raise HTTPException(status_code=503, detail="AI Service Unavailable")
    return app.state.genai_client

@router.post("/audio")
async def chat_with_audio(
    audio_file: UploadFile = File(...),
    workspace_id: Optional[str] = Form(None),
    user_id: str = Form(...),
    client: genai.Client = Depends(get_gemini_client)
):
    """
    Handles voice prompts. Optimized for Gemini 2.0 Flash audio throughput.
    Includes workspace context (files) and ensures response in user's language.
    """
    logger.info(f"Audio chat request from {user_id}. File: {audio_file.filename}, Workspace: {workspace_id}")
    
    try:
        # 1. Read audio bytes
        audio_bytes = await audio_file.read()
        mime_type = audio_file.content_type or "audio/mpeg"
        
        # 2. Setup Services
        engine = GeminiEngine(client)
        from app.services.workspace_service import WorkspaceService
        ws_service = WorkspaceService()
        
        # 3. Resolve Workspace context
        cached_content_name = None
        fallback_files = []
        
        if workspace_id:
            # Use WorkspaceService for consistent metadata and validation
            cached_content_name, fallback_files = await ws_service.get_active_context(workspace_id, user_id)
            if cached_content_name:
                logger.info(f"Using context cache: {cached_content_name}")
            elif fallback_files:
                 logger.info(f"Using {len(fallback_files)} files as fallback context.")

        # 4. Prepare Audio for Gemini
        audio_part = await process_audio_input(
            engine=engine,
            audio_bytes=audio_bytes,
            mime_type=mime_type,
            file_name=audio_file.filename,
            workspace_id=workspace_id
        )
        
        if not audio_part:
            raise HTTPException(status_code=400, detail="Failed to process audio")

        # 5. Generate Response
        # Include Academic Context and Current Date
        academic_service = AcademicService()
        from app.routers.workspace_router import username_to_uuid
        
        # Robust UUID resolution
        try:
            import uuid as uuid_lib
            uuid_lib.UUID(user_id)
            user_uuid = user_id
        except:
            user_uuid = username_to_uuid(user_id) if user_id and user_id != "anonymous" else None
            
        academic_summary = await academic_service.get_academic_summary(user_uuid)
        
        prompt_parts = [
            types.Part(text=f"{academic_summary}\n\nListen to this audio and respond to the user's request. **IMPORTANT: Respond in the same language the user is speaking.**")
        ]
        
        # Add fallback files if cache failed
        if not cached_content_name and fallback_files:
            for f in fallback_files:
                prompt_parts.append(types.Part(file_data=types.FileData(file_uri=f["uri"], mime_type=f["mime_type"])))
        
        # Add the actual voice message
        prompt_parts.append(audio_part)

        # Build config based on whether we have a cache
        # Workspace audio system instruction (file-focused, enforce LaTeX)
        workspace_audio_instr = """You are Ayla, helping the student with their study materials via voice.
Focus on analyzing the uploaded documents and providing helpful explanations.
Respond in the same language the user speaks.
CRITICAL: Use LaTeX for ALL math expressions. Write $\\frac{a}{b}$ not a/b. Use $$equation$$ for display math."""
        
        if cached_content_name:
            config = {
                "cached_content": cached_content_name,
                "temperature": 0.7
            }
        else:
            config = {
                "system_instruction": workspace_audio_instr,
                "temperature": 0.7
            }

        response = await client.aio.models.generate_content(
            model=MODEL_NAME,
            contents=[types.Content(role="user", parts=prompt_parts)],
            config=config
        )

        answer = response.text if response.text else "I couldn't generate a response."

        # 6. Save to Database (Persistence)
        if workspace_id:
            try:
                from app.routers.workspace_router import username_to_uuid, supabase
                user_uuid = username_to_uuid(user_id)
                
                # Ensure a Chat session exists
                chats_resp = supabase.table("chats").select("id").eq("workspace_id", workspace_id).execute()
                if not chats_resp.data:
                    c_resp = supabase.table("chats").insert({
                        "workspace_id": workspace_id, 
                        "user_id": user_uuid, 
                        "title": "Workspace Chat"
                    }).execute()
                    chat_id = c_resp.data[0]["id"]
                else:
                    chat_id = chats_resp.data[0]["id"]
                
                # Save User Message (Transcription if possible, otherwise placeholder)
                # For now, we save it as a voice message placeholder
                supabase.table("messages").insert({
                    "chat_id": chat_id,
                    "role": "user",
                    "content": "[Voice Message]"
                }).execute()
                
                # Save Assistant Message
                supabase.table("messages").insert({
                    "chat_id": chat_id,
                    "role": "assistant",
                    "content": answer
                }).execute()
                
                logger.info(f"Saved voice interaction to chat history for workspace {workspace_id}")
            except Exception as db_e:
                logger.error(f"Failed to save voice chat to DB: {db_e}")

        return {
            "success": True,
            "answer": answer,
            "user_id": user_id,
            "filename": audio_file.filename
        }

    except Exception as e:
        logger.error(f"Audio chat failed: {e}")
        return {"success": False, "error": str(e)}
    finally:
        await audio_file.close()
