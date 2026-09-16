-- ============================================================
-- SintonIA AI Sessions Migration
-- Persists SintonIA mental health AI chat history per user
-- ============================================================

-- ── Table ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.sintonia_ai_sessions (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID        NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  role        TEXT        NOT NULL CHECK (role IN ('user', 'assistant')),
  content     TEXT        NOT NULL DEFAULT '',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ── Indexes ──────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_sintonia_ai_sessions_user_id
  ON public.sintonia_ai_sessions(user_id);

CREATE INDEX IF NOT EXISTS idx_sintonia_ai_sessions_created_at
  ON public.sintonia_ai_sessions(created_at DESC);

-- ── RLS ──────────────────────────────────────────────────────
ALTER TABLE public.sintonia_ai_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_manage_own_sintonia_ai_sessions" ON public.sintonia_ai_sessions;
CREATE POLICY "users_manage_own_sintonia_ai_sessions"
  ON public.sintonia_ai_sessions
  FOR ALL
  TO authenticated
  USING  (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- ── Security: add missing columns to user_profiles ───────────
ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS values_and_ideas JSONB DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS communication_styles JSONB DEFAULT '[]'::jsonb;

-- ── Security: ensure RLS is enabled on all core tables ───────
ALTER TABLE public.user_profiles          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.posts                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.post_likes             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.post_comments          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.saved_posts            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.friendships            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.groups                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.group_members          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages               ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pets                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pet_diary_entries      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pet_diary_likes        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stories                ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_diary_entries     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.compatibility_scores   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reports                ENABLE ROW LEVEL SECURITY;
