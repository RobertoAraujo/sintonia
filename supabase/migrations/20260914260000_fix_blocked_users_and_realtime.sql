-- ============================================================
-- Fix blocked_users table schema and enable Realtime
-- ============================================================

-- Ensure blocked_users table exists with correct columns
-- The previous migration used blocked_user_id; we keep that consistent.
CREATE TABLE IF NOT EXISTS public.blocked_users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  blocker_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  blocked_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(blocker_id, blocked_user_id)
);

ALTER TABLE public.blocked_users ENABLE ROW LEVEL SECURITY;

-- Drop and recreate policies to ensure correctness
DROP POLICY IF EXISTS "blocked_users_select_own" ON public.blocked_users;
CREATE POLICY "blocked_users_select_own" ON public.blocked_users
  FOR SELECT USING (auth.uid() = blocker_id);

DROP POLICY IF EXISTS "blocked_users_insert_own" ON public.blocked_users;
CREATE POLICY "blocked_users_insert_own" ON public.blocked_users
  FOR INSERT WITH CHECK (auth.uid() = blocker_id);

DROP POLICY IF EXISTS "blocked_users_delete_own" ON public.blocked_users;
CREATE POLICY "blocked_users_delete_own" ON public.blocked_users
  FOR DELETE USING (auth.uid() = blocker_id);

-- Enable Realtime on messages table (skip if already a member)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
  END IF;
END$$;

-- Enable Realtime on conversations table (skip if already a member)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'conversations'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.conversations;
  END IF;
END$$;

-- Enable Realtime on conversation_participants (skip if already a member)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'conversation_participants'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.conversation_participants;
  END IF;
END$$;
