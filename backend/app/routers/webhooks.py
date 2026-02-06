import logging
import os
import threading
from typing import Optional, Dict, Any

from fastapi import APIRouter, Header, HTTPException, BackgroundTasks, Depends
from dotenv import load_dotenv

from app.scrapers.moodle_scraper import MoodleScraper
# No longer importing global supabase, will use engine or get_supabase if needed


load_dotenv()

router = APIRouter(prefix="/webhooks", tags=["Webhooks"])
logger = logging.getLogger(__name__)

# Security: Service Key for internal scheduled jobs
SERVICE_KEY = os.getenv("SUPABASE_SERVICE_KEY")

async def verify_service_key(x_service_key: str = Header(None)):
    if x_service_key != SERVICE_KEY:
        logger.warning(f"Unauthorized webhook attempt with key: {x_service_key}")
        raise HTTPException(status_code=401, detail="Unauthorized")
    return x_service_key

def run_moodle_sync():
    """
    Background task to sync Moodle files.
    """
    logger.info("Starting scheduled Moodle sync...")
    # Logic:
    # 1. Get all users (or active profiles).
    # 2. For each user, decrypt stored credentials (if you have them stored, which is risky/complex).
    #    OR rely on the fact that this might be a per-user trigger if simpler.
    
    # Requirement from prompt: "Create a cron job that invokes a Python webhook (POST /webhooks/sync-moodle) to check for new files."
    # Since we don't store passwords plainly, we might only be able to do this if we have a way to login.
    # The prompt implies a general sync.
    # CAUTION: Without stored credentials, we can't login to Moodle.
    # The 'Shadow State' implies we track what we have.
    # If the user is logged in via the app, we have session.
    # For a CRON job, we'd need stored credentials. 
    # Current `main.py` accepts credentials in /login.
    
    # Assumption for this phase: The webhook is a placeholder for the architecture or expects a specific user context?
    # Or maybe we skip implementation of the *actual* login loop for all users if we lack the creds storage.
    # I will implement the structure.
    
    logger.info("Moodle sync triggered (Implementation pending credential storage strategy).")
    pass

@router.post("/sync-moodle")
async def sync_moodle(
    background_tasks: BackgroundTasks,
    x_service_key: str = Depends(verify_service_key)
):
    """
    Webhook triggered by pg_cron to sync Moodle files.
    """
    background_tasks.add_task(run_moodle_sync)
    return {"status": "accepted", "message": "Sync job started"}
