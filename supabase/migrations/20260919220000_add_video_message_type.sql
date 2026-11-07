-- Add 'video' value to the message_type enum so video messages can be stored
ALTER TYPE public.message_type ADD VALUE IF NOT EXISTS 'video';

-- Update chat-media bucket to allow additional video MIME types
UPDATE storage.buckets
SET allowed_mime_types = ARRAY[
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
  'video/quicktime',
  'video/x-msvideo',
  'video/3gpp',
  'video/x-matroska',
  'application/pdf',
  'application/octet-stream'
]
WHERE id = 'chat-media';
