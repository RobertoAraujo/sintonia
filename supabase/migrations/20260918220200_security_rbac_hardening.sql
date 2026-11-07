-- ============================================================
-- Security Hardening: RBAC RLS Policy Enforcement
-- Ensures users can only access/modify their own data.
-- Adds rate-limiting helper table for brute-force tracking.
-- ============================================================

-- ── 1. Verify and harden user_profiles RLS ──────────────────────────────────

-- Ensure RLS is enabled on user_profiles
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;

-- Drop and recreate policies to ensure correct RBAC enforcement
DROP POLICY IF EXISTS "users_can_update_own_profile" ON public.user_profiles;
CREATE POLICY "users_can_update_own_profile"
  ON public.user_profiles
  FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "users_can_delete_own_profile" ON public.user_profiles;
CREATE POLICY "users_can_delete_own_profile"
  ON public.user_profiles
  FOR DELETE
  USING (auth.uid() = id);

-- ── 2. Harden user_settings RLS ─────────────────────────────────────────────

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'user_settings'
  ) THEN
    ALTER TABLE public.user_settings ENABLE ROW LEVEL SECURITY;

    DROP POLICY IF EXISTS "users_own_settings_select" ON public.user_settings;
    CREATE POLICY "users_own_settings_select"
      ON public.user_settings FOR SELECT
      USING (auth.uid() = user_id);

    DROP POLICY IF EXISTS "users_own_settings_insert" ON public.user_settings;
    CREATE POLICY "users_own_settings_insert"
      ON public.user_settings FOR INSERT
      WITH CHECK (auth.uid() = user_id);

    DROP POLICY IF EXISTS "users_own_settings_update" ON public.user_settings;
    CREATE POLICY "users_own_settings_update"
      ON public.user_settings FOR UPDATE
      USING (auth.uid() = user_id)
      WITH CHECK (auth.uid() = user_id);

    DROP POLICY IF EXISTS "users_own_settings_delete" ON public.user_settings;
    CREATE POLICY "users_own_settings_delete"
      ON public.user_settings FOR DELETE
      USING (auth.uid() = user_id);
  END IF;
END $$;

-- ── 3. Harden sintonia_ai_sessions RLS ──────────────────────────────────────

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'sintonia_ai_sessions'
  ) THEN
    ALTER TABLE public.sintonia_ai_sessions ENABLE ROW LEVEL SECURITY;

    DROP POLICY IF EXISTS "users_own_ai_sessions_select" ON public.sintonia_ai_sessions;
    CREATE POLICY "users_own_ai_sessions_select"
      ON public.sintonia_ai_sessions FOR SELECT
      USING (auth.uid() = user_id);

    DROP POLICY IF EXISTS "users_own_ai_sessions_insert" ON public.sintonia_ai_sessions;
    CREATE POLICY "users_own_ai_sessions_insert"
      ON public.sintonia_ai_sessions FOR INSERT
      WITH CHECK (auth.uid() = user_id);

    DROP POLICY IF EXISTS "users_own_ai_sessions_update" ON public.sintonia_ai_sessions;
    CREATE POLICY "users_own_ai_sessions_update"
      ON public.sintonia_ai_sessions FOR UPDATE
      USING (auth.uid() = user_id)
      WITH CHECK (auth.uid() = user_id);

    DROP POLICY IF EXISTS "users_own_ai_sessions_delete" ON public.sintonia_ai_sessions;
    CREATE POLICY "users_own_ai_sessions_delete"
      ON public.sintonia_ai_sessions FOR DELETE
      USING (auth.uid() = user_id);
  END IF;
END $$;

-- ── 4. Harden ai_chat_history RLS ───────────────────────────────────────────

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'ai_chat_history'
  ) THEN
    ALTER TABLE public.ai_chat_history ENABLE ROW LEVEL SECURITY;

    DROP POLICY IF EXISTS "users_own_chat_history_select" ON public.ai_chat_history;
    CREATE POLICY "users_own_chat_history_select"
      ON public.ai_chat_history FOR SELECT
      USING (auth.uid() = user_id);

    DROP POLICY IF EXISTS "users_own_chat_history_insert" ON public.ai_chat_history;
    CREATE POLICY "users_own_chat_history_insert"
      ON public.ai_chat_history FOR INSERT
      WITH CHECK (auth.uid() = user_id);

    DROP POLICY IF EXISTS "users_own_chat_history_delete" ON public.ai_chat_history;
    CREATE POLICY "users_own_chat_history_delete"
      ON public.ai_chat_history FOR DELETE
      USING (auth.uid() = user_id);
  END IF;
END $$;

-- ── 5. Harden notifications RLS ─────────────────────────────────────────────

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'notifications'
  ) THEN
    ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

    DROP POLICY IF EXISTS "users_own_notifications_select" ON public.notifications;
    CREATE POLICY "users_own_notifications_select"
      ON public.notifications FOR SELECT
      USING (auth.uid() = recipient_id);

    DROP POLICY IF EXISTS "users_own_notifications_update" ON public.notifications;
    CREATE POLICY "users_own_notifications_update"
      ON public.notifications FOR UPDATE
      USING (auth.uid() = recipient_id)
      WITH CHECK (auth.uid() = recipient_id);

    DROP POLICY IF EXISTS "users_own_notifications_delete" ON public.notifications;
    CREATE POLICY "users_own_notifications_delete"
      ON public.notifications FOR DELETE
      USING (auth.uid() = recipient_id);
  END IF;
END $$;

-- ── 6. Security audit log table ─────────────────────────────────────────────
-- Tracks security-relevant events for monitoring and incident response.

CREATE TABLE IF NOT EXISTS public.security_audit_log (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  event_type text NOT NULL, -- 'login_success', 'login_failed', 'password_reset', '2fa_enabled', etc.
  ip_address text,
  user_agent text,
  metadata jsonb DEFAULT '{}',
  created_at timestamptz DEFAULT now() NOT NULL
);

ALTER TABLE public.security_audit_log ENABLE ROW LEVEL SECURITY;

-- Only service_role can insert audit logs (from edge functions/backend)
DROP POLICY IF EXISTS "service_role_insert_audit_log" ON public.security_audit_log;
CREATE POLICY "service_role_insert_audit_log"
  ON public.security_audit_log FOR INSERT
  TO service_role
  WITH CHECK (true);

-- Users can only read their own audit log entries
DROP POLICY IF EXISTS "users_read_own_audit_log" ON public.security_audit_log;
CREATE POLICY "users_read_own_audit_log"
  ON public.security_audit_log FOR SELECT
  USING (auth.uid() = user_id);

-- Index for performance
CREATE INDEX IF NOT EXISTS idx_security_audit_log_user_id
  ON public.security_audit_log(user_id);

CREATE INDEX IF NOT EXISTS idx_security_audit_log_event_type
  ON public.security_audit_log(event_type);

CREATE INDEX IF NOT EXISTS idx_security_audit_log_created_at
  ON public.security_audit_log(created_at DESC);
