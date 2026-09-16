-- Create the posts storage bucket (public so post images are accessible)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'posts',
  'posts',
  true,
  10485760, -- 10 MB limit
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
ON CONFLICT (id) DO NOTHING;

-- Drop existing policies before recreating (idempotent)
DROP POLICY IF EXISTS "Users can upload post images" ON storage.objects;
DROP POLICY IF EXISTS "Users can update their own post images" ON storage.objects;
DROP POLICY IF EXISTS "Public read access for post images" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete their own post images" ON storage.objects;

-- RLS: Allow authenticated users to upload post images
CREATE POLICY "Users can upload post images"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'posts'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- RLS: Allow authenticated users to update their own post images
CREATE POLICY "Users can update their own post images"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'posts'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- RLS: Allow public read access to post images
CREATE POLICY "Public read access for post images"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'posts');

-- RLS: Allow users to delete their own post images
CREATE POLICY "Users can delete their own post images"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'posts'
  AND (storage.foldername(name))[1] = auth.uid()::text
);
