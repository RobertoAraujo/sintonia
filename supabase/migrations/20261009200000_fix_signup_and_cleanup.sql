-- ============================================================
-- Fix 1: Auto-confirm email on signup
-- Creates a trigger that sets email_confirmed_at automatically
-- so new accounts don't require email verification
-- ============================================================

CREATE OR REPLACE FUNCTION public.auto_confirm_email()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Auto-confirm email so users can log in immediately after signup
  IF NEW.email_confirmed_at IS NULL THEN
    NEW.email_confirmed_at := now();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS auto_confirm_email_trigger ON auth.users;
CREATE TRIGGER auto_confirm_email_trigger
  BEFORE INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.auto_confirm_email();

-- Also confirm any existing unconfirmed users
UPDATE auth.users
SET email_confirmed_at = now(), updated_at = now()
WHERE email_confirmed_at IS NULL;

-- ============================================================
-- Fix 2: Clean all seed/demo data
-- Remove all data inserted by previous seed migrations
-- ============================================================

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
    DELETE FROM auth.users WHERE id = ANY(demo_user_ids);
    RAISE NOTICE 'Deleted % demo users and all related data', array_length(demo_user_ids, 1);
  ELSE
    RAISE NOTICE 'No demo users found to delete';
  END IF;

  -- Also clean any remaining orphaned posts (from seed migration)
  DELETE FROM public.post_likes WHERE post_id NOT IN (SELECT id FROM public.posts);
  DELETE FROM public.post_comments WHERE post_id NOT IN (SELECT id FROM public.posts);
  DELETE FROM public.saved_posts WHERE post_id NOT IN (SELECT id FROM public.posts);

  RAISE NOTICE 'Database cleanup complete';
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'Cleanup error: % %', SQLERRM, SQLSTATE;
END $$;
