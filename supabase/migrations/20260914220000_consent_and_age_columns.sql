-- Migration: Add age verification and consent columns to user_profiles
-- Step 9/9 onboarding: LGPD/GDPR compliance fields

ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS birth_date DATE,
  ADD COLUMN IF NOT EXISTS is_adult BOOLEAN DEFAULT true,
  ADD COLUMN IF NOT EXISTS push_notifications_enabled BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS location_permissions_enabled BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS camera_gallery_enabled BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS microphone_enabled BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS sensitive_data_consent BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS privacy_policy_accepted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS terms_accepted_at TIMESTAMPTZ;
