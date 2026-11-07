-- ============================================================
-- SintonIA Production Readiness Fixes
-- Fixes all critical schema gaps found during audit
-- ============================================================

-- ─── 1. Create post_shares table (referenced in code but missing) ──────────
CREATE TABLE IF NOT EXISTS public.post_shares (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(post_id, user_id)
);

ALTER TABLE public.post_shares ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "post_shares_select" ON public.post_shares;
CREATE POLICY "post_shares_select" ON public.post_shares
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "post_shares_insert" ON public.post_shares;
CREATE POLICY "post_shares_insert" ON public.post_shares
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "post_shares_delete" ON public.post_shares;
CREATE POLICY "post_shares_delete" ON public.post_shares
  FOR DELETE TO authenticated USING (user_id = auth.uid());

-- ─── 2. Fix post_likes unique constraint (prevent duplicate likes) ──────────
ALTER TABLE public.post_likes
  DROP CONSTRAINT IF EXISTS post_likes_post_id_user_id_key;

ALTER TABLE public.post_likes
  ADD CONSTRAINT post_likes_post_id_user_id_key UNIQUE (post_id, user_id);

-- ─── 3. Fix saved_posts unique constraint (prevent duplicate saves) ─────────
ALTER TABLE public.saved_posts
  DROP CONSTRAINT IF EXISTS saved_posts_user_id_post_id_key;

ALTER TABLE public.saved_posts
  ADD CONSTRAINT saved_posts_user_id_post_id_key UNIQUE (user_id, post_id);

-- ─── 4. Fix friendships unique constraint (prevent duplicate requests) ──────
ALTER TABLE public.friendships
  DROP CONSTRAINT IF EXISTS friendships_requester_id_addressee_id_key;

ALTER TABLE public.friendships
  ADD CONSTRAINT friendships_requester_id_addressee_id_key UNIQUE (requester_id, addressee_id);

-- ─── 5. Fix reports table: add 'pending' as valid status alias ─────────────
-- The code uses 'pending' but the enum only has 'open'. 
-- Add a check that maps 'pending' → 'open' via a trigger, or just add 'pending' to enum.
-- Safest: add 'pending' to the enum
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum
    WHERE enumlabel = 'pending'
      AND enumtypid = (SELECT oid FROM pg_type WHERE typname = 'report_status')
  ) THEN
    ALTER TYPE public.report_status ADD VALUE IF NOT EXISTS 'pending';
  END IF;
END $$;

-- ─── 6. Fix groups table: ensure cover_url column exists ────────────────────
-- Code uses 'cover_url' but schema has 'cover_url' — verify and add if missing
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'groups' AND column_name = 'cover_url'
  ) THEN
    ALTER TABLE public.groups ADD COLUMN cover_url TEXT DEFAULT '';
  END IF;
END $$;

-- ─── 7. Ensure groups.tags column exists (used in createGroup) ──────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'groups' AND column_name = 'tags'
  ) THEN
    ALTER TABLE public.groups ADD COLUMN tags JSONB DEFAULT '[]'::jsonb;
  END IF;
END $$;

-- ─── 8. Ensure groups.avatar_url column exists (used in createGroup) ────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'groups' AND column_name = 'avatar_url'
  ) THEN
    ALTER TABLE public.groups ADD COLUMN avatar_url TEXT DEFAULT '';
  END IF;
END $$;

-- ─── 9. Ensure messages table does NOT require receiver_id ──────────────────
-- The code sends receiver_id but the schema doesn't have it.
-- Add it as nullable so existing inserts don't fail.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'receiver_id'
  ) THEN
    ALTER TABLE public.messages ADD COLUMN receiver_id UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL;
  END IF;
END $$;

-- ─── 10. Add missing performance indexes ────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id ON public.messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_messages_sender_id ON public.messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_messages_created_at ON public.messages(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_posts_author_id ON public.posts(author_id);
CREATE INDEX IF NOT EXISTS idx_posts_created_at ON public.posts(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_post_comments_post_id ON public.post_comments(post_id);
CREATE INDEX IF NOT EXISTS idx_post_likes_post_id ON public.post_likes(post_id);
CREATE INDEX IF NOT EXISTS idx_post_likes_user_id ON public.post_likes(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_recipient_id ON public.notifications(recipient_id);
CREATE INDEX IF NOT EXISTS idx_notifications_is_read ON public.notifications(is_read);
CREATE INDEX IF NOT EXISTS idx_conversation_participants_user_id ON public.conversation_participants(user_id);
CREATE INDEX IF NOT EXISTS idx_conversation_participants_conversation_id ON public.conversation_participants(conversation_id);

-- ─── 11. Ensure notifications table has all required columns ────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'notifications' AND column_name = 'reference_id'
  ) THEN
    ALTER TABLE public.notifications ADD COLUMN reference_id UUID;
  END IF;
END $$;

-- ─── 12. Ensure user_profiles has onboarding_completed column ───────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'user_profiles' AND column_name = 'onboarding_completed'
  ) THEN
    ALTER TABLE public.user_profiles ADD COLUMN onboarding_completed BOOLEAN DEFAULT false;
  END IF;
END $$;

-- ─── 13. Ensure user_profiles has active_pet_id column ──────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'user_profiles' AND column_name = 'active_pet_id'
  ) THEN
    ALTER TABLE public.user_profiles ADD COLUMN active_pet_id UUID REFERENCES public.pets(id) ON DELETE SET NULL;
  END IF;
END $$;

-- ─── 14. Ensure user_profiles has consent columns ───────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'user_profiles' AND column_name = 'terms_accepted'
  ) THEN
    ALTER TABLE public.user_profiles ADD COLUMN terms_accepted BOOLEAN DEFAULT false;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'user_profiles' AND column_name = 'age_verified'
  ) THEN
    ALTER TABLE public.user_profiles ADD COLUMN age_verified BOOLEAN DEFAULT false;
  END IF;
END $$;

-- ─── 15. Ensure group_posts has RLS for UPDATE ──────────────────────────────
DROP POLICY IF EXISTS "group_posts_update" ON public.group_posts;
CREATE POLICY "group_posts_update" ON public.group_posts
  FOR UPDATE TO authenticated USING (author_id = auth.uid()) WITH CHECK (author_id = auth.uid());

-- ─── 16. Ensure post_comments has proper RLS ────────────────────────────────
-- Allow authenticated users to INSERT comments (author_id = their uid)
DROP POLICY IF EXISTS "post_comments_insert" ON public.post_comments;
CREATE POLICY "post_comments_insert" ON public.post_comments
  FOR INSERT TO authenticated
  WITH CHECK (author_id = auth.uid());

-- Allow anyone authenticated to read visible comments
DROP POLICY IF EXISTS "post_comments_select" ON public.post_comments;
CREATE POLICY "post_comments_select" ON public.post_comments
  FOR SELECT TO authenticated
  USING (is_visible = true);

-- Allow author to delete own comments
DROP POLICY IF EXISTS "post_comments_delete" ON public.post_comments;
CREATE POLICY "post_comments_delete" ON public.post_comments
  FOR DELETE TO authenticated
  USING (author_id = auth.uid());

-- ─── 17. Ensure messages RLS allows participants to read ────────────────────
DROP POLICY IF EXISTS "messages_select_participants" ON public.messages;
CREATE POLICY "messages_select_participants" ON public.messages
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.conversation_participants cp
      WHERE cp.conversation_id = messages.conversation_id
        AND cp.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "messages_insert_participants" ON public.messages;
CREATE POLICY "messages_insert_participants" ON public.messages
  FOR INSERT TO authenticated
  WITH CHECK (
    sender_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.conversation_participants cp
      WHERE cp.conversation_id = messages.conversation_id
        AND cp.user_id = auth.uid()
    )
  );

-- ─── 18. Ensure conversations RLS ───────────────────────────────────────────
DROP POLICY IF EXISTS "conversations_select_participants" ON public.conversations;
CREATE POLICY "conversations_select_participants" ON public.conversations
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.conversation_participants cp
      WHERE cp.conversation_id = conversations.id
        AND cp.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "conversations_insert_authenticated" ON public.conversations;
CREATE POLICY "conversations_insert_authenticated" ON public.conversations
  FOR INSERT TO authenticated
  WITH CHECK (true);

-- ─── 19. Enable Realtime on critical tables ──────────────────────────────────
DO $$
BEGIN
  -- Add tables to realtime publication if not already added
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.conversations;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.post_comments;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.post_likes;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.user_profiles;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
END $$;

-- ─── 20. Fix calculate_compatibility RPC (fallback used in match scoring) ────
CREATE OR REPLACE FUNCTION public.calculate_compatibility(
  user_a_id UUID,
  user_b_id UUID
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  user_a RECORD;
  user_b RECORD;
  score INTEGER := 50;
  shared_hyperfocuses INTEGER := 0;
  shared_interests INTEGER := 0;
BEGIN
  SELECT neurodiv_type, hyperfocuses, interests
  INTO user_a
  FROM public.user_profiles WHERE id = user_a_id;

  SELECT neurodiv_type, hyperfocuses, interests
  INTO user_b
  FROM public.user_profiles WHERE id = user_b_id;

  IF NOT FOUND THEN
    RETURN 50;
  END IF;

  -- Same neurotype bonus
  IF user_a.neurodiv_type IS NOT NULL AND user_a.neurodiv_type = user_b.neurodiv_type THEN
    score := score + 20;
  END IF;

  -- Shared hyperfocuses bonus (up to 20 pts)
  SELECT COUNT(*) INTO shared_hyperfocuses
  FROM jsonb_array_elements_text(COALESCE(user_a.hyperfocuses, '[]'::jsonb)) a_tag
  WHERE a_tag IN (
    SELECT jsonb_array_elements_text(COALESCE(user_b.hyperfocuses, '[]'::jsonb))
  );
  score := score + LEAST(shared_hyperfocuses * 5, 20);

  -- Shared interests bonus (up to 10 pts)
  SELECT COUNT(*) INTO shared_interests
  FROM jsonb_array_elements_text(COALESCE(user_a.interests, '[]'::jsonb)) a_int
  WHERE a_int IN (
    SELECT jsonb_array_elements_text(COALESCE(user_b.interests, '[]'::jsonb))
  );
  score := score + LEAST(shared_interests * 2, 10);

  RETURN LEAST(score, 100);
END;
$$;
