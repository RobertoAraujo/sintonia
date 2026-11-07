-- ============================================================
-- Add visibility column to posts table
-- Fixes: updatePost error - 'visibility' column not found
-- ============================================================

-- Add visibility column if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'posts' AND column_name = 'visibility'
  ) THEN
    ALTER TABLE public.posts ADD COLUMN visibility TEXT NOT NULL DEFAULT 'public';
  END IF;
END $$;

-- Update the public read policy to respect visibility
-- public = everyone, friends = authenticated, private = only author
DROP POLICY IF EXISTS "public_read_posts" ON public.posts;
CREATE POLICY "public_read_posts" ON public.posts
  FOR SELECT TO public
  USING (
    is_published = true
    AND (
      visibility = 'public'
      OR (visibility = 'friends' AND auth.uid() IS NOT NULL)
      OR (visibility = 'private' AND author_id = auth.uid())
    )
  );

-- Ensure author can still manage all their own posts regardless of visibility
DROP POLICY IF EXISTS "users_manage_own_posts" ON public.posts;
CREATE POLICY "users_manage_own_posts" ON public.posts
  FOR ALL TO authenticated
  USING (author_id = auth.uid())
  WITH CHECK (author_id = auth.uid());
