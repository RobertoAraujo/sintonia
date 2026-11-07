-- ============================================================
-- Remove all demo/test accounts permanently
-- This migration deletes all demo users created by previous
-- seed and fix migrations, and removes the auto-confirm trigger
-- that was added for testing purposes.
-- ============================================================

-- Step 1: Remove all demo/test accounts and their data
DO $$
DECLARE
  demo_emails TEXT[] := ARRAY[
    'admin@sintonia.app',
    'ana.silva@email.com',
    'carlos.mendes@email.com',
    'julia.costa@email.com',
    'pedro.lima@email.com',
    'mariana.rocha@email.com'
  ];
  demo_user_ids UUID[];
BEGIN
  -- Collect demo user IDs
  SELECT ARRAY_AGG(id) INTO demo_user_ids
  FROM auth.users
  WHERE email = ANY(demo_emails);

  IF demo_user_ids IS NOT NULL AND array_length(demo_user_ids, 1) > 0 THEN
    -- Delete in dependency order (children first)
    DELETE FROM public.consent_logs WHERE user_id = ANY(demo_user_ids);
    DELETE FROM public.security_audit_log WHERE user_id = ANY(demo_user_ids);
    DELETE FROM public.user_2fa_codes WHERE user_id = ANY(demo_user_ids);
    DELETE FROM public.password_reset_codes WHERE user_id = ANY(demo_user_ids);
    DELETE FROM public.ai_chat_history WHERE user_id = ANY(demo_user_ids);
    DELETE FROM public.sintonia_ai_sessions WHERE user_id = ANY(demo_user_ids);
    DELETE FROM public.notifications WHERE user_id = ANY(demo_user_ids);
    DELETE FROM public.user_settings WHERE user_id = ANY(demo_user_ids);
    DELETE FROM public.user_matches WHERE user_id = ANY(demo_user_ids) OR matched_user_id = ANY(demo_user_ids);
    DELETE FROM public.compatibility_scores WHERE user_id = ANY(demo_user_ids) OR other_user_id = ANY(demo_user_ids);
    DELETE FROM public.blocked_users WHERE blocker_id = ANY(demo_user_ids) OR blocked_id = ANY(demo_user_ids);
    DELETE FROM public.friendships WHERE requester_id = ANY(demo_user_ids) OR addressee_id = ANY(demo_user_ids);
    DELETE FROM public.user_diary_entries WHERE user_id = ANY(demo_user_ids);
    DELETE FROM public.stories WHERE user_id = ANY(demo_user_ids);
    DELETE FROM public.post_shares WHERE user_id = ANY(demo_user_ids);
    DELETE FROM public.saved_posts WHERE user_id = ANY(demo_user_ids);
    DELETE FROM public.post_likes WHERE user_id = ANY(demo_user_ids);
    DELETE FROM public.post_comments WHERE user_id = ANY(demo_user_ids);
    DELETE FROM public.group_post_likes WHERE user_id = ANY(demo_user_ids);
    DELETE FROM public.group_posts WHERE user_id = ANY(demo_user_ids);
    DELETE FROM public.group_members WHERE user_id = ANY(demo_user_ids);
    DELETE FROM public.groups WHERE created_by = ANY(demo_user_ids);
    DELETE FROM public.messages WHERE sender_id = ANY(demo_user_ids);
    DELETE FROM public.conversation_participants WHERE user_id = ANY(demo_user_ids);
    DELETE FROM public.conversations WHERE created_by = ANY(demo_user_ids);
    DELETE FROM public.pet_diary_likes WHERE user_id = ANY(demo_user_ids);
    DELETE FROM public.pet_diary_entries WHERE user_id = ANY(demo_user_ids);
    DELETE FROM public.pets WHERE owner_id = ANY(demo_user_ids);
    DELETE FROM public.user_photos WHERE user_id = ANY(demo_user_ids);
    DELETE FROM public.reports WHERE reporter_id = ANY(demo_user_ids) OR reported_user_id = ANY(demo_user_ids);
    DELETE FROM public.posts WHERE user_id = ANY(demo_user_ids);
    DELETE FROM public.user_profiles WHERE id = ANY(demo_user_ids);
    -- Delete auth identities and sessions
    DELETE FROM auth.identities WHERE user_id = ANY(demo_user_ids);
    DELETE FROM auth.sessions WHERE user_id = ANY(demo_user_ids);
    DELETE FROM auth.refresh_tokens WHERE user_id = ANY(demo_user_ids);
    DELETE FROM auth.mfa_factors WHERE user_id = ANY(demo_user_ids);
    DELETE FROM auth.users WHERE id = ANY(demo_user_ids);
    RAISE NOTICE 'Deleted % demo users and all related data', array_length(demo_user_ids, 1);
  ELSE
    RAISE NOTICE 'No demo users found — database is already clean';
  END IF;

EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'Cleanup error (non-fatal): % %', SQLERRM, SQLSTATE;
END $$;

-- Step 2: Keep the auto-confirm trigger so real new signups work immediately
-- (This trigger was added in 20261009200000 and must remain active)
-- No changes needed here — the trigger is already in place.

-- Step 3: Clean orphaned post interactions (safety net)
DELETE FROM public.post_likes WHERE post_id NOT IN (SELECT id FROM public.posts);
DELETE FROM public.post_comments WHERE post_id NOT IN (SELECT id FROM public.posts);
DELETE FROM public.saved_posts WHERE post_id NOT IN (SELECT id FROM public.posts);
