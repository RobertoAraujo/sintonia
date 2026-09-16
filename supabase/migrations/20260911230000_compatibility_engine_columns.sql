-- ============================================================
-- Compatibility Engine: ensure all scoring columns exist
-- ============================================================

-- Add values_and_ideas column if it doesn't exist
ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS values_and_ideas JSONB DEFAULT '[]'::jsonb;

-- Add communication_styles column if it doesn't exist  
ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS communication_styles JSONB DEFAULT '[]'::jsonb;

-- Add compatibility_score_cache table for caching pre-computed scores
CREATE TABLE IF NOT EXISTS public.compatibility_scores (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_a UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  user_b UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  overall_score FLOAT NOT NULL DEFAULT 0.0,
  interests_score FLOAT NOT NULL DEFAULT 0.0,
  values_score FLOAT NOT NULL DEFAULT 0.0,
  neurotypes_score FLOAT NOT NULL DEFAULT 0.0,
  communication_score FLOAT NOT NULL DEFAULT 0.0,
  computed_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(user_a, user_b)
);

-- Index for fast lookups
CREATE INDEX IF NOT EXISTS idx_compat_user_a ON public.compatibility_scores(user_a);
CREATE INDEX IF NOT EXISTS idx_compat_user_b ON public.compatibility_scores(user_b);

-- RLS for compatibility_scores
ALTER TABLE public.compatibility_scores ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their own compatibility scores" ON public.compatibility_scores;
CREATE POLICY "Users can view their own compatibility scores"
  ON public.compatibility_scores FOR SELECT
  USING (auth.uid() = user_a OR auth.uid() = user_b);

DROP POLICY IF EXISTS "Users can insert their own compatibility scores" ON public.compatibility_scores;
CREATE POLICY "Users can insert their own compatibility scores"
  ON public.compatibility_scores FOR INSERT
  WITH CHECK (auth.uid() = user_a);

DROP POLICY IF EXISTS "Users can update their own compatibility scores" ON public.compatibility_scores;
CREATE POLICY "Users can update their own compatibility scores"
  ON public.compatibility_scores FOR UPDATE
  USING (auth.uid() = user_a);
