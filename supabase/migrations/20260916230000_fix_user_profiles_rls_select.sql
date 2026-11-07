-- Fix: Allow authenticated users to SELECT all user_profiles
-- This is required for social features: chat contact names/avatars,
-- friend lists, profile search, etc.
-- Without this policy, fetchConversations cannot read other users' profiles,
-- causing the conversation list to show "Conversa" with no avatar.

-- Drop any existing conflicting SELECT policy
DROP POLICY IF EXISTS "users_can_view_all_profiles" ON public.user_profiles;
DROP POLICY IF EXISTS "authenticated_can_read_all_profiles" ON public.user_profiles;
DROP POLICY IF EXISTS "public_profiles_are_viewable" ON public.user_profiles;

-- Allow any authenticated user to read any profile (needed for chat, friends, search)
CREATE POLICY "authenticated_can_read_all_profiles"
ON public.user_profiles
FOR SELECT
TO authenticated
USING (true);
