-- Create chat-media storage bucket for sending images and audio in private chats
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'chat-media',
  'chat-media',
  true,
  52428800, -- 50MB
  ARRAY[
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/gif',
    'audio/mpeg',
    'audio/mp4',
    'audio/ogg',
    'audio/wav',
    'audio/aac',
    'audio/m4a',
    'audio/webm',
    'video/mp4',
    'video/webm',
    'application/pdf',
    'application/octet-stream'
  ]
)
ON CONFLICT (id) DO NOTHING;

-- RLS policies for chat-media bucket
DROP POLICY IF EXISTS "chat_media_authenticated_upload" ON storage.objects;
CREATE POLICY "chat_media_authenticated_upload"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'chat-media' AND auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "chat_media_public_read" ON storage.objects;
CREATE POLICY "chat_media_public_read"
ON storage.objects
FOR SELECT
TO public
USING (bucket_id = 'chat-media');

DROP POLICY IF EXISTS "chat_media_owner_delete" ON storage.objects;
CREATE POLICY "chat_media_owner_delete"
ON storage.objects
FOR DELETE
TO authenticated
USING (bucket_id = 'chat-media' AND owner = auth.uid());
