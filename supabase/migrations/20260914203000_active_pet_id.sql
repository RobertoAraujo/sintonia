-- Migration: Add active_pet_id to user_profiles
-- Allows each user to designate one pet as their "active" pet shown on the profile badge.

-- 1. Add active_pet_id column to user_profiles (nullable FK to pets)
ALTER TABLE public.user_profiles
ADD COLUMN IF NOT EXISTS active_pet_id UUID REFERENCES public.pets(id) ON DELETE SET NULL;

-- 2. Index for fast lookups
CREATE INDEX IF NOT EXISTS idx_user_profiles_active_pet_id
  ON public.user_profiles(active_pet_id);

-- 3. Auto-set active_pet_id to the first pet when a new pet is created
--    (only if the user has no active pet yet)
CREATE OR REPLACE FUNCTION public.handle_new_pet_active()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.user_profiles
  SET active_pet_id = NEW.id
  WHERE id = NEW.owner_id
    AND active_pet_id IS NULL;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_pet_created_set_active ON public.pets;
CREATE TRIGGER on_pet_created_set_active
  AFTER INSERT ON public.pets
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_pet_active();
