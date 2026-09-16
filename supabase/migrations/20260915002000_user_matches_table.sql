-- ============================================================
-- user_matches table: stores AI-powered compatibility scores
-- between pairs of users (Gemini via Lambda)
-- ============================================================

CREATE TABLE IF NOT EXISTS public.user_matches (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id_1 UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  user_id_2 UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  compatibility_score INTEGER NOT NULL DEFAULT 50 CHECK (compatibility_score BETWEEN 0 AND 100),
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (user_id_1, user_id_2)
);

CREATE INDEX IF NOT EXISTS idx_user_matches_user_id_1 ON public.user_matches(user_id_1);
CREATE INDEX IF NOT EXISTS idx_user_matches_user_id_2 ON public.user_matches(user_id_2);

-- Enable RLS
ALTER TABLE public.user_matches ENABLE ROW LEVEL SECURITY;

-- Authenticated users can read matches involving themselves
DROP POLICY IF EXISTS "users_read_own_matches" ON public.user_matches;
CREATE POLICY "users_read_own_matches" ON public.user_matches
  FOR SELECT TO authenticated
  USING (user_id_1 = auth.uid() OR user_id_2 = auth.uid());

-- Authenticated users can insert/update matches where they are user_id_1
DROP POLICY IF EXISTS "users_upsert_own_matches" ON public.user_matches;
CREATE POLICY "users_upsert_own_matches" ON public.user_matches
  FOR ALL TO authenticated
  USING (user_id_1 = auth.uid())
  WITH CHECK (user_id_1 = auth.uid());

-- Enable Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.user_matches;
