-- ============================================================
-- Post Interactions: shares table + count triggers
-- ============================================================

-- Post shares table
CREATE TABLE IF NOT EXISTS public.post_shares (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_post_shares_unique
  ON public.post_shares (post_id, user_id);

CREATE INDEX IF NOT EXISTS idx_post_shares_post_id
  ON public.post_shares (post_id);

-- Add shares_count column to posts if not exists
ALTER TABLE public.posts
  ADD COLUMN IF NOT EXISTS shares_count INTEGER DEFAULT 0;

-- ─── Trigger: update likes_count on post_likes insert/delete ───────────────

CREATE OR REPLACE FUNCTION public.update_post_likes_count()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.posts
    SET likes_count = likes_count + 1
    WHERE id = NEW.post_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.posts
    SET likes_count = GREATEST(likes_count - 1, 0)
    WHERE id = OLD.post_id;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_post_likes_count ON public.post_likes;
CREATE TRIGGER trg_post_likes_count
AFTER INSERT OR DELETE ON public.post_likes
FOR EACH ROW EXECUTE FUNCTION public.update_post_likes_count();

-- ─── Trigger: update comments_count on post_comments insert/delete ─────────

CREATE OR REPLACE FUNCTION public.update_post_comments_count()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.posts
    SET comments_count = comments_count + 1
    WHERE id = NEW.post_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.posts
    SET comments_count = GREATEST(comments_count - 1, 0)
    WHERE id = OLD.post_id;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_post_comments_count ON public.post_comments;
CREATE TRIGGER trg_post_comments_count
AFTER INSERT OR DELETE ON public.post_comments
FOR EACH ROW EXECUTE FUNCTION public.update_post_comments_count();

-- ─── Trigger: update shares_count on post_shares insert/delete ─────────────

CREATE OR REPLACE FUNCTION public.update_post_shares_count()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.posts
    SET shares_count = shares_count + 1
    WHERE id = NEW.post_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.posts
    SET shares_count = GREATEST(shares_count - 1, 0)
    WHERE id = OLD.post_id;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_post_shares_count ON public.post_shares;
CREATE TRIGGER trg_post_shares_count
AFTER INSERT OR DELETE ON public.post_shares
FOR EACH ROW EXECUTE FUNCTION public.update_post_shares_count();

-- ─── RLS ───────────────────────────────────────────────────────────────────

ALTER TABLE public.post_shares ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "public_read_post_shares" ON public.post_shares;
CREATE POLICY "public_read_post_shares"
ON public.post_shares FOR SELECT TO public USING (true);

DROP POLICY IF EXISTS "users_manage_own_post_shares" ON public.post_shares;
CREATE POLICY "users_manage_own_post_shares"
ON public.post_shares FOR ALL TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

-- Ensure post_likes and post_comments also have RLS
ALTER TABLE public.post_likes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "public_read_post_likes" ON public.post_likes;
CREATE POLICY "public_read_post_likes"
ON public.post_likes FOR SELECT TO public USING (true);

DROP POLICY IF EXISTS "users_manage_own_post_likes" ON public.post_likes;
CREATE POLICY "users_manage_own_post_likes"
ON public.post_likes FOR ALL TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

ALTER TABLE public.post_comments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "public_read_post_comments" ON public.post_comments;
CREATE POLICY "public_read_post_comments"
ON public.post_comments FOR SELECT TO public USING (true);

DROP POLICY IF EXISTS "users_manage_own_post_comments" ON public.post_comments;
CREATE POLICY "users_manage_own_post_comments"
ON public.post_comments FOR ALL TO authenticated
USING (author_id = auth.uid())
WITH CHECK (author_id = auth.uid());
