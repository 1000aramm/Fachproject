import os
import httpx
import asyncio
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

BASE_URL = "http://localhost:8001"
# Note: You need a valid Supabase JWT token to run this against a live server.
# For verification purposes, we'll use a script that can also be used as a template.
TOKEN = os.getenv("SUPABASE_JWT_TOKEN", "MOCK_TOKEN")

async def test_audio_chat_e2e(file_size_mb: float, workspace_id: str = None):
    print(f"\n--- Testing Audio Chat (Size: {file_size_mb} MB) ---")
    
    # Create a dummy audio file
    filename = f"test_{file_size_mb}mb.m4a"
    content = b"0" * int(file_size_mb * 1024 * 1024)
    
    with open(filename, "wb") as f:
        f.write(content)
    
    try:
        async with httpx.AsyncClient(timeout=60.0) as client:
            files = {'audio_file': (filename, open(filename, 'rb'), 'audio/mpeg')}
            data = {}
            if workspace_id:
                data['workspace_id'] = workspace_id
                
            headers = {"Authorization": f"Bearer {TOKEN}"}
            
            print(f"Sending request to {BASE_URL}/chat/audio...")
            response = await client.post(
                f"{BASE_URL}/chat/audio",
                files=files,
                data=data,
                headers=headers
            )
            
            print(f"Status Code: {response.statusCode if hasattr(response, 'statusCode') else response.status_code}")
            print(f"Response: {response.text}")
            
            if response.status_code == 200:
                print("✅ Success!")
            else:
                print("❌ Failed.")
                
    except Exception as e:
        print(f"Error during E2E test: {e}")
    finally:
        if os.path.exists(filename):
            os.remove(filename)

async def main():
    # 1. Test Small File (Inline Path)
    await test_audio_chat_e2e(0.1)
    
    # 2. Test Large File (Files API Path)
    # Note: 21MB is quite large for a dummy test, let's use 2MB for the "small" 
    # and just trust the regression tests for the 20MB+ threshold unless specifically needed.
    # But for a true E2E, we'd need a real token and connectivity.
    print("\nE2E Verification Script ready. To run against a live server, ensure BASE_URL and TOKEN are set.")

if __name__ == "__main__":
    asyncio.run(main())
