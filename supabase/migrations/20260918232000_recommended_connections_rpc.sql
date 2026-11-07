-- Migration: get_recommended_connections RPC
-- Adds optional geo columns to user_profiles and creates the RPC that
-- calculates compatibility score (hyperfocuses + interests) plus
-- Haversine distance between the logged-in user and all public profiles.

-- ── 1. Add optional geo / visibility columns ─────────────────────────────
ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS latitude   DOUBLE PRECISION DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS longitude  DOUBLE PRECISION DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS is_public  BOOLEAN DEFAULT true;

-- ── 2. RPC: get_recommended_connections ──────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_recommended_connections(
  current_user_id UUID,
  max_distance_km DOUBLE PRECISION DEFAULT 50.0
)
RETURNS TABLE (
  user_id          UUID,
  display_name     TEXT,
  avatar_url       TEXT,
  bio              TEXT,
  hyperfocus       TEXT[],
  interests        TEXT[],
  compatibility_score INT,
  distance_km      DOUBLE PRECISION
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  WITH current_user_profile AS (
    SELECT
      up.id,
      COALESCE(
        ARRAY(SELECT jsonb_array_elements_text(COALESCE(up.hyperfocuses, '[]'::jsonb))),
        ARRAY[]::TEXT[]
      )                                AS my_hyperfocus,
      COALESCE(
        ARRAY(SELECT jsonb_array_elements_text(COALESCE(up.interests, '[]'::jsonb))),
        ARRAY[]::TEXT[]
      )                                AS my_interests,
      up.latitude                      AS my_lat,
      up.longitude                     AS my_lng
    FROM public.user_profiles up
    WHERE up.id = current_user_id
  ),
  candidate_arrays AS (
    SELECT
      p.id,
      p.full_name,
      p.avatar_url,
      p.bio,
      p.latitude,
      p.longitude,
      p.is_public,
      COALESCE(
        ARRAY(SELECT jsonb_array_elements_text(COALESCE(p.hyperfocuses, '[]'::jsonb))),
        ARRAY[]::TEXT[]
      ) AS p_hyperfocus,
      COALESCE(
        ARRAY(SELECT jsonb_array_elements_text(COALESCE(p.interests, '[]'::jsonb))),
        ARRAY[]::TEXT[]
      ) AS p_interests
    FROM public.user_profiles p
    WHERE p.id <> current_user_id
      AND COALESCE(p.is_active, true) = true
  )
  SELECT
    ca.id                                                          AS user_id,
    COALESCE(ca.full_name, 'Usuário')::TEXT                       AS display_name,
    ca.avatar_url::TEXT,
    COALESCE(ca.bio, '')::TEXT                                     AS bio,
    ca.p_hyperfocus                                                AS hyperfocus,
    ca.p_interests                                                 AS interests,
    -- Weighted compatibility score (max 100):
    --   Each shared hyperfocus  → +30 pts  (60% weight)
    --   Each shared interest    → +15 pts  (40% weight)
    --   Community base          → +30 pts
    LEAST(
      100,
      (
        COALESCE(
          cardinality(
            ARRAY(
              SELECT unnest(ca.p_hyperfocus)
              INTERSECT
              SELECT unnest(cup.my_hyperfocus)
            )
          ), 0
        ) * 30
        +
        COALESCE(
          cardinality(
            ARRAY(
              SELECT unnest(ca.p_interests)
              INTERSECT
              SELECT unnest(cup.my_interests)
            )
          ), 0
        ) * 15
        + 30
      )
    )::INT AS compatibility_score,
    -- Haversine distance (km), NULL when coordinates are missing
    CASE
      WHEN ca.latitude IS NOT NULL AND ca.longitude IS NOT NULL
           AND cup.my_lat IS NOT NULL AND cup.my_lng IS NOT NULL THEN
        ROUND(
          (
            6371.0 * acos(
              LEAST(1.0,
                cos(radians(cup.my_lat)) * cos(radians(ca.latitude)) *
                cos(radians(ca.longitude) - radians(cup.my_lng)) +
                sin(radians(cup.my_lat)) * sin(radians(ca.latitude))
              )
            )
          )::numeric,
          1
        )::DOUBLE PRECISION
      ELSE NULL
    END AS distance_km
  FROM candidate_arrays ca, current_user_profile cup
  WHERE COALESCE(ca.is_public, true) = true
    -- Apply distance filter only when both sides have coordinates
    AND (
      ca.latitude IS NULL OR cup.my_lat IS NULL
      OR (
        6371.0 * acos(
          LEAST(1.0,
            cos(radians(cup.my_lat)) * cos(radians(ca.latitude)) *
            cos(radians(ca.longitude) - radians(cup.my_lng)) +
            sin(radians(cup.my_lat)) * sin(radians(ca.latitude))
          )
        ) <= max_distance_km
      )
    )
  ORDER BY compatibility_score DESC, distance_km ASC NULLS LAST
  LIMIT 20;
END;
$$;
