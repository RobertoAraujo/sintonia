-- ============================================================
-- LGPD Compliance: Consent Logs + Data Export RPC
-- ============================================================

-- 1. Consent audit log table (LGPD Art. 7 & 8)
CREATE TABLE IF NOT EXISTS public.consent_logs (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  consent_type  text NOT NULL,          -- 'terms', 'privacy_policy', 'sensitive_data', '2fa_enabled'
  accepted      boolean NOT NULL DEFAULT true,
  ip_address    text,                   -- stored at acceptance time
  user_agent    text,
  accepted_at   timestamptz NOT NULL DEFAULT now(),
  revoked_at    timestamptz
);

ALTER TABLE public.consent_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own consent logs" ON public.consent_logs;
CREATE POLICY "Users can view own consent logs"
  ON public.consent_logs FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own consent logs" ON public.consent_logs;
CREATE POLICY "Users can insert own consent logs"
  ON public.consent_logs FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- 2. RPC: export_user_data — returns all personal data for LGPD Art. 18
CREATE OR REPLACE FUNCTION public.export_user_data()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_result jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT jsonb_build_object(
    'profile',        (SELECT row_to_json(p) FROM user_profiles p WHERE p.id = v_uid),
    'posts',          (SELECT jsonb_agg(row_to_json(po)) FROM posts po WHERE po.author_id = v_uid),
    'consent_logs',   (SELECT jsonb_agg(row_to_json(cl)) FROM consent_logs cl WHERE cl.user_id = v_uid),
    'friendships',    (SELECT jsonb_agg(row_to_json(f))
                       FROM friendships f
                       WHERE f.requester_id = v_uid OR f.addressee_id = v_uid),
    'notifications',  (SELECT jsonb_agg(row_to_json(n)) FROM notifications n WHERE n.recipient_id = v_uid),
    'exported_at',    now()
  ) INTO v_result;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.export_user_data() TO authenticated;

-- 3. Add consent_ip column to user_profiles if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'user_profiles'
      AND column_name  = 'consent_ip'
  ) THEN
    ALTER TABLE public.user_profiles ADD COLUMN consent_ip text;
  END IF;
END;
$$;

-- 4. Add min_age_required column (platform policy: 13+)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'user_profiles'
      AND column_name  = 'age_verified'
  ) THEN
    ALTER TABLE public.user_profiles ADD COLUMN age_verified boolean DEFAULT false;
  END IF;
END;
$$;
