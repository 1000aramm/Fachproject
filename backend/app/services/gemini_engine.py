import os
import logging
import asyncio
import base64
from datetime import datetime, timezone, timedelta
from typing import Optional, List, Dict
from io import BytesIO

from google import genai
from google.genai import types
from supabase import acreate_client, Client
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

logger = logging.getLogger(__name__)

# Initialize Supabase Client (Service Role for backend operations)
SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_SERVICE_KEY = os.getenv("SUPABASE_SERVICE_KEY")

# Asynchronous Supabase client
async def get_supabase() -> Client:
    return await acreate_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)

# Gemini Model Configuration
GEMINI_MODEL_ID = "models/gemini-2.0-flash"

class GeminiEngine:
    """
    Manages the lifecycle of Gemini 2.0 Context Cashing and Files.
    Connects Supabase Storage -> Gemini Files API -> Gemini Context Cache.
    """
    
    def __init__(self, client: genai.Client):
        self.client = client

    async def get_or_create_cache(self, workspace_id: str, files: Optional[List[Dict]] = None, user_id: Optional[str] = None) -> str:
        """
        Retrieves an active cache name for the workspace, or creates a new one
        if it doesn't exist or has expired.
        
        Args:
            workspace_id: The UUID of the workspace.
            files: Optional list of file records to cache. If None, fetched from DB.
            user_id: The student's ID/username to fetch academic context.
            
        Returns:
            The resource name of the cache (e.g., 'cachedContents/xyz...')
        """
        logger.info(f"Checking context cache for workspace: {workspace_id}")
        supabase = await get_supabase()
        
        # 1. Check Supabase 'gemini_caches' table
        try:
            response = await supabase.table("gemini_caches") \
                .select("*") \
                .eq("workspace_id", workspace_id) \
                .maybe_single() \
                .execute()
            
            # Handle None response or missing data attribute
            cache_record = getattr(response, 'data', None) if response else None
            
            if cache_record:
                # Check expiration
                expires_at = datetime.fromisoformat(cache_record['expires_at'].replace('Z', '+00:00'))
                # Add a 5 minute buffer
                if expires_at > datetime.now(timezone.utc) + timedelta(minutes=5):
                    logger.info(f"✅ Found valid active cache: {cache_record['cache_resource_name']}")
                    return cache_record['cache_resource_name']
                else:
                    logger.info("⚠️ Cache expired. Creating new one.")
                    # Delete expired record
                    await supabase.table("gemini_caches").delete().eq("id", cache_record['id']).execute()
            
        except Exception as e:
            logger.warning(f"Could not check gemini_caches (table may not exist): {e}")
            # Proceed to create new cache if check fails
            
        # 2. Cache invalid or missing -> Create updated cache
        return await self._create_workspace_cache(workspace_id, files, user_id)

    async def _create_workspace_cache(self, workspace_id: str, files: Optional[List[Dict]] = None, user_id: Optional[str] = None) -> str:
        """
        Internal: Uploads files and creates a new cache.
        """
        logger.info(f"Creating new context cache for workspace: {workspace_id}")
        supabase = await get_supabase()
        
        # 1. Get all files for this workspace if not provided
        if files is None:
            files_response = await supabase.table("workspace_files") \
                .select("*") \
                .eq("workspace_id", workspace_id) \
                .execute()
            files = files_response.data
        if not files:
            logger.info("No files in workspace. Returning None (Standard Context).")
            return "" # Handle empty cache case in caller (use standard generation)

        gemini_files = []
        
        # 2. Ensure all files are uploaded to Gemini and Active
        for file_record in files:
            g_file = await self._ensure_file_uploaded(file_record)
            if g_file:
                gemini_files.append(g_file)
        
        if not gemini_files:
             logger.warning("No valid files available for caching despite database records.")
             return ""

        # 3. Create the Cache
        # Cache TTL: 60 minutes (adjust as needed)
        logger.info(f"Creating cache with {len(gemini_files)} files...")
        
        try:
            # We use the system instruction to give context about the workspace
            ws_response = await supabase.table("workspaces").select("name, description").eq("id", workspace_id).single().execute()
            ws_name = ws_response.data['name']
            
            # Fetch academic summary if user_id is provided
            academic_context = ""
            if user_id:
                from app.services.academic_service import AcademicService
                from app.routers.workspace_router import username_to_uuid
                service = AcademicService()
                u_uuid = username_to_uuid(user_id)
                academic_context = await service.get_academic_summary(u_uuid)

            full_system_instruction = f"{academic_context}\n\nYou are a helpful teaching assistant for the course/project '{ws_name}'. Use the provided materials to answer questions."
            
            cache_config = types.CreateCachedContentConfig(
                contents=[
                    types.Content(
                        role="user",
                        parts=[
                            types.Part(file_data=types.FileData(file_uri=f.uri, mime_type=f.mime_type)) 
                            for f in gemini_files
                        ]
                    )
                ],
                system_instruction=full_system_instruction,
                ttl="3600s", # 1 hour
                display_name=f"Workspace-{workspace_id}"
            )

            # Model is passed to create(), not the config
            cached_content = await self.client.aio.caches.create(model=GEMINI_MODEL_ID, config=cache_config)
            
            logger.info(f"✅ Cache created: {cached_content.name}")
            
            # 4. Save to Supabase
            await supabase.table("gemini_caches").insert({
                "workspace_id": workspace_id,
                "cache_resource_name": cached_content.name,
                "expires_at": cached_content.expire_time.isoformat(),
                "token_count": 0 # SDK might not return this immediately, update later if needed
            }).execute()
            
            return cached_content.name
            
        except Exception as e:
            error_msg = str(e)
            # Handle minimum token count gracefully - fall back to non-cached
            if "too small" in error_msg.lower() or "min_total_token_count" in error_msg:
                logger.warning(f"Workspace content too small for caching (min 4096 tokens required). Proceeding without cache.")
                return ""
            logger.error(f"Failed to create Gemini cache: {e}")
            # For other errors, also fall back to non-cached instead of failing
            return ""

    async def _ensure_file_uploaded(self, file_record: Dict) -> Optional[types.File]:
        """
        Ensures a single file is up on Gemini and in 'ACTIVE' state.
        Handles upload from Supabase Storage if missing.
        """
        gemini_uri = file_record.get('gemini_file_uri')
        
        # Check if exists and valid on Gemini
        if gemini_uri:
            try:
                # Use standard client for sync check or aio if available
                # Assuming get_file is quick
                g_file = await self.client.aio.files.get(name=gemini_uri)
                if g_file.state.name == "ACTIVE":
                    return g_file
                elif g_file.state.name == "FAILED":
                    logger.warning(f"File {gemini_uri} failed. Re-uploading.")
                # If Processing, we might wait, but for simplicity let's assume we re-check loop or re-upload if stuck
            except Exception:
                logger.info(f"File {gemini_uri} not found on Gemini. Re-uploading.")
        
        # Upload flow
        return await self._upload_from_supabase_to_gemini(file_record)

    async def _upload_from_supabase_to_gemini(self, file_record: Dict) -> Optional[types.File]:
        """
        Downloads from Supabase Storage -> Uploads to Gemini
        """
        storage_path = file_record['storage_path']
        logger.info(f"Uploading {file_record['file_name']} from Supabase: {storage_path}")
        supabase = await get_supabase()
        
        try:
            # 1. Download file bytes from Supabase
            res = await supabase.storage.from_("workspace_files").download(storage_path)
            file_bytes = res 
            
            # 2. Upload to Gemini
            file_obj = BytesIO(file_bytes)
            
            # Determine MIME type - use from record or detect from filename
            mime_type = file_record.get('mime_type')
            if not mime_type:
                import mimetypes
                mime_type, _ = mimetypes.guess_type(file_record['file_name'])
                if not mime_type:
                    # Default fallbacks based on extension
                    ext = file_record['file_name'].lower().split('.')[-1] if '.' in file_record['file_name'] else ''
                    mime_defaults = {
                        'pdf': 'application/pdf',
                        'png': 'image/png',
                        'jpg': 'image/jpeg',
                        'jpeg': 'image/jpeg',
                        'txt': 'text/plain',
                        'md': 'text/markdown',
                    }
                    mime_type = mime_defaults.get(ext, 'application/octet-stream')
                logger.info(f"Detected MIME type for {file_record['file_name']}: {mime_type}")
            
            upload_result = await self.client.aio.files.upload(
                file=file_obj,
                config=types.UploadFileConfig(
                    display_name=file_record['file_name'],
                    mime_type=mime_type
                )
            )
            
            # 3. Wait for ACTIVE state
            logger.info(f"File uploaded to Gemini: {upload_result.name}. Waiting for processing...")
            
            g_file = upload_result
            while g_file.state.name == "PROCESSING":
                await asyncio.sleep(1) # Poll every second
                g_file = await self.client.aio.files.get(name=g_file.name)
                
            if g_file.state.name != "ACTIVE":
                logger.error(f"File processing failed: {g_file.state.name}")
                # Update DB status
                await supabase.table("workspace_files").update({
                   "gemini_file_state": "failed" 
                }).eq("id", file_record['id']).execute()
                return None
                
            logger.info("✅ File is ACTIVE.")
            
            # 4. Update Supabase record
            await supabase.table("workspace_files").update({
                "gemini_file_uri": g_file.name,
                "gemini_file_state": "active",
                "gemini_file_expiration": g_file.expiration_time.isoformat() if g_file.expiration_time else None
            }).eq("id", file_record['id']).execute()
            
            return g_file
            
        except Exception as e:
            logger.error(f"Failed to upload file {file_record['file_name']}: {e}")
            return None
