-- Add last_seen timestamp to user_profiles for presence tracking
ALTER TABLE public.user_profiles
ADD COLUMN IF NOT EXISTS last_seen TIMESTAMPTZ DEFAULT NULL;

-- Create index for efficient last_seen queries
CREATE INDEX IF NOT EXISTS idx_user_profiles_last_seen ON public.user_profiles(last_seen);

-- Function to update own last_seen (SECURITY DEFINER so it bypasses RLS safely)
CREATE OR REPLACE FUNCTION public.update_last_seen()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.user_profiles
  SET last_seen = now()
  WHERE id = auth.uid();
END;
$$;
