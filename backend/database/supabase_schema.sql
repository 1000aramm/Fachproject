-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_cron";

-- Clean up existing tables (Replacements)
DROP TABLE IF EXISTS 
    profiles, 
    workspaces, 
    workspace_files, 
    gemini_caches, 
    chats, 
    messages, 
    reminders,
    -- Legacy tables from old structure
    chat_logs, 
    calendar_events, 
    workspace_chats, 
    workspace_notes
CASCADE;

-- Table: profiles (Links to auth.users)
CREATE TABLE profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own profile"
    ON profiles FOR SELECT
    USING (auth.uid() = id);

CREATE POLICY "Users can update own profile"
    ON profiles FOR UPDATE
    USING (auth.uid() = id);


-- Table: workspaces (Project/Subject)
CREATE TABLE workspaces (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE workspaces ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own workspaces"
    ON workspaces FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own workspaces"
    ON workspaces FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own workspaces"
    ON workspaces FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own workspaces"
    ON workspaces FOR DELETE
    USING (auth.uid() = user_id);


-- Table: workspace_files (Links Supabase Storage to Gemini File URI)
CREATE TABLE workspace_files (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE NOT NULL,
    file_name TEXT NOT NULL,
    storage_path TEXT NOT NULL,
    gemini_uri TEXT,
    upload_status TEXT CHECK (upload_status IN ('pending', 'uploaded', 'failed')) DEFAULT 'pending',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE workspace_files ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own workspace files"
    ON workspace_files FOR SELECT
    USING (EXISTS (SELECT 1 FROM workspaces WHERE workspaces.id = workspace_files.workspace_id AND workspaces.user_id = auth.uid()));

CREATE POLICY "Users can manage own workspace files"
    ON workspace_files FOR ALL
    USING (EXISTS (SELECT 1 FROM workspaces WHERE workspaces.id = workspace_files.workspace_id AND workspaces.user_id = auth.uid()));


-- Table: gemini_caches (Stores active Cache Token info)
CREATE TABLE gemini_caches (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE NOT NULL UNIQUE, -- One active cache per workspace
    resource_name TEXT NOT NULL, -- The Gemini cache name
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE gemini_caches ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own gemini caches"
    ON gemini_caches FOR SELECT
    USING (EXISTS (SELECT 1 FROM workspaces WHERE workspaces.id = gemini_caches.workspace_id AND workspaces.user_id = auth.uid()));

CREATE POLICY "Users can manage own gemini caches"
    ON gemini_caches FOR ALL
    USING (EXISTS (SELECT 1 FROM workspaces WHERE workspaces.id = gemini_caches.workspace_id AND workspaces.user_id = auth.uid()));


-- Table: chats (Polymorphic design)
CREATE TABLE chats (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    workspace_id UUID REFERENCES workspaces(id) ON DELETE SET NULL, -- Optional link to workspace
    title TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE chats ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own chats"
    ON chats FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can manage own chats"
    ON chats FOR ALL
    USING (auth.uid() = user_id);


-- Table: messages
CREATE TABLE messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    chat_id UUID REFERENCES chats(id) ON DELETE CASCADE NOT NULL,
    role TEXT CHECK (role IN ('user', 'assistant', 'system')) NOT NULL,
    content TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own messages"
    ON messages FOR SELECT
    USING (EXISTS (SELECT 1 FROM chats WHERE chats.id = messages.chat_id AND chats.user_id = auth.uid()));

CREATE POLICY "Users can insert own messages"
    ON messages FOR INSERT
    WITH CHECK (EXISTS (SELECT 1 FROM chats WHERE chats.id = messages.chat_id AND chats.user_id = auth.uid()));


-- Table: reminders
CREATE TABLE reminders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    content TEXT NOT NULL,
    scheduled_at TIMESTAMP WITH TIME ZONE NOT NULL,
    status TEXT CHECK (status IN ('pending', 'sent', 'failed')) DEFAULT 'pending',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE reminders ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own reminders"
    ON reminders FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can manage own reminders"
    ON reminders FOR ALL
    USING (auth.uid() = user_id);


-- pg_cron Scheduler
-- Runs every minute to check for pending reminders and call an edge function
-- Replace 'https://your-project.supabase.co/functions/v1/process-reminders' with your actual endpoint
SELECT cron.schedule(
    'process-pending-reminders',
    '* * * * *',
    $$
    SELECT
        net.http_post(
            url:='https://your-project.supabase.co/functions/v1/process-reminders',
            body:=json_build_object('secret', 'YOUR_SERVICE_KEY')::jsonb
        )
    FROM reminders
    WHERE status = 'pending' AND scheduled_at <= NOW();
    $$
);
