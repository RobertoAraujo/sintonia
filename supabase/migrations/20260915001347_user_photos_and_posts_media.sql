-- Migration: user_photos table + posts_media storage bucket
-- Timestamp: 20260915001347

-- 1. Create user_photos table (profile photo gallery)
CREATE TABLE IF NOT EXISTS public.user_photos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  post_id UUID REFERENCES public.posts(id) ON DELETE SET NULL,
  photo_url TEXT NOT NULL DEFAULT '',
  caption TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 2. Indexes
CREATE INDEX IF NOT EXISTS idx_user_photos_user_id ON public.user_photos(user_id);
CREATE INDEX IF NOT EXISTS idx_user_photos_post_id ON public.user_photos(post_id);
CREATE INDEX IF NOT EXISTS idx_user_photos_created_at ON public.user_photos(created_at DESC);

-- 3. Enable RLS
ALTER TABLE public.user_photos ENABLE ROW LEVEL SECURITY;

-- 4. RLS Policies
DROP POLICY IF EXISTS "public_can_read_user_photos" ON public.user_photos;
CREATE POLICY "public_can_read_user_photos"
  ON public.user_photos
  FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "users_manage_own_user_photos" ON public.user_photos;
CREATE POLICY "users_manage_own_user_photos"
  ON public.user_photos
  FOR ALL
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- 5. Enable Realtime on user_photos table
ALTER PUBLICATION supabase_realtime ADD TABLE public.user_photos;
