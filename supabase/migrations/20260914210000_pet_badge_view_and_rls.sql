-- Migration: Pet Badge – SQL View + Storage RLS for pets subfolder
-- Adds a reusable DB view that returns the user profile joined with the active pet
-- in a single query, and hardens Storage RLS so only the pet owner can write
-- to the pets/ subfolder inside the avatars bucket.

-- ─────────────────────────────────────────────────────────────
-- 1. SQL VIEW: profile_with_active_pet
--    Returns every user_profiles column plus a nested active_pet JSON object
--    (id, name, photo_url).  Consumers add ?v=<timestamp> in the app layer
--    for cache-busting (views cannot embed runtime timestamps).
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW public.profile_with_active_pet AS
SELECT
  up.id,
  up.email,
  up.full_name,
  up.username,
  up.bio,
  up.avatar_url,
  up.neurodiv_type,
  up.role,
  up.is_active,
  up.hyperfocuses,
  up.interests,
  up.communication_preferences,
  up.values_and_ideas,
  up.communication_styles,
  up.active_pet_id,
  up.created_at,
  up.updated_at,
  -- Active pet as a JSON object (NULL when no active pet is set)
  CASE
    WHEN p.id IS NOT NULL THEN
      jsonb_build_object(
        'id',        p.id,
        'name',      p.name,
        'photo_url', COALESCE(p.photo_url, '')
      )
    ELSE NULL
  END AS active_pet
FROM public.user_profiles up
LEFT JOIN public.pets p
  ON p.id = up.active_pet_id
 AND p.is_active = true;

-- Grant SELECT on the view to authenticated users
GRANT SELECT ON public.profile_with_active_pet TO authenticated;

-- ─────────────────────────────────────────────────────────────
-- 2. RPC FUNCTION: get_my_profile_with_pet
--    Wraps the view so the Flutter client can call it via rpc()
--    and receive a single row for the current user.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_my_profile_with_pet()
RETURNS SETOF public.profile_with_active_pet
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT *
  FROM public.profile_with_active_pet
  WHERE id = auth.uid();
$$;

GRANT EXECUTE ON FUNCTION public.get_my_profile_with_pet() TO authenticated;

-- ─────────────────────────────────────────────────────────────
-- 3. STORAGE RLS – pets subfolder inside the avatars bucket
--    Path convention: <user_id>/pets/<filename>
--    (storage.foldername returns an array; index [1] = first segment,
--     index [2] = second segment)
-- ─────────────────────────────────────────────────────────────

-- INSERT: only the owner can upload to their own pets/ subfolder
DROP POLICY IF EXISTS "Users can upload their own pet photos" ON storage.objects;
CREATE POLICY "Users can upload their own pet photos"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'avatars'
  AND (storage.foldername(name))[1] = auth.uid()::text
  AND (storage.foldername(name))[2] = 'pets'
);

-- UPDATE: only the owner can overwrite their own pet photos
DROP POLICY IF EXISTS "Users can update their own pet photos" ON storage.objects;
CREATE POLICY "Users can update their own pet photos"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'avatars'
  AND (storage.foldername(name))[1] = auth.uid()::text
  AND (storage.foldername(name))[2] = 'pets'
);

-- DELETE: only the owner can remove their own pet photos
DROP POLICY IF EXISTS "Users can delete their own pet photos" ON storage.objects;
CREATE POLICY "Users can delete their own pet photos"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'avatars'
  AND (storage.foldername(name))[1] = auth.uid()::text
  AND (storage.foldername(name))[2] = 'pets'
);

-- SELECT: public read (already covered by the existing "Public read access for avatars"
-- policy, but we add an explicit one for clarity and forward-compatibility)
DROP POLICY IF EXISTS "Public read access for pet photos" ON storage.objects;
CREATE POLICY "Public read access for pet photos"
ON storage.objects FOR SELECT
TO public
USING (
  bucket_id = 'avatars'
  AND (storage.foldername(name))[2] = 'pets'
);
