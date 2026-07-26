-- Run this AFTER 04_functions_and_seed.sql
-- This sets up storage bucket permissions for incident photos

-- ============================================
-- STORAGE: Create the incident-photos bucket
-- NOTE: The bucket itself must be created via the Supabase Dashboard UI:
--   Storage → New bucket → name: "incident-photos" → Public: ON
--   Then run this SQL to set the policies.
-- ============================================

-- Allow authenticated users to upload photos to their own folder
CREATE POLICY "Users can upload incident photos"
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'incident-photos'
    AND (storage.foldername(name))[1] = 'incidents'
  );

-- Allow anyone to view incident photos (public bucket)
CREATE POLICY "Public can view incident photos"
  ON storage.objects
  FOR SELECT
  TO public
  USING (bucket_id = 'incident-photos');

-- Allow users to delete their own photos
CREATE POLICY "Users can delete own incident photos"
  ON storage.objects
  FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'incident-photos'
    AND (storage.foldername(name))[2] = auth.uid()::text
  );
