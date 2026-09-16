-- Migration: Add TEXT[] columns for multi-select onboarding fields
-- sensory_triggers, political_views, religions on user_profiles

ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS sensory_triggers TEXT[] DEFAULT ARRAY[]::TEXT[],
  ADD COLUMN IF NOT EXISTS political_views   TEXT[] DEFAULT ARRAY[]::TEXT[],
  ADD COLUMN IF NOT EXISTS religions         TEXT[] DEFAULT ARRAY[]::TEXT[];
