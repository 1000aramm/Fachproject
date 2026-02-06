"""
Google Calendar Router - Handles OAuth flow and calendar sync via Supabase Auth.

Endpoints:
- GET /calendar/auth/url - Returns the Supabase/Google OAuth URL
- GET /calendar/auth/callback - Handles redirect from Google/Supabase
- GET /calendar/status - Checks if user has connected Google Calendar
- GET /calendar/events - Fetches calendar events for the user
- POST /calendar/disconnect - Removes the Google Calendar connection
"""

import os
import logging
from typing import Optional, List, Dict, Any
from datetime import datetime, timedelta
from urllib.parse import urlencode, quote

from fastapi import APIRouter, Query, HTTPException, Request
from fastapi.responses import RedirectResponse
from pydantic import BaseModel
import httpx

from app.services.gemini_engine import get_supabase

router = APIRouter(prefix="/calendar", tags=["Google Calendar"])
logger = logging.getLogger(__name__)

# Configuration
SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_ANON_KEY = os.getenv("SUPABASE_ANON_KEY", "")
GOOGLE_CLIENT_ID = os.getenv("GOOGLE_CLIENT_ID", "")
GOOGLE_CLIENT_SECRET = os.getenv("GOOGLE_CLIENT_SECRET", "")
FRONTEND_URL = os.getenv("FRONTEND_URL", "http://localhost:8080")
BACKEND_URL = os.getenv("BACKEND_URL", "http://localhost:8000")

# Google OAuth endpoints
GOOGLE_AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token"
GOOGLE_CALENDAR_API = "https://www.googleapis.com/calendar/v3"

# Scopes we need
GOOGLE_SCOPES = [
    "https://www.googleapis.com/auth/calendar.readonly",
    "email",
    "profile"
]


class CalendarEvent(BaseModel):
    """Calendar event model."""
    id: str
    title: str
    description: Optional[str] = None
    start_time: datetime
    end_time: datetime
    is_all_day: bool = False
    location: Optional[str] = None
    color_hex: str = "#4285F4"


# =============================================================================
# OAuth Flow Endpoints
# =============================================================================

@router.get("/auth/url")
async def get_auth_url(user_id: str = Query(..., description="The Ayla user ID")):
    """
    Returns the Google OAuth URL to initiate calendar connection.
    
    The user_id is encoded in the state parameter so we can link
    the Google account to the correct Ayla user after callback.
    """
    if not GOOGLE_CLIENT_ID:
        raise HTTPException(status_code=500, detail="Google OAuth not configured")
    
    # Encode user_id in state for security
    state = user_id  # In production, encrypt this
    
    params = {
        "client_id": GOOGLE_CLIENT_ID,
        "redirect_uri": f"{BACKEND_URL}/calendar/auth/callback",
        "response_type": "code",
        "scope": " ".join(GOOGLE_SCOPES),
        "access_type": "offline",  # Get refresh token
        "prompt": "consent",  # Force consent to get refresh token
        "state": state
    }
    
    url = f"{GOOGLE_AUTH_URL}?{urlencode(params)}"
    logger.info(f"Generated OAuth URL for user {user_id}")
    
    return {"url": url}


@router.get("/auth/callback")
async def auth_callback(
    code: str = Query(None),
    state: str = Query(None),
    error: str = Query(None)
):
    """
    Handles the OAuth callback from Google.
    
    Exchanges the authorization code for tokens and stores them in the database.
    Returns an HTML page that closes the popup and notifies the parent window.
    """
    
    def _create_response_html(success: bool, message: str = "", error_code: str = "") -> str:
        """Creates an HTML page that closes the popup and notifies the parent."""
        status = "success" if success else "error"
        return f"""
        <!DOCTYPE html>
        <html>
        <head>
            <title>Google Calendar - {'Connected' if success else 'Error'}</title>
            <style>
                body {{
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    display: flex;
                    justify-content: center;
                    align-items: center;
                    height: 100vh;
                    margin: 0;
                    background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
                    color: white;
                }}
                .container {{
                    text-align: center;
                    padding: 40px;
                }}
                .icon {{
                    font-size: 64px;
                    margin-bottom: 20px;
                }}
                .message {{
                    font-size: 18px;
                    opacity: 0.9;
                }}
                .closing {{
                    font-size: 14px;
                    opacity: 0.6;
                    margin-top: 20px;
                }}
            </style>
        </head>
        <body>
            <div class="container">
                <div class="icon">{'✓' if success else '✗'}</div>
                <div class="message">
                    {'Google Calendar connected successfully!' if success else f'Connection failed: {message}'}
                </div>
                <div class="closing">This window will close automatically...</div>
            </div>
            <script>
                // Notify parent window about the result
                if (window.opener) {{
                    window.opener.postMessage({{
                        type: 'google_calendar_oauth',
                        status: '{status}',
                        error: '{error_code}'
                    }}, '*');
                }}
                
                // Close this popup after a short delay
                setTimeout(function() {{
                    window.close();
                }}, 1500);
            </script>
        </body>
        </html>
        """
    
    from fastapi.responses import HTMLResponse
    
    if error:
        logger.error(f"OAuth error: {error}")
        return HTMLResponse(content=_create_response_html(False, error, error))
    
    if not code or not state:
        return HTMLResponse(content=_create_response_html(False, "Missing parameters", "missing_params"))
    
    user_id = state  # Decrypt in production
    
    try:
        # Debug logging
        logger.info(f"Exchanging token with Client ID: {GOOGLE_CLIENT_ID[:5]}...{GOOGLE_CLIENT_ID[-5:]}")
        logger.info(f"Redirect URI being sent: {BACKEND_URL}/calendar/auth/callback")
        
        # Exchange code for tokens
        async with httpx.AsyncClient() as client:
            token_response = await client.post(
                GOOGLE_TOKEN_URL,
                data={
                    "client_id": GOOGLE_CLIENT_ID,
                    "client_secret": GOOGLE_CLIENT_SECRET,
                    "code": code,
                    "grant_type": "authorization_code",
                    "redirect_uri": f"{BACKEND_URL}/calendar/auth/callback"
                }
            )
            
            if token_response.status_code != 200:
                error_detail = token_response.text
                logger.error(f"Token exchange failed ({token_response.status_code}): {error_detail}")
                return HTMLResponse(content=_create_response_html(False, f"Token exchange failed ({token_response.status_code})", "token_exchange_failed"))
            
            tokens = token_response.json()
            access_token = tokens.get("access_token")
            refresh_token = tokens.get("refresh_token")
            expires_in = tokens.get("expires_in", 3600)
            
            # Get user info from Google
            userinfo_response = await client.get(
                "https://www.googleapis.com/oauth2/v2/userinfo",
                headers={"Authorization": f"Bearer {access_token}"}
            )
            
            if userinfo_response.status_code != 200:
                logger.error(f"Failed to get user info: {userinfo_response.text}")
                return HTMLResponse(content=_create_response_html(False, "Failed to get user info", "userinfo_failed"))
            
            userinfo = userinfo_response.json()
            google_email = userinfo.get("email", "unknown")
        
        # Store tokens in database
        supabase = await get_supabase()
        token_expiry = datetime.utcnow() + timedelta(seconds=expires_in)
        
        # Upsert the link
        await supabase.table("google_calendar_links").upsert({
            "user_id": user_id,
            "google_email": google_email,
            "access_token": access_token,
            "refresh_token": refresh_token,
            "token_expiry": token_expiry.isoformat(),
            "updated_at": datetime.utcnow().isoformat()
        }, on_conflict="user_id").execute()
        
        logger.info(f"Successfully linked Google account {google_email} to user {user_id}")
        
        # Return success HTML that closes the popup
        return HTMLResponse(content=_create_response_html(True))
        
    except Exception as e:
        logger.error(f"OAuth callback error: {e}")
        return HTMLResponse(content=_create_response_html(False, str(e), "internal_error"))


# =============================================================================
# Status & Events Endpoints
# =============================================================================

@router.get("/status")
async def get_status(user_id: str = Query(...)):
    """Checks if the user has connected Google Calendar."""
    try:
        supabase = await get_supabase()
        
        result = await supabase.table("google_calendar_links") \
            .select("google_email, connected_at") \
            .eq("user_id", user_id) \
            .execute()
        
        if result.data and len(result.data) > 0:
            link = result.data[0]
            return {
                "connected": True,
                "email": link.get("google_email"),
                "connected_at": link.get("connected_at")
            }
        
        return {"connected": False, "email": None}
        
    except Exception as e:
        logger.error(f"Status check error: {e}")
        return {"connected": False, "email": None, "error": str(e)}


@router.get("/events")
async def get_events(
    user_id: str = Query(...),
    days: int = Query(90, description="Number of days to fetch")
):
    """Fetches Google Calendar events for the user."""
    try:
        supabase = await get_supabase()
        
        # Get stored tokens
        result = await supabase.table("google_calendar_links") \
            .select("access_token, refresh_token, token_expiry") \
            .eq("user_id", user_id) \
            .execute()
        
        if not result.data or len(result.data) == 0:
            return {"success": False, "error": "Not connected", "events": []}
        
        link = result.data[0]
        access_token = link.get("access_token")
        refresh_token = link.get("refresh_token")
        token_expiry = link.get("token_expiry")
        
        # Check if token is expired and refresh if needed
        if token_expiry:
            expiry_dt = datetime.fromisoformat(token_expiry.replace("Z", "+00:00"))
            if datetime.utcnow().replace(tzinfo=expiry_dt.tzinfo) > expiry_dt:
                access_token = await _refresh_access_token(user_id, refresh_token)
                if not access_token:
                    return {"success": False, "error": "Token refresh failed", "events": []}
        
        # Fetch events from Google Calendar
        events = await _fetch_google_events(access_token, days)
        
        return {"success": True, "events": events}
        
    except Exception as e:
        logger.error(f"Events fetch error: {e}")
        return {"success": False, "error": str(e), "events": []}


@router.post("/disconnect")
async def disconnect(user_id: str = Query(...)):
    """Removes the Google Calendar connection."""
    try:
        supabase = await get_supabase()
        
        # Delete the link
        await supabase.table("google_calendar_links") \
            .delete() \
            .eq("user_id", user_id) \
            .execute()
        
        # Also delete cached events
        await supabase.table("google_calendar_events") \
            .delete() \
            .eq("user_id", user_id) \
            .execute()
        
        logger.info(f"Disconnected Google Calendar for user {user_id}")
        return {"success": True}
        
    except Exception as e:
        logger.error(f"Disconnect error: {e}")
        return {"success": False, "error": str(e)}


# =============================================================================
# Helper Functions
# =============================================================================

async def _refresh_access_token(user_id: str, refresh_token: str) -> Optional[str]:
    """Refreshes the Google access token using the refresh token."""
    if not refresh_token:
        return None
    
    try:
        async with httpx.AsyncClient() as client:
            response = await client.post(
                GOOGLE_TOKEN_URL,
                data={
                    "client_id": GOOGLE_CLIENT_ID,
                    "client_secret": GOOGLE_CLIENT_SECRET,
                    "refresh_token": refresh_token,
                    "grant_type": "refresh_token"
                }
            )
            
            if response.status_code != 200:
                logger.error(f"Token refresh failed: {response.text}")
                return None
            
            tokens = response.json()
            new_access_token = tokens.get("access_token")
            expires_in = tokens.get("expires_in", 3600)
            
            # Update in database
            supabase = await get_supabase()
            token_expiry = datetime.utcnow() + timedelta(seconds=expires_in)
            
            await supabase.table("google_calendar_links") \
                .update({
                    "access_token": new_access_token,
                    "token_expiry": token_expiry.isoformat(),
                    "updated_at": datetime.utcnow().isoformat()
                }) \
                .eq("user_id", user_id) \
                .execute()
            
            return new_access_token
            
    except Exception as e:
        logger.error(f"Token refresh error: {e}")
        return None


async def _fetch_google_events(access_token: str, days: int = 90) -> List[Dict[str, Any]]:
    """Fetches events from Google Calendar API."""
    events = []
    
    try:
        now = datetime.utcnow()
        time_min = now.isoformat() + "Z"
        time_max = (now + timedelta(days=days)).isoformat() + "Z"
        
        async with httpx.AsyncClient() as client:
            # First, get list of calendars
            calendars_response = await client.get(
                f"{GOOGLE_CALENDAR_API}/users/me/calendarList",
                headers={"Authorization": f"Bearer {access_token}"}
            )
            
            if calendars_response.status_code != 200:
                logger.error(f"Failed to fetch calendars: {calendars_response.text}")
                return []
            
            calendars = calendars_response.json().get("items", [])
            
            # Fetch events from each selected calendar
            for calendar in calendars:
                if not calendar.get("selected", False) and calendar.get("id") != "primary":
                    continue
                
                calendar_id = calendar.get("id", "primary")
                
                events_response = await client.get(
                    f"{GOOGLE_CALENDAR_API}/calendars/{quote(calendar_id)}/events",
                    headers={"Authorization": f"Bearer {access_token}"},
                    params={
                        "timeMin": time_min,
                        "timeMax": time_max,
                        "singleEvents": "true",
                        "orderBy": "startTime",
                        "maxResults": 100
                    }
                )
                
                if events_response.status_code != 200:
                    logger.warning(f"Failed to fetch events for calendar {calendar_id}")
                    continue
                
                calendar_events = events_response.json().get("items", [])
                
                for event in calendar_events:
                    start = event.get("start", {})
                    end = event.get("end", {})
                    
                    # Handle all-day vs timed events
                    is_all_day = "date" in start
                    
                    if is_all_day:
                        start_time = datetime.fromisoformat(start.get("date"))
                        end_time = datetime.fromisoformat(end.get("date"))
                    else:
                        start_str = start.get("dateTime", now.isoformat())
                        end_str = end.get("dateTime", start_str)
                        start_time = datetime.fromisoformat(start_str.replace("Z", "+00:00"))
                        end_time = datetime.fromisoformat(end_str.replace("Z", "+00:00"))
                    
                    events.append({
                        "id": event.get("id"),
                        "title": event.get("summary", "Untitled Event"),
                        "description": event.get("description"),
                        "start_time": start_time.isoformat(),
                        "end_time": end_time.isoformat(),
                        "is_all_day": is_all_day,
                        "location": event.get("location"),
                        "color_hex": _get_color_from_id(event.get("colorId")),
                        "calendar_id": calendar_id,
                        "source": "google"
                    })
        
        # Sort by start time
        events.sort(key=lambda x: x["start_time"])
        
        logger.info(f"Fetched {len(events)} events from Google Calendar")
        return events
        
    except Exception as e:
        logger.error(f"Error fetching Google events: {e}")
        return []


def _get_color_from_id(color_id: Optional[str]) -> str:
    """Maps Google Calendar color IDs to hex colors."""
    color_map = {
        "1": "#7986CB",  # Lavender
        "2": "#33B679",  # Sage
        "3": "#8E24AA",  # Grape
        "4": "#E67C73",  # Flamingo
        "5": "#F6BF26",  # Banana
        "6": "#F4511E",  # Tangerine
        "7": "#039BE5",  # Peacock
        "8": "#616161",  # Graphite
        "9": "#3F51B5",  # Blueberry
        "10": "#0B8043", # Basil
        "11": "#D50000", # Tomato
    }
    return color_map.get(color_id, "#4285F4")  # Default Google Blue
