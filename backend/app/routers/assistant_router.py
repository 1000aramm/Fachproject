"""
Assistant API Router - Dedicated endpoints for the Chat Assistant (Ayla).

This router handles all Chat Assistant functionality, completely separated from
workspace operations. It provides:
- /assistant/chat - Text chat with academic context
- /assistant/audio - Voice chat with academic context

The assistant has access to the student's academic data from Supabase:
- Grades, ECTS, degree program
- Upcoming deadlines
- Academic profile

It does NOT have access to workspace files - that's handled by workspace_router.py
"""

import logging
import os
from typing import Optional, Dict, List
from datetime import datetime, timedelta
import threading

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form
from pydantic import BaseModel, Field
from google import genai
from google.genai import types

from app.services.academic_service import AcademicService
from app.features.audio_processor import process_audio_input
from app.services.gemini_engine import GeminiEngine
from backend_config import MODEL_NAME

router = APIRouter(prefix="/assistant", tags=["Chat Assistant"])
logger = logging.getLogger(__name__)


# =============================================================================
# Conversation Memory (Assistant-Specific)
# =============================================================================

class AssistantMemory:
    """In-memory conversation storage with 24-hour TTL per user."""
    
    def __init__(self, ttl_hours: int = 24):
        self._store: Dict[str, Dict] = {}
        self._lock = threading.Lock()
        self._ttl = timedelta(hours=ttl_hours)
    
    def _cleanup_expired(self):
        now = datetime.now()
        expired = [uid for uid, data in self._store.items() 
                   if now - data['last_access'] > self._ttl]
        for uid in expired:
            del self._store[uid]
    
    def add_message(self, user_id: str, role: str, content: str):
        with self._lock:
            self._cleanup_expired()
            if user_id not in self._store:
                self._store[user_id] = {'messages': [], 'last_access': datetime.now()}
            
            self._store[user_id]['messages'].append({
                'role': role,
                'content': content,
                'timestamp': datetime.now().isoformat()
            })
            self._store[user_id]['last_access'] = datetime.now()
            
            # Keep only last 20 messages
            if len(self._store[user_id]['messages']) > 20:
                self._store[user_id]['messages'] = self._store[user_id]['messages'][-20:]
    
    def get_history(self, user_id: str) -> List[Dict]:
        with self._lock:
            self._cleanup_expired()
            if user_id in self._store:
                self._store[user_id]['last_access'] = datetime.now()
                return self._store[user_id]['messages'].copy()
            return []


# Singleton memory instance for this router
assistant_memory = AssistantMemory(ttl_hours=24)


# =============================================================================
# Request/Response Models
# =============================================================================

class ChatRequest(BaseModel):
    """Request model for text chat."""
    message: str = Field(..., min_length=1)
    user_id: Optional[str] = None
    student_context: Optional[dict] = None  # Fallback context from frontend


# =============================================================================
# Dependencies
# =============================================================================

async def get_gemini_client():
    """Get the Gemini client from app state."""
    from main import app
    if not app.state.genai_client:
        raise HTTPException(status_code=503, detail="AI Service Unavailable")
    return app.state.genai_client


def resolve_user_uuid(user_id: str) -> Optional[str]:
    """Resolves user_id to a UUID, handling both UUIDs and usernames."""
    if not user_id or user_id == "anonymous":
        return None
    try:
        import uuid as uuid_lib
        uuid_lib.UUID(user_id)
        return user_id
    except ValueError:
        # It's a username, convert to deterministic UUID
        from app.routers.workspace_router import username_to_uuid
        return username_to_uuid(user_id)


# =============================================================================
# Assistant System Instruction (Specialized for Academic Help)
# =============================================================================

ASSISTANT_SYSTEM_INSTRUCTION = """You are Ayla, a friendly and highly intelligent AI study assistant for TU Dortmund students.

Your role: Help students with academic questions, study planning, and course-related problems.

Your personality:
- Warm, encouraging, and supportive
- Thorough and detailed when explaining complex concepts
- Use casual but professional language
- Add helpful emojis occasionally 📚✨

Mathematics & Technical Reasoning:
- When solving mathematical or technical problems, provide COMPLETE, step-by-step solutions.
- Use LaTeX notation INLINE for all formulas: $\\frac{a}{b}$, $\\int_{a}^{b} f(x) dx$, $x^{2}$
- For important equations, use display math: $$\\int \\frac{4x}{x^4-1} dx$$
- NEVER output raw LaTeX code blocks or document preambles
- Keep all math readable and properly formatted.

Your capabilities:
- Answer questions about courses, exams, and academic life at TU Dortmund
- Help with study planning and time management  
- Explain concepts related to their courses (Informatik, Math, etc.)
- Solve problems completely and provide full solutions
- You have access to the student's academic data: grades, ECTS, deadlines, degree program

Constraints:
- Provide thorough, complete responses. Do NOT refuse to give full solutions.
- If asked about specific documents or files, explain that you can help with those in the Workspace view.
- Focus on being a helpful academic companion.
"""


# =============================================================================
# Chat Endpoints
# =============================================================================

@router.post("/chat")
async def assistant_chat(
    request: ChatRequest,
    client: genai.Client = Depends(get_gemini_client)
):
    """
    Text chat with the assistant. Includes academic context from Supabase.
    
    This is the dedicated endpoint for the floating Ayla chat widget.
    It does NOT have access to workspace files.
    """
    try:
        user_id = request.user_id or "anonymous"
        user_uuid = resolve_user_uuid(user_id)
        
        messages = []
        
        # 1. Fetch Academic Context from Supabase (Primary Source)
        academic_context = ""
        if user_uuid:
            service = AcademicService()
            academic_context = await service.get_academic_summary(user_uuid)
            messages.append(academic_context)
        
        # 2. Fallback to frontend context if DB fetch failed
        if not academic_context and request.student_context:
            ctx = request.student_context
            fallback_msg = "[STUDENT CONTEXT]\n"
            if ctx.get('name'): fallback_msg += f"- Name: {ctx['name']}\n"
            if ctx.get('degree'): fallback_msg += f"- Degree: {ctx['degree']}\n"
            if ctx.get('ects'): fallback_msg += f"- ECTS: {ctx['ects']}\n"
            messages.append(fallback_msg)
        elif not academic_context:
            messages.append(f"Today's Date: {datetime.now().strftime('%A, %B %d, %Y')}")
        
        # 3. Add Conversation History
        history = assistant_memory.get_history(user_id)
        for msg in history[-10:]:
            role = "User" if msg['role'] == 'user' else "Ayla"
            messages.append(f"{role}: {msg['content']}")
        
        # 4. Add Current Message
        messages.append(f"User: {request.message}")
        full_prompt = "\n\n".join(messages)
        
        logger.info(f"Assistant chat from {user_id}")
        
        # 5. Generate Response
        response = await client.aio.models.generate_content(
            model=MODEL_NAME,
            contents=full_prompt,
            config=types.GenerateContentConfig(
                system_instruction=ASSISTANT_SYSTEM_INSTRUCTION,
                temperature=0.7,
            )
        )
        
        answer = response.text
        
        # 6. Save to Memory
        assistant_memory.add_message(user_id, "user", request.message)
        assistant_memory.add_message(user_id, "assistant", answer)
        
        return {
            "success": True,
            "result": answer,
            "model": MODEL_NAME,
            "user_id": user_id,
            "history_count": len(history) + 2
        }
        
    except Exception as e:
        logger.error(f"Assistant chat error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/audio")
async def assistant_audio(
    audio_file: UploadFile = File(...),
    user_id: str = Form(...),
    client: genai.Client = Depends(get_gemini_client)
):
    """
    Voice chat with the assistant. Includes academic context from Supabase.
    
    This is the dedicated endpoint for voice messages in the Ayla chat widget.
    It does NOT have access to workspace files.
    """
    logger.info(f"Assistant audio request from {user_id}. File: {audio_file.filename}")
    
    try:
        # 1. Read audio bytes
        audio_bytes = await audio_file.read()
        mime_type = audio_file.content_type or "audio/mpeg"
        
        # 2. Resolve user UUID
        user_uuid = resolve_user_uuid(user_id)
        
        # 3. Fetch Academic Context
        academic_context = ""
        if user_uuid:
            service = AcademicService()
            academic_context = await service.get_academic_summary(user_uuid)
        
        if not academic_context:
            academic_context = f"Today's Date: {datetime.now().strftime('%A, %B %d, %Y')}"
        
        # 4. Process Audio for Gemini
        engine = GeminiEngine(client)
        audio_part = await process_audio_input(
            engine=engine,
            audio_bytes=audio_bytes,
            mime_type=mime_type,
            file_name=audio_file.filename,
            workspace_id=None  # No workspace context for assistant
        )
        
        if not audio_part:
            raise HTTPException(status_code=400, detail="Failed to process audio")
        
        # 5. Build Prompt
        prompt_parts = [
            types.Part(text=f"{academic_context}\n\nListen to this audio and respond to the user's request. **IMPORTANT: Respond in the same language the user is speaking.**")
        ]
        prompt_parts.append(audio_part)
        
        # 6. Generate Response
        response = await client.aio.models.generate_content(
            model=MODEL_NAME,
            contents=[types.Content(role="user", parts=prompt_parts)],
            config={
                "system_instruction": ASSISTANT_SYSTEM_INSTRUCTION,
                "temperature": 0.7
            }
        )
        
        answer = response.text if response.text else "I couldn't generate a response."
        
        # 7. Update Memory
        assistant_memory.add_message(user_id, "user", "[Voice Message]")
        assistant_memory.add_message(user_id, "assistant", answer)
        
        return {
            "success": True,
            "answer": answer,
            "user_id": user_id,
            "filename": audio_file.filename
        }
        
    except Exception as e:
        logger.error(f"Assistant audio error: {e}")
        return {"success": False, "error": str(e)}
    finally:
        await audio_file.close()
