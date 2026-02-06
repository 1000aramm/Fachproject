-- Google Calendar Integration Tables
-- Run this migration in Supabase SQL Editor

-- Links Supabase Auth identity to our university user
CREATE TABLE IF NOT EXISTS google_calendar_links (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,                          -- Our existing user ID (from university login)
    supabase_user_id UUID,                          -- Supabase Auth user ID (from Google login)
    google_email TEXT NOT NULL,
    access_token TEXT,                              -- Google OAuth access token
    refresh_token TEXT,                             -- Google OAuth refresh token (for offline access)
    token_expiry TIMESTAMPTZ,
    connected_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id)                                 -- One Google account per Ayla user
);

-- Index for fast lookups
CREATE INDEX IF NOT EXISTS idx_gcal_links_user ON google_calendar_links(user_id);

-- Optional: Cache table for calendar events
CREATE TABLE IF NOT EXISTS google_calendar_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES google_calendar_links(user_id) ON DELETE CASCADE,
    google_event_id TEXT NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    is_all_day BOOLEAN DEFAULT FALSE,
    location TEXT,
    color_hex TEXT DEFAULT '#4285F4',
    calendar_id TEXT,
    fetched_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, google_event_id)
);

CREATE INDEX IF NOT EXISTS idx_gcal_events_user ON google_calendar_events(user_id);
CREATE INDEX IF NOT EXISTS idx_gcal_events_time ON google_calendar_events(start_time);
