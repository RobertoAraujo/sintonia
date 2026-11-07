-- Migration: user_2fa_codes table for 2FA email verification during login
-- Timestamp: 20260918220100

CREATE TABLE IF NOT EXISTS public.user_2fa_codes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  code TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '10 minutes'),
  used BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_user_2fa_codes_user_id ON public.user_2fa_codes(user_id);
CREATE INDEX IF NOT EXISTS idx_user_2fa_codes_expires_at ON public.user_2fa_codes(expires_at);

ALTER TABLE public.user_2fa_codes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "service_role_manage_2fa_codes" ON public.user_2fa_codes;
CREATE POLICY "service_role_manage_2fa_codes"
  ON public.user_2fa_codes
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- Users can only read their own codes (for client-side validation if needed)
DROP POLICY IF EXISTS "users_read_own_2fa_codes" ON public.user_2fa_codes;
CREATE POLICY "users_read_own_2fa_codes"
  ON public.user_2fa_codes
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());
