-- ============================================================
-- delete_user_account: LGPD / Right to be Forgotten
-- Deletes all user data and the auth account permanently.
-- Called via RPC from the Flutter app after re-confirmation.
-- ============================================================

CREATE OR REPLACE FUNCTION public.delete_user_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID;
  v_storage_path TEXT;
  v_file RECORD;
BEGIN
  -- 1. Identify the calling user
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- 2. Delete Storage files: avatars bucket (avatar + pet photos)
  --    List and delete files under <uid>/ prefix in the avatars bucket.
  --    We use storage.objects directly since we have SECURITY DEFINER.
  DELETE FROM storage.objects
  WHERE bucket_id = 'avatars'
    AND (name LIKE v_uid::text || '/%' OR name = v_uid::text);

  -- 3. Delete Storage files: posts bucket (post images)
  DELETE FROM storage.objects
  WHERE bucket_id = 'posts'
    AND (name LIKE v_uid::text || '/%' OR name = v_uid::text);

  -- 4. Delete application data in dependency order
  --    (Most tables have ON DELETE CASCADE from user_profiles,
  --     but we delete explicitly for clarity and LGPD audit trail.)

  -- Notifications
  DELETE FROM public.notifications WHERE user_id = v_uid OR actor_id = v_uid;

  -- AI sessions
  DELETE FROM public.sintonia_ai_sessions WHERE user_id = v_uid;

  -- Post interactions
  DELETE FROM public.post_likes WHERE user_id = v_uid;
  DELETE FROM public.post_comments WHERE author_id = v_uid;
  DELETE FROM public.saved_posts WHERE user_id = v_uid;

  -- Posts (and their cascaded likes/comments)
  DELETE FROM public.posts WHERE author_id = v_uid;

  -- Messages and conversations
  DELETE FROM public.messages WHERE sender_id = v_uid;
  DELETE FROM public.conversation_participants WHERE user_id = v_uid;

  -- Friendships
  DELETE FROM public.friendships
  WHERE requester_id = v_uid OR addressee_id = v_uid;

  -- Group memberships
  DELETE FROM public.group_members WHERE user_id = v_uid;

  -- Groups created by user
  DELETE FROM public.groups WHERE creator_id = v_uid;

  -- Pet diary entries
  DELETE FROM public.pet_diary_entries WHERE owner_id = v_uid;

  -- Pets
  DELETE FROM public.pets WHERE owner_id = v_uid;

  -- User consents (if table exists)
  DELETE FROM public.user_consents WHERE user_id = v_uid;

  -- User profile (cascades remaining FK references)
  DELETE FROM public.user_profiles WHERE id = v_uid;

  -- 5. Delete the auth account via Supabase admin API
  --    auth.users deletion is handled by the CASCADE on user_profiles.id FK,
  --    but we call it explicitly to ensure auth session is invalidated.
  DELETE FROM auth.users WHERE id = v_uid;

END;
$$;

-- Grant execute to authenticated users only
REVOKE ALL ON FUNCTION public.delete_user_account() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_user_account() TO authenticated;

-- Add a comment for documentation
COMMENT ON FUNCTION public.delete_user_account() IS
  'LGPD Right to be Forgotten: permanently deletes all user data, storage files, and auth account. Called by the authenticated user themselves.';
