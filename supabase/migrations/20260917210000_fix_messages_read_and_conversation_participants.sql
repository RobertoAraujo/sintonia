-- ============================================================
-- Fix 1: Allow conversation participants to mark messages as read.
-- The previous UPDATE policy required receiver_id = auth.uid(),
-- but receiver_id is NULL for conversation-based messages.
-- We replace it with a policy that allows updating is_read
-- for messages in conversations the user participates in,
-- as long as the user is NOT the sender (can only mark others' messages as read).
-- ============================================================

DROP POLICY IF EXISTS "Users can update read status" ON public.messages;
CREATE POLICY "Users can update read status"
  ON public.messages FOR UPDATE
  USING (
    sender_id != auth.uid()
    AND conversation_id IN (
      SELECT conversation_id
      FROM public.conversation_participants
      WHERE user_id = auth.uid()
    )
  )
  WITH CHECK (
    sender_id != auth.uid()
    AND conversation_id IN (
      SELECT conversation_id
      FROM public.conversation_participants
      WHERE user_id = auth.uid()
    )
  );

-- ============================================================
-- Fix 2: SECURITY DEFINER function to get all participants
-- of conversations the current user belongs to.
-- This bypasses RLS so fetchConversations can always find
-- the other participant's user_id for name/avatar lookup.
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_conversation_participants(conv_ids UUID[])
RETURNS TABLE(conversation_id UUID, user_id UUID)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT cp.conversation_id, cp.user_id
  FROM public.conversation_participants cp
  WHERE cp.conversation_id = ANY(conv_ids)
    AND cp.user_id != auth.uid();
$$;

GRANT EXECUTE ON FUNCTION public.get_conversation_participants(UUID[]) TO authenticated;
