-- Storage Policies for 'workspace_files' bucket

-- 1. Allow authenticated uploads
CREATE POLICY "Allow authenticated uploads"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'workspace_files' AND
  auth.uid() = owner
);

-- 2. Allow users to view their own files
CREATE POLICY "Allow users to view own files"
ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'workspace_files' AND
  auth.uid() = owner
);

-- 3. Allow users to update their own files
CREATE POLICY "Allow users to update own files"
ON storage.objects
FOR UPDATE
TO authenticated
USING (
  bucket_id = 'workspace_files' AND
  auth.uid() = owner
);

-- 4. Allow users to delete their own files
CREATE POLICY "Allow users to delete own files"
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'workspace_files' AND
  auth.uid() = owner
);
