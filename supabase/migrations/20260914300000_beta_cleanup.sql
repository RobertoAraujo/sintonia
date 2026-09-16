-- ============================================================
-- SintonIA Beta Cleanup Migration
-- Truncates all user data tables, keeps schema/RLS intact
-- ============================================================

-- Disable FK constraints temporarily to allow truncation
SET session_replication_role = 'replica';

-- Cleanup usage/feed data
TRUNCATE TABLE public.messages CASCADE;
TRUNCATE TABLE public.conversations CASCADE;
TRUNCATE TABLE public.conversation_participants CASCADE;
TRUNCATE TABLE public.ai_chat_history CASCADE;
TRUNCATE TABLE public.sintonia_ai_sessions CASCADE;
TRUNCATE TABLE public.posts CASCADE;
TRUNCATE TABLE public.post_likes CASCADE;
TRUNCATE TABLE public.post_comments CASCADE;
TRUNCATE TABLE public.saved_posts CASCADE;
TRUNCATE TABLE public.friendships CASCADE;
TRUNCATE TABLE public.group_members CASCADE;
TRUNCATE TABLE public.groups CASCADE;
TRUNCATE TABLE public.pets CASCADE;
TRUNCATE TABLE public.pet_diary_entries CASCADE;
TRUNCATE TABLE public.user_diary_entries CASCADE;
TRUNCATE TABLE public.notifications CASCADE;
TRUNCATE TABLE public.user_settings CASCADE;
TRUNCATE TABLE public.stories CASCADE;
TRUNCATE TABLE public.blocked_users CASCADE;
TRUNCATE TABLE public.reports CASCADE;

-- Truncate user profiles last (referenced by all above)
TRUNCATE TABLE public.user_profiles CASCADE;

-- Re-enable FK constraints
SET session_replication_role = 'origin';

-- Add leaveGroup support: ensure RPC exists for decrementing members_count
CREATE OR REPLACE FUNCTION public.decrement_group_members(group_id_param UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.groups
  SET members_count = GREATEST(0, members_count - 1)
  WHERE id = group_id_param;
END;
$$;

-- Ensure increment_group_members RPC exists
CREATE OR REPLACE FUNCTION public.increment_group_members(group_id_param UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.groups
  SET members_count = members_count + 1
  WHERE id = group_id_param;
END;
$$;

-- Add group_posts table for group-specific posts/messages
CREATE TABLE IF NOT EXISTS public.group_posts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id UUID NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  author_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  content TEXT NOT NULL DEFAULT '',
  image_url TEXT DEFAULT '',
  likes_count INTEGER DEFAULT 0,
  comments_count INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.group_posts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "group_posts_select" ON public.group_posts;
CREATE POLICY "group_posts_select" ON public.group_posts
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "group_posts_insert" ON public.group_posts;
CREATE POLICY "group_posts_insert" ON public.group_posts
  FOR INSERT TO authenticated WITH CHECK (author_id = auth.uid());

DROP POLICY IF EXISTS "group_posts_delete" ON public.group_posts;
CREATE POLICY "group_posts_delete" ON public.group_posts
  FOR DELETE TO authenticated USING (author_id = auth.uid());

-- Add group_post_likes table
CREATE TABLE IF NOT EXISTS public.group_post_likes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id UUID NOT NULL REFERENCES public.group_posts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(post_id, user_id)
);

ALTER TABLE public.group_post_likes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "group_post_likes_all" ON public.group_post_likes;
CREATE POLICY "group_post_likes_all" ON public.group_post_likes
  FOR ALL TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- Enable realtime for group_posts
ALTER PUBLICATION supabase_realtime ADD TABLE public.group_posts;
