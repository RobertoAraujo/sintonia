-- Migration: password_reset_codes
-- Stores temporary 6-digit codes for password recovery (expires in 15 minutes)

CREATE TABLE IF NOT EXISTS public.password_reset_codes (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    email TEXT NOT NULL,
    code TEXT NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '15 minutes'),
    used BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_password_reset_codes_email ON public.password_reset_codes(email);
CREATE INDEX IF NOT EXISTS idx_password_reset_codes_expires_at ON public.password_reset_codes(expires_at);

ALTER TABLE public.password_reset_codes ENABLE ROW LEVEL SECURITY;

-- No direct client access — all operations go through Edge Functions (service_role)
-- We add a permissive policy only for service_role (edge functions use service_role key)
DROP POLICY IF EXISTS "service_role_manage_reset_codes" ON public.password_reset_codes;
CREATE POLICY "service_role_manage_reset_codes"
ON public.password_reset_codes
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);
