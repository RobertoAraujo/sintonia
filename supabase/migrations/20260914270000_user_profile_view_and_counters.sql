-- ============================================================
-- public_user_profiles VIEW
-- Returns full profile data with computed counters in one query
-- ============================================================

CREATE OR REPLACE VIEW public.public_user_profiles AS
SELECT
  p.id,
  p.full_name                                                    AS name,
  p.username,
  p.avatar_url,
  p.bio,
  p.neurodiv_type,
  p.hyperfocuses,
  p.interests,
  p.values_and_ideas,
  p.communication_preferences,
  p.communication_styles,
  p.sensory_triggers,
  p.political_views,
  p.religions,
  p.active_pet_id,
  p.created_at,
  (
    SELECT COUNT(*)::INT
    FROM public.posts
    WHERE author_id = p.id
      AND is_published = true
  ) AS posts_count,
  (
    SELECT COUNT(*)::INT
    FROM public.friendships
    WHERE (requester_id = p.id OR addressee_id = p.id)
      AND status = 'accepted'
  ) AS friends_count
FROM public.user_profiles p
WHERE p.is_active = true;

-- Grant SELECT on the view to authenticated users
GRANT SELECT ON public.public_user_profiles TO authenticated;
GRANT SELECT ON public.public_user_profiles TO anon;
