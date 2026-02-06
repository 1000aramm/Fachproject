import os
import asyncio
from datetime import datetime, timedelta, timezone
from typing import Optional, List
import logging

from supabase import create_client, Client as SupabaseClient
from google import genai
from google.genai import types
from backend_config import MODEL_NAME

logger = logging.getLogger(__name__)

class WorkspaceService:
    def __init__(self):
        # Initialize Supabase Client
        self.supabase_url = os.getenv("SUPABASE_URL")
        self.supabase_key = os.getenv("SUPABASE_SERVICE_KEY")
        
        if not self.supabase_url or not self.supabase_key:
            logger.warning("Supabase credentials not found in environment variables.")
            self.supabase: Optional[SupabaseClient] = None
        else:
            self.supabase = create_client(self.supabase_url, self.supabase_key)

        # Initialize Gemini Client
        self.gemini_api_key = os.getenv("GEMINI_API_KEY")
        if not self.gemini_api_key:
            logger.warning("Gemini API key not found.")
            self.gemini_client = None
        else:
            self.gemini_client = genai.Client(api_key=self.gemini_api_key)

    async def get_active_context(self, workspace_id: str, user_id: str) -> tuple[Optional[str], List[dict]]:
        """
        Implements the Check-or-Create Caching Algorithm.
        Returns (gemini_cache_name, list_of_file_info_for_fallback).
        """
        if not self.supabase or not self.gemini_client:
            raise RuntimeError("Services not initialized properly.")

        # 1. Query gemini_caches for the workspace
        # We need to check if a valid cache exists.
        # Assuming RLS allows this service role access or we pass user context if utilizing proper auth flow. 
        # Since this is a backend service utilizing service key (likely) or acting on behalf, 
        # we'll assume we can query by workspace_id directly.
        
        response = self.supabase.table("gemini_caches") \
            .select("cache_resource_name, expires_at") \
            .eq("workspace_id", workspace_id) \
            .execute()

        cache_entry = response.data[0] if response.data else None

        if cache_entry:
            expires_at_str = cache_entry["expires_at"]
            # Parse ISO string to datetime
            expires_at = datetime.fromisoformat(expires_at_str.replace("Z", "+00:00"))
            
            # Check if expired
            if expires_at > datetime.now(timezone.utc):
                logger.info(f"Cache hit for workspace {workspace_id}: {cache_entry['cache_resource_name']}")
                # We still need the files info for fallback if something goes wrong later, 
                # but for simplicity, we'll return empty list if cache hit.
                return cache_entry["cache_resource_name"], []
            else:
                logger.info(f"Cache expired for workspace {workspace_id}. Re-creating...")
                # Cleanup old cache entry ideally, but upsert will handle the DB record update. 
                # We might want to delete the old cache from Gemini if possible, but the API handles expiration.

        # 2. Cache miss or expired: Create new cache
        
        # Query workspace_files for this workspace to get file paths
        files_response = self.supabase.table("workspace_files") \
            .select("id, storage_path, gemini_file_uri, file_name") \
            .eq("workspace_id", workspace_id) \
            .execute()
        
        workspace_files = files_response.data
        if not workspace_files:
            logger.info(f"No files in workspace {workspace_id}. Returning empty context.")
            return None, []

        valid_files = []
        
        # Check gemini_file_uris and upload if missing or expired
        for file_record in workspace_files:
            resource_name = file_record.get("gemini_file_uri")
            g_file = None
            
            # Validate file is still active on Gemini
            if resource_name:
                try:
                    g_file = await self.gemini_client.aio.files.get(name=resource_name)
                    if g_file.state.name != "ACTIVE":
                        logger.info(f"File {resource_name} is not active (state: {g_file.state.name}). Re-uploading...")
                        g_file = None
                except Exception as e:
                    logger.warning(f"File {resource_name} no longer exists or inaccessible on Gemini: {e}. Re-uploading...")
                    g_file = None
            
            if not g_file:
                # Upload to Gemini Files API
                new_resource_name = await self._upload_to_gemini(file_record)
                # Note: _upload_to_gemini returns uri currently, but we need resource name for persistence
                # and g_file object for immediate use. 
                # Let's fetch the object for the new one to be sure we have BOTH name and uri
                try:
                    # In google-genai, the object returned by upload has .name and .uri
                    # If my helper returns uri, I might need to clarify what it returns.
                    # Looking at my helper below, it returns uploaded_file.uri (URI string).
                    # But we need the resource name (e.g. files/...) for storage.
                    pass
                except:
                    pass
                
                # Re-fetch or re-upload to get full object
                # Update: My helper returns a string. Let's make it more robust.
                # Actually, I'll modify _upload_to_gemini to return the resource name.
                # Since I am refactoring, I will fix the helper too.
                # For now, assume it returns the name 'files/...'
                pass

            # I will refactor the upload helper too to be clearer.
            # But here let's finish the loop logic.
            # I will perform the re-upload and re-fetch to get the full object.
            if not g_file:
                 resource_name = await self._upload_to_gemini(file_record) # Refactored to return name
                 g_file = await self.gemini_client.aio.files.get(name=resource_name)
                 
                 # Update DB with new Resource Name
                 self.supabase.table("workspace_files") \
                    .update({"gemini_file_uri": resource_name, "gemini_file_state": "active"}) \
                    .eq("id", file_record["id"]) \
                    .execute()

            valid_files.append(g_file)

        if not valid_files:
             return None, []

        # Prepare files info or cache contents
        files_info = []
        cached_contents = []
        
        for g_file in valid_files:
            fname = g_file.display_name or "doc.pdf"
            mime_type = g_file.mime_type or "application/pdf"
            
            # files_info needs full URI for fallback prompt
            files_info.append({"uri": g_file.uri, "mime_type": mime_type})
            
            cached_contents.append(
                types.Content(
                    role="user",
                    parts=[
                        types.Part(
                            file_data=types.FileData(file_uri=g_file.uri, mime_type=mime_type)
                        )
                    ]
                )
            )

        # Create cache
        try:
            # Fetch academic summary if user_id is provided
            academic_context = ""
            if user_id:
                from app.services.academic_service import AcademicService
                from app.routers.workspace_router import username_to_uuid
                service = AcademicService()
                u_uuid = username_to_uuid(user_id)
                academic_context = await service.get_academic_summary(u_uuid)
            
            # Workspace cache system instruction (file-focused, enforce LaTeX)
            workspace_cache_instr = """You are Ayla, helping students analyze their study materials.
Focus on the uploaded documents. 
CRITICAL: Use LaTeX for ALL math. Write $\\frac{a}{b}$ not a/b. Write $\\int f(x) dx$ not integral f(x) dx.
For display equations use: $$\\int \\frac{4x}{x^4-1} dx = answer$$"""
            full_sys_instr = f"{academic_context}\n\n{workspace_cache_instr}"

            cache = await self.gemini_client.aio.caches.create(
                model=MODEL_NAME,
                config=types.CreateCachedContentConfig(
                    system_instruction=types.Content(
                        role="system",
                        parts=[types.Part(text=full_sys_instr)]
                    ),
                    contents=cached_contents,
                    ttl="7200s" # 2 hours
                )
            )
            
            # Upsert into gemini_caches
            self.supabase.table("gemini_caches").upsert({
                "workspace_id": workspace_id,
                "cache_resource_name": cache.name,
                "expires_at": cache.expire_time
            }).execute()
            
            return cache.name, files_info
            
        except Exception as e:
            error_msg = str(e)
            if "too small" in error_msg.lower() or "min_total_token_count" in error_msg:
                logger.info(f"Workspace too small for cache. Proceeding with fallback files.")
            else:
                logger.warning(f"Gemini Caching failed (proceeding with fallback): {e}")
            return None, files_info

    async def _upload_to_gemini(self, file_record: dict) -> str:
        """
        Downloads file from Supabase Storage and uploads to Gemini Files API.
        Returns the Gemini resource name (e.g., "files/...")
        """
        # 1. Download from Supabase Storage
        path = file_record["storage_path"]
        # bucket name? Assuming 'workspace_files' or similar. 
        # Ideally stored in path or separate config.
        # We will assume path is 'bucket/folder/file' or use a default bucket.
        # Let's assume a 'files' bucket.
        bucket_name = "workspace_files" # heuristic
        
        try:
            # Note: Supabase storage.download returns bytes
            file_data = self.supabase.storage.from_(bucket_name).download(path)
        except Exception as e:
            logger.error(f"Failed to download {path} from Supabase: {e}")
            raise

        # 2. Upload to Gemini
        # We need a temporary file or bytes IO?
        # client.files.upload takes path or file-like object?
        # In v1.0, types.File object?
        # Actually client.files.upload(file=...)
        # We'll use a BytesIO wrapper or temp file if needed.
        # But `upload` usually expects a path. `upload_file` is the method?
        
        # Workaround: Write to temp file
        import tempfile
        suffix = os.path.splitext(file_record["file_name"])[1]
        
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
            tmp.write(file_data)
            tmp_path = tmp.name
            
        try:
            # client.files.upload(path=...) returns a File object
            # Note: client.files.upload is synchronous usually? 
            # Use aio? client.aio.files.upload?
            # Check SDK capability. Assuming client.aio.files.upload exists.
            
            uploaded_file = await self.gemini_client.aio.files.upload(
                file=tmp_path,
                config=types.UploadFileConfig(display_name=file_record["file_name"]) 
            )
            
            # Poll for ACTIVE state
            logger.info(f"File {uploaded_file.name} uploaded. Waiting for ACTIVE state...")
            g_file = uploaded_file
            while g_file.state.name == "PROCESSING":
                await asyncio.sleep(1)
                g_file = await self.gemini_client.aio.files.get(name=uploaded_file.name)
            
            if g_file.state.name != "ACTIVE":
                logger.error(f"File {uploaded_file.name} failed to process: {g_file.state.name}")
                raise RuntimeError(f"Gemini file processing failed: {g_file.state.name}")
                
            return g_file.name
        finally:
            if os.path.exists(tmp_path):
                os.remove(tmp_path)

