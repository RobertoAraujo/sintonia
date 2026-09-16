-- First-time user setup: add onboarding_completed flag and ensure
-- neurodiv_type, hyperfocus_tags, and comm_style columns exist.

-- Add onboarding_completed column if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'user_profiles'
      AND column_name = 'onboarding_completed'
  ) THEN
    ALTER TABLE public.user_profiles
      ADD COLUMN onboarding_completed BOOLEAN NOT NULL DEFAULT FALSE;
  END IF;
END $$;

-- Add comm_style TEXT[] column if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'user_profiles'
      AND column_name = 'comm_style'
  ) THEN
    ALTER TABLE public.user_profiles
      ADD COLUMN comm_style TEXT[] DEFAULT '{}';
  END IF;
END $$;

-- Add hyperfocus_tags TEXT[] column if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'user_profiles'
      AND column_name = 'hyperfocus_tags'
  ) THEN
    ALTER TABLE public.user_profiles
      ADD COLUMN hyperfocus_tags TEXT[] DEFAULT '{}';
  END IF;
END $$;

-- Mark existing users who already have neurodiv_type set as onboarding_completed
UPDATE public.user_profiles
SET onboarding_completed = TRUE
WHERE neurodiv_type IS NOT NULL
  AND onboarding_completed = FALSE;
