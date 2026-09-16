-- ============================================================
-- Messages table: add missing columns + Realtime
-- The messages table already exists from the base schema.
-- We only add the new columns if they are not already present.
-- ============================================================

-- Add receiver_id column if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'messages'
      AND column_name  = 'receiver_id'
  ) THEN
    ALTER TABLE public.messages
      ADD COLUMN receiver_id UUID REFERENCES auth.users(id) ON DELETE SET NULL;
  END IF;
END;
$$;

-- Add is_read column if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'messages'
      AND column_name  = 'is_read'
  ) THEN
    ALTER TABLE public.messages
      ADD COLUMN is_read BOOLEAN DEFAULT false;
  END IF;
END;
$$;

-- Index for fast chat queries
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id ON public.messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_messages_sender_id ON public.messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_messages_receiver_id ON public.messages(receiver_id);
CREATE INDEX IF NOT EXISTS idx_messages_created_at ON public.messages(created_at DESC);

-- RLS (table already has RLS enabled from base schema)
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read their own messages" ON public.messages;
CREATE POLICY "Users can read their own messages"
  ON public.messages FOR SELECT
  USING (
    sender_id = auth.uid() OR receiver_id = auth.uid()
    OR conversation_id IN (
      SELECT conversation_id FROM public.conversation_participants WHERE user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Users can insert messages" ON public.messages;
CREATE POLICY "Users can insert messages"
  ON public.messages FOR INSERT
  WITH CHECK (sender_id = auth.uid());

DROP POLICY IF EXISTS "Users can update read status" ON public.messages;
CREATE POLICY "Users can update read status"
  ON public.messages FOR UPDATE
  USING (receiver_id = auth.uid())
  WITH CHECK (receiver_id = auth.uid());

-- Enable Realtime on messages table
ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;

-- ============================================================
-- calculate_compatibility stored function
-- Scores compatibility between two users (0-100)
-- Weights: hyperfocuses 40%, values 35%, neurotype 15%, communication 10%
-- ============================================================

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
  profile_a RECORD;
  profile_b RECORD;

  -- Hyperfocuses / interests (weight 40%)
  a_hyperfocuses TEXT[];
  b_hyperfocuses TEXT[];
  hyperfocus_intersection INT := 0;
  hyperfocus_union INT := 0;
  hyperfocus_score FLOAT := 0;

  -- Values / beliefs (weight 35%)
  a_values TEXT[];
  b_values TEXT[];
  values_intersection INT := 0;
  values_union INT := 0;
  values_score FLOAT := 0;

  -- Neurotype similarity (weight 15%)
  neurotype_score FLOAT := 0;

  -- Communication style (weight 10%)
  a_comm TEXT[];
  b_comm TEXT[];
  comm_intersection INT := 0;
  comm_union INT := 0;
  comm_score FLOAT := 0;

  total_score FLOAT := 0;
  tag TEXT;
BEGIN
  -- Fetch both profiles
  SELECT
    hyperfocuses,
    interests,
    communication_preferences,
    neurodiv_type,
    sensory_profile,
    values_and_ideas
  INTO profile_a
  FROM public.user_profiles
  WHERE id = user_a_id;

  SELECT
    hyperfocuses,
    interests,
    communication_preferences,
    neurodiv_type,
    sensory_profile,
    values_and_ideas
  INTO profile_b
  FROM public.user_profiles
  WHERE id = user_b_id;

  -- Return 0 if either profile not found
  IF profile_a IS NULL OR profile_b IS NULL THEN
    RETURN 0;
  END IF;

  -- ── Hyperfocuses score (Jaccard similarity, weight 40%) ──────────────────
  BEGIN
    SELECT ARRAY(
      SELECT LOWER(TRIM(elem::TEXT))
      FROM jsonb_array_elements_text(COALESCE(profile_a.hyperfocuses, '[]'::jsonb)) AS elem
    ) INTO a_hyperfocuses;

    SELECT ARRAY(
      SELECT LOWER(TRIM(elem::TEXT))
      FROM jsonb_array_elements_text(COALESCE(profile_b.hyperfocuses, '[]'::jsonb)) AS elem
    ) INTO b_hyperfocuses;

    -- Count intersection
    FOREACH tag IN ARRAY COALESCE(a_hyperfocuses, ARRAY[]::TEXT[]) LOOP
      IF tag = ANY(COALESCE(b_hyperfocuses, ARRAY[]::TEXT[])) THEN
        hyperfocus_intersection := hyperfocus_intersection + 1;
      END IF;
    END LOOP;

    -- Union = |A| + |B| - |A ∩ B|
    hyperfocus_union := COALESCE(array_length(a_hyperfocuses, 1), 0)
                      + COALESCE(array_length(b_hyperfocuses, 1), 0)
                      - hyperfocus_intersection;

    IF hyperfocus_union > 0 THEN
      hyperfocus_score := hyperfocus_intersection::FLOAT / hyperfocus_union::FLOAT;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    hyperfocus_score := 0;
  END;

  -- ── Values score (Jaccard similarity, weight 35%) ────────────────────────
  BEGIN
    SELECT ARRAY(
      SELECT LOWER(TRIM(elem::TEXT))
      FROM jsonb_array_elements_text(COALESCE(profile_a.values_and_ideas, '[]'::jsonb)) AS elem
    ) INTO a_values;

    SELECT ARRAY(
      SELECT LOWER(TRIM(elem::TEXT))
      FROM jsonb_array_elements_text(COALESCE(profile_b.values_and_ideas, '[]'::jsonb)) AS elem
    ) INTO b_values;

    FOREACH tag IN ARRAY COALESCE(a_values, ARRAY[]::TEXT[]) LOOP
      IF tag = ANY(COALESCE(b_values, ARRAY[]::TEXT[])) THEN
        values_intersection := values_intersection + 1;
      END IF;
    END LOOP;

    values_union := COALESCE(array_length(a_values, 1), 0)
                  + COALESCE(array_length(b_values, 1), 0)
                  - values_intersection;

    IF values_union > 0 THEN
      values_score := values_intersection::FLOAT / values_union::FLOAT;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    values_score := 0;
  END;

  -- ── Neurotype similarity (weight 15%) ────────────────────────────────────
  BEGIN
    IF profile_a.neurodiv_type IS NOT NULL AND profile_b.neurodiv_type IS NOT NULL THEN
      IF profile_a.neurodiv_type = profile_b.neurodiv_type THEN
        neurotype_score := 1.0;
      ELSE
        neurotype_score := 0.3; -- partial credit for different neurodivergent types
      END IF;
    ELSIF profile_a.neurodiv_type IS NOT NULL OR profile_b.neurodiv_type IS NOT NULL THEN
      neurotype_score := 0.15;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    neurotype_score := 0;
  END;

  -- ── Communication style score (weight 10%) ───────────────────────────────
  BEGIN
    SELECT ARRAY(
      SELECT LOWER(TRIM(value::TEXT))
      FROM jsonb_each_text(COALESCE(profile_a.communication_preferences, '{}'::jsonb)) AS kv(key, value)
      WHERE value IS NOT NULL AND value <> ''
    ) INTO a_comm;

    SELECT ARRAY(
      SELECT LOWER(TRIM(value::TEXT))
      FROM jsonb_each_text(COALESCE(profile_b.communication_preferences, '{}'::jsonb)) AS kv(key, value)
      WHERE value IS NOT NULL AND value <> ''
    ) INTO b_comm;

    FOREACH tag IN ARRAY COALESCE(a_comm, ARRAY[]::TEXT[]) LOOP
      IF tag = ANY(COALESCE(b_comm, ARRAY[]::TEXT[])) THEN
        comm_intersection := comm_intersection + 1;
      END IF;
    END LOOP;

    comm_union := COALESCE(array_length(a_comm, 1), 0)
                + COALESCE(array_length(b_comm, 1), 0)
                - comm_intersection;

    IF comm_union > 0 THEN
      comm_score := comm_intersection::FLOAT / comm_union::FLOAT;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    comm_score := 0;
  END;

  -- ── Weighted total ────────────────────────────────────────────────────────
  total_score := (hyperfocus_score * 0.40)
               + (values_score     * 0.35)
               + (neurotype_score  * 0.15)
               + (comm_score       * 0.10);

  RETURN ROUND(total_score * 100)::INTEGER;
END;
$$;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION public.calculate_compatibility(UUID, UUID) TO authenticated;

-- ============================================================
-- get_compatible_users: returns users ordered by compatibility
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_compatible_users(
  requesting_user_id UUID,
  result_limit INT DEFAULT 20
)
RETURNS TABLE (
  user_id UUID,
  full_name TEXT,
  username TEXT,
  avatar_url TEXT,
  bio TEXT,
  neurodiv_type TEXT,
  hyperfocuses JSONB,
  interests JSONB,
  communication_preferences JSONB,
  compatibility_pct INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    p.id AS user_id,
    p.full_name,
    p.username,
    p.avatar_url,
    p.bio,
    p.neurodiv_type::TEXT,
    p.hyperfocuses,
    p.interests,
    p.communication_preferences,
    public.calculate_compatibility(requesting_user_id, p.id) AS compatibility_pct
  FROM public.user_profiles p
  WHERE p.id <> requesting_user_id
    AND p.is_active = true
    AND p.id NOT IN (
      SELECT CASE
        WHEN f.requester_id = requesting_user_id THEN f.addressee_id
        ELSE f.requester_id
      END
      FROM public.friendships f
      WHERE (f.requester_id = requesting_user_id OR f.addressee_id = requesting_user_id)
        AND f.status IN ('accepted', 'blocked')
    )
  ORDER BY compatibility_pct DESC
  LIMIT result_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_compatible_users(UUID, INT) TO authenticated;
