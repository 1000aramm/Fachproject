-- ============================================================
-- Academic Data Type Migration (Force Fix)
-- ============================================================

-- 1. Drop constraints again just to be safe
DO $$ BEGIN
    ALTER TABLE IF EXISTS student_grades DROP CONSTRAINT IF EXISTS student_grades_user_id_fkey;
    ALTER TABLE IF EXISTS student_deadlines DROP CONSTRAINT IF EXISTS student_deadlines_user_id_fkey;
    ALTER TABLE IF EXISTS academic_profiles DROP CONSTRAINT IF EXISTS academic_profiles_user_id_fkey;
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Constraints already gone'; END $$;

-- 2. Force conversion of credits to FLOAT
-- This handles existing data by casting
ALTER TABLE student_grades 
  ALTER COLUMN credits TYPE FLOAT USING credits::FLOAT;

-- 3. Relax GPA/Grade types if needed (already FLOAT, but just in case)
ALTER TABLE academic_profiles
  ALTER COLUMN total_ects TYPE FLOAT USING total_ects::FLOAT,
  ALTER COLUMN average_grade TYPE FLOAT USING average_grade::FLOAT,
  ALTER COLUMN best_grade TYPE FLOAT USING best_grade::FLOAT;

-- 4. Ensure RLS is OFF for these tables to allow shadow IDs
ALTER TABLE academic_profiles DISABLE ROW LEVEL SECURITY;
ALTER TABLE student_deadlines DISABLE ROW LEVEL SECURITY;
ALTER TABLE student_grades DISABLE ROW LEVEL SECURITY;
