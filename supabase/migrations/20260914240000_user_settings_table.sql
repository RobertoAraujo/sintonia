-- Create user_settings table for persistent app preferences
CREATE TABLE IF NOT EXISTS public.user_settings (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  dark_mode BOOLEAN DEFAULT false,
  notify_messages BOOLEAN DEFAULT true,
  notify_friendships BOOLEAN DEFAULT true,
  notify_feed BOOLEAN DEFAULT true,
  notify_ai_suggestions BOOLEAN DEFAULT false,
  is_public_profile BOOLEAN DEFAULT true,
  show_hyperfocus BOOLEAN DEFAULT true,
  show_interests BOOLEAN DEFAULT true,
  show_pets BOOLEAN DEFAULT true,
  allow_direct_messages BOOLEAN DEFAULT true,
  reduce_animations BOOLEAN DEFAULT false,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.user_settings ENABLE ROW LEVEL SECURITY;

-- Users can only read/write their own settings
CREATE POLICY "user_settings_select_own" ON public.user_settings
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "user_settings_insert_own" ON public.user_settings
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "user_settings_update_own" ON public.user_settings
  FOR UPDATE USING (auth.uid() = user_id);

-- Create blocked_users table if not exists
CREATE TABLE IF NOT EXISTS public.blocked_users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  blocker_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  blocked_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(blocker_id, blocked_user_id)
);

ALTER TABLE public.blocked_users ENABLE ROW LEVEL SECURITY;

CREATE POLICY "blocked_users_select_own" ON public.blocked_users
  FOR SELECT USING (auth.uid() = blocker_id);

CREATE POLICY "blocked_users_insert_own" ON public.blocked_users
  FOR INSERT WITH CHECK (auth.uid() = blocker_id);

CREATE POLICY "blocked_users_delete_own" ON public.blocked_users
  FOR DELETE USING (auth.uid() = blocker_id);

-- Auto-update updated_at on user_settings
CREATE OR REPLACE FUNCTION public.update_user_settings_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_user_settings_updated_at ON public.user_settings;
CREATE TRIGGER trg_user_settings_updated_at
  BEFORE UPDATE ON public.user_settings
  FOR EACH ROW EXECUTE FUNCTION public.update_user_settings_updated_at();
