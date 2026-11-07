-- ============================================================
-- Fix delete_user_account: Use Storage API instead of direct
-- storage.objects table deletion (fixes error code 42501).
-- ============================================================

CREATE OR REPLACE FUNCTION public.delete_user_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID;
  v_file RECORD;
BEGIN
  -- 1. Identify the calling user
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- 2. Delete Storage files via storage.delete_object() API
  --    avatars bucket
  FOR v_file IN
    SELECT name FROM storage.objects
    WHERE bucket_id = 'avatars'
      AND (name LIKE v_uid::text || '/%' OR name = v_uid::text)
  LOOP
    PERFORM storage.delete_object('avatars', v_file.name);
  END LOOP;

  -- 3. posts bucket
  FOR v_file IN
    SELECT name FROM storage.objects
    WHERE bucket_id = 'posts'
      AND (name LIKE v_uid::text || '/%' OR name = v_uid::text)
  LOOP
    PERFORM storage.delete_object('posts', v_file.name);
  END LOOP;

  -- 4. pets bucket
  FOR v_file IN
    SELECT name FROM storage.objects
    WHERE bucket_id = 'pets'
      AND (name LIKE v_uid::text || '/%' OR name = v_uid::text)
  LOOP
    PERFORM storage.delete_object('pets', v_file.name);
  END LOOP;

  -- 5. chat-media bucket
  FOR v_file IN
    SELECT name FROM storage.objects
    WHERE bucket_id = 'chat-media'
      AND (name LIKE v_uid::text || '/%' OR name = v_uid::text)
  LOOP
    PERFORM storage.delete_object('chat-media', v_file.name);
  END LOOP;

  -- 6. Delete application data in dependency order

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

  -- User diary entries
  DELETE FROM public.user_diary_entries WHERE user_id = v_uid;

  -- User consents (if table exists)
  BEGIN
    DELETE FROM public.user_consents WHERE user_id = v_uid;
  EXCEPTION WHEN undefined_table THEN
    NULL;
  END;

  -- Blocked users
  BEGIN
    DELETE FROM public.blocked_users WHERE blocker_id = v_uid OR blocked_id = v_uid;
  EXCEPTION WHEN undefined_table THEN
    NULL;
  END;

  -- User settings
  BEGIN
    DELETE FROM public.user_settings WHERE user_id = v_uid;
  EXCEPTION WHEN undefined_table THEN
    NULL;
  END;

  -- User profile (cascades remaining FK references)
  DELETE FROM public.user_profiles WHERE id = v_uid;

  -- 7. Delete the auth account
  DELETE FROM auth.users WHERE id = v_uid;

END;
$$;

-- Grant execute to authenticated users only
REVOKE ALL ON FUNCTION public.delete_user_account() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_user_account() TO authenticated;

COMMENT ON FUNCTION public.delete_user_account() IS
  'LGPD Right to be Forgotten: permanently deletes all user data, storage files (via storage API), and auth account.';
