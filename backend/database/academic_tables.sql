-- ============================================================
-- Academic Data Persistence Tables (Softened for Shadow IDs)
-- ============================================================

-- Force drop old constraints if they exist (to allow shadow IDs even if tables were pre-created)
DO $$ BEGIN
    ALTER TABLE IF EXISTS academic_profiles DROP CONSTRAINT IF EXISTS academic_profiles_user_id_fkey;
    ALTER TABLE IF EXISTS student_deadlines DROP CONSTRAINT IF EXISTS student_deadlines_user_id_fkey;
    ALTER TABLE IF EXISTS student_grades DROP CONSTRAINT IF EXISTS student_grades_user_id_fkey;
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Constraint drop ignored'; END $$;

-- 1. Academic Profiles (GPA, ECTS, Program)
CREATE TABLE IF NOT EXISTS academic_profiles (
    user_id UUID PRIMARY KEY, -- Removed strict reference to auth.users to allow shadow IDs
    total_ects INTEGER DEFAULT 0,
    average_grade FLOAT,
    best_grade FLOAT,
    degree_program TEXT,
    last_sync TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Student Deadlines (Scraped from Moodle)
CREATE TABLE IF NOT EXISTS student_deadlines (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL, -- Removed strict reference to auth.users
    activity_name TEXT NOT NULL,
    course_name TEXT,
    due_date TIMESTAMPTZ,
    url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, activity_name, due_date)
);

-- 3. Student Grades (Scraped from BOSS)
CREATE TABLE IF NOT EXISTS student_grades (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL, -- Removed strict reference to auth.users
    exam_title TEXT NOT NULL,
    grade FLOAT,
    credits FLOAT,
    status TEXT,
    is_passed BOOLEAN DEFAULT FALSE,
    semester TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, exam_title, semester)
);

-- RLS Policies (Disabled temporarily for shadow ID support)
-- ALTER TABLE academic_profiles ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE student_deadlines ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE student_grades ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own academic profile" ON academic_profiles;
CREATE POLICY "Users can view own academic profile" ON academic_profiles FOR SELECT USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can manage own academic profile" ON academic_profiles;
CREATE POLICY "Users can manage own academic profile" ON academic_profiles FOR ALL USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can view own deadlines" ON student_deadlines;
CREATE POLICY "Users can view own deadlines" ON student_deadlines FOR SELECT USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can manage own deadlines" ON student_deadlines;
CREATE POLICY "Users can manage own deadlines" ON student_deadlines FOR ALL USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can view own grades" ON student_grades;
CREATE POLICY "Users can view own grades" ON student_grades FOR SELECT USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can manage own grades" ON student_grades;
CREATE POLICY "Users can manage own grades" ON student_grades FOR ALL USING (auth.uid() = user_id);
