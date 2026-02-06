import logging
import base64
from typing import Union, Dict, Any
from google.genai import types
from app.services.gemini_engine import GeminiEngine

logger = logging.getLogger(__name__)

# Threshold for switching between inline data and Files API (20MB)
AUDIO_SIZE_THRESHOLD_MB = 20
AUDIO_SIZE_THRESHOLD_BYTES = AUDIO_SIZE_THRESHOLD_MB * 1024 * 1024

async def process_audio_input(
    engine: GeminiEngine,
    audio_bytes: bytes,
    mime_type: str,
    file_name: str,
    workspace_id: str = None
) -> Union[types.Part, types.File]:
    """
    Implements the Audio Processing Strategy from Section 3.
    
    If size < 20MB: Returns a Part with inline_data (Base64).
    If size > 20MB: Uploads to Gemini Files API and returns the File object.
    
    Args:
        engine: The GeminiEngine instance.
        audio_bytes: Raw audio data.
        mime_type: e.g. 'audio/mpeg', 'audio/wav'.
        file_name: Name for the file in Gemini.
        workspace_id: If provided, can be used for contextual logging or storage.
        
    Returns:
        A Gemini Part or File object.
    """
    file_size = len(audio_bytes)
    logger.info(f"Processing audio: {file_name} ({file_size} bytes)")

    if file_size < AUDIO_SIZE_THRESHOLD_BYTES:
        logger.info(f"Audio size < {AUDIO_SIZE_THRESHOLD_MB}MB. Using inline_data.")
        # Pass as inline_data (base64)
        return types.Part(
            inline_data=types.Blob(
                mime_type=mime_type,
                data=audio_bytes
            )
        )
    else:
        logger.info(f"Audio size > {AUDIO_SIZE_THRESHOLD_MB}MB. Routing through Files API.")
        # Route through Files API upload flow
        # Note: We can reuse the upload logic in engine or create a specific one for raw bytes
        # Since engine._upload_from_supabase_to_gemini expects a DB record, 
        # let's add a generic upload method to engine if needed or implement here.
        
        from io import BytesIO
        file_obj = BytesIO(audio_bytes)
        
        upload_result = await engine.client.aio.files.upload(
            file=file_obj,
            config=types.UploadFileConfig(
                display_name=file_name,
                mime_type=mime_type
            )
        )
        
        # Wait for ACTIVE (standard requirement for Files API)
        g_file = upload_result
        import asyncio
        for _ in range(60): # 60 second timeout
            if g_file.state.name == "ACTIVE":
                break
            await asyncio.sleep(1)
            g_file = await engine.client.aio.files.get(name=g_file.name)
            
        return g_file
