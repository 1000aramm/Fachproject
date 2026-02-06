import unittest
import asyncio
from datetime import datetime
from unittest.mock import AsyncMock, MagicMock, patch
import os
import sys

# Add backend to sys.path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from app.services.gemini_engine import GeminiEngine
from app.features.audio_processor import process_audio_input, AUDIO_SIZE_THRESHOLD_BYTES
from app.auth.supabase_auth import verify_supabase_token
from app.routers.audio_chat import chat_with_audio
from app.features.deadline_extractor import DeadlineExtractor, SyllabusDeadlines, DeadlineItem
from app.routers.stream_chat import ChatMessage, stream_chat

class RegressionTests(unittest.IsolatedAsyncioTestCase):

    def setUp(self):
        self.mock_genai_client = MagicMock()
        self.mock_genai_client.aio = MagicMock()
        self.engine = GeminiEngine(self.mock_genai_client)

    async def test_audio_processor_inline_strategy(self):
        """Verify audio < 20MB uses inline_data."""
        audio_bytes = b"small_audio_data"
        mime_type = "audio/mpeg"
        file_name = "test.mp3"
        
        with patch('app.features.audio_processor.GeminiEngine', return_value=self.engine):
            result = await process_audio_input(self.engine, audio_bytes, mime_type, file_name)
            
            # Result should be a types.Part with inline_data
            from google.genai import types
            self.assertIsInstance(result, types.Part)
            self.assertEqual(result.inline_data.mime_type, mime_type)
            self.assertEqual(result.inline_data.data, audio_bytes)

    async def test_audio_processor_files_api_strategy(self):
        """Verify audio > 20MB uses Files API."""
        # Create bytes larger than threshold
        large_audio_bytes = b"a" * (AUDIO_SIZE_THRESHOLD_BYTES + 1024)
        mime_type = "audio/mpeg"
        file_name = "large_test.mp3"

        # Mock the Gemini Files API
        mock_file = MagicMock()
        mock_file.name = "files/mock_file_123"
        mock_file.state.name = "ACTIVE"
        
        self.mock_genai_client.aio.files.upload = AsyncMock(return_value=mock_file)
        self.mock_genai_client.aio.files.get = AsyncMock(return_value=mock_file)

        result = await process_audio_input(self.engine, large_audio_bytes, mime_type, file_name)
        
        # Should call upload
        self.mock_genai_client.aio.files.upload.assert_called_once()
        self.assertEqual(result.name, "files/mock_file_123")

    @patch('app.services.gemini_engine.get_supabase')
    async def test_gemini_engine_cache_lifecycle(self, mock_get_supabase):
        """Verify GeminiEngine checks cache and handles missing cache."""
        mock_supabase = MagicMock()
        mock_get_supabase.return_value = mock_supabase
        
        # Scenario: No existing cache in DB
        # We need to mock the chain: supabase.table().select().eq().maybe_single().execute()
        execute_mock = AsyncMock(return_value=MagicMock(data=None))
        mock_supabase.table.return_value.select.return_value.eq.return_value.maybe_single.return_value.execute = execute_mock
        
        # Scenario: No files in workspace
        # We also need to mock: supabase.table().select().eq().execute()
        execute_files_mock = AsyncMock(return_value=MagicMock(data=[]))
        # This will override the previous mock if they share the same chain until .execute
        # For simple regression, let's just assert that it returns "" when no files found
        mock_supabase.table.return_value.select.return_value.eq.return_value.execute = execute_files_mock
        
        result = await self.engine.get_or_create_cache("mock_ws_id")
        
        # Path should return "" if no files can be cached
        self.assertEqual(result, "")

    def test_auth_stateless_check(self):
        """Check that auth module exists and has correct functions."""
        self.assertTrue(callable(verify_supabase_token))

    @patch('app.routers.audio_chat.GeminiEngine')
    @patch('app.routers.audio_chat.process_audio_input', new_callable=AsyncMock)
    @patch('app.routers.audio_chat.get_current_user_id', return_value="test_user")
    async def test_audio_chat_endpoint_logic(self, mock_auth, mock_process, mock_engine_class):
        """Verify the /chat/audio logic wiring."""
        # 1. Setup mocks
        mock_file = MagicMock()
        mock_file.read = AsyncMock(return_value=b"fake_audio")
        mock_file.filename = "test.m4a"
        mock_file.content_type = "audio/mpeg"
        mock_file.close = AsyncMock()
        
        mock_engine_class.return_value.get_or_create_cache = AsyncMock(return_value="mock_cache")
        mock_process.return_value = MagicMock() # types.Part
        
        mock_response = MagicMock()
        mock_response.text = "Mock AI Response"
        self.mock_genai_client.aio.models.generate_content = AsyncMock(return_value=mock_response)

        # 2. Call the endpoint function directly
        from app.routers.audio_chat import chat_with_audio
        result = await chat_with_audio(
            audio_file=mock_file,
            workspace_id="ws_123",
            user_id="test_user",
            client=self.mock_genai_client
        )
        
        # 3. Assertions
        self.assertTrue(result['success'])
        self.assertEqual(result['answer'], "Mock AI Response")
        self.mock_genai_client.aio.models.generate_content.assert_called_once()

    async def test_deadline_extractor_logic(self):
        """Verify the DeadlineExtractor parsing result logic."""
        # 1. Setup mock result
        mock_parsed = SyllabusDeadlines(deadlines=[
            DeadlineItem(title="Midterm", date="2025-10-15", type="exam", description="Big Exam")
        ])
        
        mock_response = MagicMock()
        mock_response.parsed = mock_parsed
        self.mock_genai_client.aio.models.generate_content = AsyncMock(return_value=mock_response)
        
        extractor = DeadlineExtractor(self.mock_genai_client)
        
        # 2. Call extraction
        result = await extractor.extract_from_file(b"pdf_content", "application/pdf")
        
        # 3. Assertions
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]['title'], "Midterm")
        self.assertIsInstance(result[0]['date'], datetime)
        self.assertEqual(result[0]['date'].year, 2025)

    @patch('app.routers.stream_chat.GeminiEngine')
    @patch('app.routers.stream_chat.get_gemini_client')
    async def test_stream_chat_sse_logic(self, mock_client, mock_engine_class):
        """Verify the SSE generator yields expected data chunks."""
        # 1. Setup mocks
        mock_client.return_value = self.mock_genai_client
        
        mock_chunk = MagicMock()
        mock_chunk.text = "Hello"
        
        async def mock_stream(*args, **kwargs):
            yield mock_chunk
            
        self.mock_genai_client.aio.models.generate_content_stream = MagicMock(return_value=mock_stream())
        
        # 2. Call the generator (contained inside the endpoint)
        from app.routers.stream_chat import stream_chat
        request = ChatMessage(message="Hi", workspace_id=None)
        
        response = await stream_chat(request, user_id="test_user", client=self.mock_genai_client)
        
        # 3. Manually iterate the generator
        chunks = []
        async for event in response.body_iterator:
            chunks.append(event)
            
        self.assertTrue(any("Hello" in c for c in chunks))
        self.assertTrue(any("done" in c for c in chunks))

if __name__ == '__main__':
    unittest.main()
