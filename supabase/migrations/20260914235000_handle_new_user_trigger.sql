-- ============================================================
-- Auto-create user_profiles row when a new auth user signs up
-- Uses SECURITY DEFINER to bypass RLS during initial profile creation
-- ============================================================

-- Trigger function: reads raw_user_meta_data and inserts into user_profiles
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.user_profiles (
    id,
    email,
    full_name,
    username
  )
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
    COALESCE(NEW.raw_user_meta_data->>'username', '')
  )
  ON CONFLICT (id) DO NOTHING;

  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    -- Never block auth signup due to profile creation failure
    RAISE NOTICE 'handle_new_user error: %', SQLERRM;
    RETURN NEW;
END;
$$;

-- Drop and recreate trigger to ensure idempotency
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();
