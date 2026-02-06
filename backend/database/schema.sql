-- ============================================================
-- Student AI Platform - "Shadow State" Database Architecture
-- ============================================================
-- This schema implements the core tables for syncing Supabase
-- with Google Gemini's Files API and Context Caching.
-- ============================================================

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_cron";
CREATE EXTENSION IF NOT EXISTS "pg_net";

-- ============================================================
-- 1. ENUM TYPES (Idempotent)
-- ============================================================

DO $$ BEGIN
    CREATE TYPE gemini_file_state AS ENUM (
        'uploading', 'processing', 'active', 'failed'
    );
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    CREATE TYPE chat_mode AS ENUM (
        'assistant', 'workspace'
    );
EXCEPTION WHEN duplicate_object THEN null; END $$;


-- ============================================================
-- 2. TABLES (Idempotent Creation)
-- ============================================================

CREATE TABLE IF NOT EXISTS profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT,
    avatar_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS workspaces (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    color TEXT DEFAULT '#6366f1',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS workspace_files (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE NOT NULL,
    file_name TEXT NOT NULL,
    storage_path TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS gemini_caches (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE NOT NULL UNIQUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS chats (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    chat_id UUID REFERENCES chats(id) ON DELETE CASCADE NOT NULL,
    role TEXT CHECK (role IN ('user', 'assistant', 'system')) NOT NULL,
    content TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS reminders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);


-- ============================================================
-- 3. ROBUST COLUMN MIGRATION (Ensures Alignment with Python Code)
-- ============================================================
-- This block ensures that even if tables pre-existed, they have the correct columns.

DO $$ BEGIN
    -- Workspaces
    ALTER TABLE workspaces ADD COLUMN IF NOT EXISTS color TEXT DEFAULT '#6366f1';
    
    -- Workspace Files
    ALTER TABLE workspace_files ADD COLUMN IF NOT EXISTS file_size_bytes BIGINT;
    ALTER TABLE workspace_files ADD COLUMN IF NOT EXISTS mime_type TEXT;
    ALTER TABLE workspace_files ADD COLUMN IF NOT EXISTS gemini_file_uri TEXT;
    ALTER TABLE workspace_files ADD COLUMN IF NOT EXISTS gemini_file_state gemini_file_state DEFAULT 'uploading';
    ALTER TABLE workspace_files ADD COLUMN IF NOT EXISTS gemini_file_expiration TIMESTAMPTZ;

    -- Gemini Caches
    ALTER TABLE gemini_caches ADD COLUMN IF NOT EXISTS cache_resource_name TEXT;
    ALTER TABLE gemini_caches ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;
    ALTER TABLE gemini_caches ADD COLUMN IF NOT EXISTS token_count INTEGER DEFAULT 0;

    -- Chats
    ALTER TABLE chats ADD COLUMN IF NOT EXISTS mode chat_mode NOT NULL DEFAULT 'assistant';
    ALTER TABLE chats ADD COLUMN IF NOT EXISTS workspace_id UUID REFERENCES workspaces(id) ON DELETE SET NULL;
    ALTER TABLE chats ADD COLUMN IF NOT EXISTS title TEXT;

    -- Reminders
    ALTER TABLE reminders ADD COLUMN IF NOT EXISTS workspace_id UUID REFERENCES workspaces(id) ON DELETE SET NULL;
    ALTER TABLE reminders ADD COLUMN IF NOT EXISTS title TEXT;
    ALTER TABLE reminders ADD COLUMN IF NOT EXISTS description TEXT;
    ALTER TABLE reminders ADD COLUMN IF NOT EXISTS due_date TIMESTAMPTZ;
    ALTER TABLE reminders ADD COLUMN IF NOT EXISTS source_file_id UUID REFERENCES workspace_files(id) ON DELETE SET NULL;
    ALTER TABLE reminders ADD COLUMN IF NOT EXISTS notified BOOLEAN DEFAULT FALSE;

EXCEPTION WHEN OTHERS THEN 
    RAISE NOTICE 'Migration encountered a non-critical error: %', SQLERRM;
END $$;


-- ============================================================
-- 4. RLS POLICIES (Idempotent)
-- ============================================================

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE workspaces ENABLE ROW LEVEL SECURITY;
ALTER TABLE workspace_files ENABLE ROW LEVEL SECURITY;
ALTER TABLE gemini_caches ENABLE ROW LEVEL SECURITY;
ALTER TABLE chats ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE reminders ENABLE ROW LEVEL SECURITY;

-- Profiles
DROP POLICY IF EXISTS "Users can view own profile" ON profiles;
CREATE POLICY "Users can view own profile" ON profiles FOR SELECT USING (auth.uid() = id);
DROP POLICY IF EXISTS "Users can update own profile" ON profiles;
CREATE POLICY "Users can update own profile" ON profiles FOR UPDATE USING (auth.uid() = id);

-- Workspaces
DROP POLICY IF EXISTS "Users can view own workspaces" ON workspaces;
CREATE POLICY "Users can view own workspaces" ON workspaces FOR SELECT USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can manage own workspaces" ON workspaces;
CREATE POLICY "Users can manage own workspaces" ON workspaces FOR ALL USING (auth.uid() = user_id);

-- Workspace Files
DROP POLICY IF EXISTS "Users can view own workspace files" ON workspace_files;
CREATE POLICY "Users can view own workspace files" ON workspace_files FOR SELECT 
USING (EXISTS (SELECT 1 FROM workspaces WHERE id = workspace_id AND user_id = auth.uid()));
DROP POLICY IF EXISTS "Users can manage own workspace files" ON workspace_files;
CREATE POLICY "Users can manage own workspace files" ON workspace_files FOR ALL 
USING (EXISTS (SELECT 1 FROM workspaces WHERE id = workspace_id AND user_id = auth.uid()));

-- Gemini Caches
DROP POLICY IF EXISTS "Users can view own gemini caches" ON gemini_caches;
CREATE POLICY "Users can view own gemini caches" ON gemini_caches FOR SELECT 
USING (EXISTS (SELECT 1 FROM workspaces WHERE id = workspace_id AND user_id = auth.uid()));
DROP POLICY IF EXISTS "Users can manage own gemini caches" ON gemini_caches;
CREATE POLICY "Users can manage own gemini caches" ON gemini_caches FOR ALL 
USING (EXISTS (SELECT 1 FROM workspaces WHERE id = workspace_id AND user_id = auth.uid()));

-- Chats
DROP POLICY IF EXISTS "Users can view own chats" ON chats;
CREATE POLICY "Users can view own chats" ON chats FOR SELECT USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can manage own chats" ON chats;
CREATE POLICY "Users can manage own chats" ON chats FOR ALL USING (auth.uid() = user_id);

-- Messages
DROP POLICY IF EXISTS "Users can view own messages" ON messages;
CREATE POLICY "Users can view own messages" ON messages FOR SELECT 
USING (EXISTS (SELECT 1 FROM chats WHERE id = chat_id AND user_id = auth.uid()));
DROP POLICY IF EXISTS "Users can insert own messages" ON messages;
CREATE POLICY "Users can insert own messages" ON messages FOR INSERT 
WITH CHECK (EXISTS (SELECT 1 FROM chats WHERE id = chat_id AND user_id = auth.uid()));

-- Reminders
DROP POLICY IF EXISTS "Users can view own reminders" ON reminders;
CREATE POLICY "Users can view own reminders" ON reminders FOR SELECT USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can manage own reminders" ON reminders;
CREATE POLICY "Users can manage own reminders" ON reminders FOR ALL USING (auth.uid() = user_id);


-- ============================================================
-- 5. AUTOMATION HANDLERS
-- ============================================================

-- Profile creation on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, full_name)
    VALUES (NEW.id, NEW.raw_user_meta_data->>'full_name');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- ============================================================
-- 6. CRON JOBS
-- ============================================================

-- Moodle Sync Webhook
SELECT cron.schedule(
    'moodle-file-sync', '0 * * * *',
    $$ SELECT net.http_post(
        url := 'https://YOUR_BACKEND_URL/webhooks/sync-moodle',
        headers := jsonb_build_object('Content-Type', 'application/json', 'X-Service-Key', 'YOUR_SERVICE_KEY'),
        body := jsonb_build_object('trigger', 'scheduled')
    ); $$
);

-- Cache Cleanup
SELECT cron.schedule(
    'cleanup-expired-caches', '*/30 * * * *',
    $$ DELETE FROM gemini_caches WHERE expires_at < NOW(); $$
);


-- ============================================================
-- 7. PERFORMANCE INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_workspace_files_workspace_id ON workspace_files(workspace_id);
CREATE INDEX IF NOT EXISTS idx_messages_chat_id ON messages(chat_id);
CREATE INDEX IF NOT EXISTS idx_reminders_due_date ON reminders(due_date) WHERE notified = FALSE;
CREATE INDEX IF NOT EXISTS idx_chats_workspace_id ON chats(workspace_id) WHERE workspace_id IS NOT NULL;
