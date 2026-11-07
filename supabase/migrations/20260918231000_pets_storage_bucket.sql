-- Migration: Create pets storage bucket with RLS policies
-- Timestamp: 20260918231000

-- ─────────────────────────────────────────────────────────────
-- 1. Create the pets storage bucket (public)
-- ─────────────────────────────────────────────────────────────
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'pets',
  'pets',
  true,
  5242880, -- 5MB limit
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- ─────────────────────────────────────────────────────────────
-- 2. RLS Policies for pets bucket
-- ─────────────────────────────────────────────────────────────

-- Allow public SELECT (read) on all pet images
DROP POLICY IF EXISTS "pets_public_select" ON storage.objects;
CREATE POLICY "pets_public_select"
ON storage.objects
FOR SELECT
TO public
USING (bucket_id = 'pets');

-- Allow authenticated users to INSERT their own pet images
DROP POLICY IF EXISTS "pets_authenticated_insert" ON storage.objects;
CREATE POLICY "pets_authenticated_insert"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'pets'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Allow authenticated users to UPDATE their own pet images
DROP POLICY IF EXISTS "pets_authenticated_update" ON storage.objects;
CREATE POLICY "pets_authenticated_update"
ON storage.objects
FOR UPDATE
TO authenticated
USING (
  bucket_id = 'pets'
  AND (storage.foldername(name))[1] = auth.uid()::text
)
WITH CHECK (
  bucket_id = 'pets'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Allow authenticated users to DELETE their own pet images
DROP POLICY IF EXISTS "pets_authenticated_delete" ON storage.objects;
CREATE POLICY "pets_authenticated_delete"
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'pets'
  AND (storage.foldername(name))[1] = auth.uid()::text
);
