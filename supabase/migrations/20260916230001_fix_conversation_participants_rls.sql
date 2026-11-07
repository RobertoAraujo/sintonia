-- Fix: Allow conversation participants to read ALL participants of their conversations.
-- The previous policy "cp_select_own" only allowed reading rows where user_id = auth.uid(),
-- which blocked fetchConversations from discovering the other participant's user_id.
-- Without the other participant's user_id, the profile lookup returns empty,
-- causing the chat list to show "Conversa" with no avatar.

-- Helper function (SECURITY DEFINER bypasses RLS to avoid recursion)
CREATE OR REPLACE FUNCTION public.get_my_conversation_ids()
RETURNS SETOF UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT conversation_id
  FROM public.conversation_participants
  WHERE user_id = auth.uid();
$$;

-- Drop all existing SELECT policies on conversation_participants
DROP POLICY IF EXISTS "cp_select_own" ON public.conversation_participants;
DROP POLICY IF EXISTS "users_read_own_conversation_participants" ON public.conversation_participants;
DROP POLICY IF EXISTS "users_read_conversation_participants" ON public.conversation_participants;
DROP POLICY IF EXISTS "users_read_coparticipants" ON public.conversation_participants;

-- Allow reading ALL participants of conversations you belong to
-- (needed to discover the other user's ID for name/avatar lookup)
CREATE POLICY "users_read_conversation_participants"
ON public.conversation_participants
FOR SELECT
TO authenticated
USING (
  conversation_id IN (SELECT public.get_my_conversation_ids())
);
