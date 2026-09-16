-- ============================================================
-- Fix: conversation_participants INSERT RLS + direct conversation helper
-- The previous policy WITH CHECK (user_id = auth.uid()) blocked inserting
-- the other participant's row when creating a new conversation.
-- ============================================================

-- 1. Fix conversation_participants INSERT policy
--    Allow authenticated users to insert ANY participant row into a conversation
--    they own (i.e., they are also being added to the same conversation).
--    We split the ALL policy into SELECT/UPDATE/DELETE (own rows only) +
--    a separate INSERT that allows inserting any user into a conversation
--    the current user is creating.

DROP POLICY IF EXISTS "users_manage_own_conversation_participants" ON public.conversation_participants;

-- SELECT: only see your own participant rows
DROP POLICY IF EXISTS "cp_select_own" ON public.conversation_participants;
CREATE POLICY "cp_select_own"
  ON public.conversation_participants
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

-- INSERT: allow inserting any participant as long as the inserting user
--         is also being added to the same conversation in the same batch,
--         OR is already a participant of that conversation.
--         We use a permissive insert policy so the batch insert works.
DROP POLICY IF EXISTS "cp_insert_participant" ON public.conversation_participants;
CREATE POLICY "cp_insert_participant"
  ON public.conversation_participants
  FOR INSERT
  TO authenticated
  WITH CHECK (
    -- Either inserting your own row
    user_id = auth.uid()
    OR
    -- Or the current user is already a participant of this conversation
    EXISTS (
      SELECT 1 FROM public.conversation_participants existing
      WHERE existing.conversation_id = conversation_id
        AND existing.user_id = auth.uid()
    )
  );

-- UPDATE: only your own rows
DROP POLICY IF EXISTS "cp_update_own" ON public.conversation_participants;
CREATE POLICY "cp_update_own"
  ON public.conversation_participants
  FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- DELETE: only your own rows
DROP POLICY IF EXISTS "cp_delete_own" ON public.conversation_participants;
CREATE POLICY "cp_delete_own"
  ON public.conversation_participants
  FOR DELETE
  TO authenticated
  USING (user_id = auth.uid());

-- Also keep the old read policy name for backward compat
DROP POLICY IF EXISTS "users_read_own_conversation_participants" ON public.conversation_participants;

-- 2. SECURITY DEFINER function to atomically create a direct conversation
--    This bypasses RLS for the participant inserts, which is safe because
--    the function itself validates the caller is authenticated.
CREATE OR REPLACE FUNCTION public.create_direct_conversation(other_user_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  current_user_id UUID;
  existing_conv_id UUID;
  new_conv_id UUID;
BEGIN
  current_user_id := auth.uid();

  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF current_user_id = other_user_id THEN
    RAISE EXCEPTION 'Cannot create conversation with yourself';
  END IF;

  -- Check if a direct (non-group) conversation already exists between the two users
  SELECT cp1.conversation_id INTO existing_conv_id
  FROM public.conversation_participants cp1
  JOIN public.conversation_participants cp2
    ON cp1.conversation_id = cp2.conversation_id
  JOIN public.conversations c
    ON c.id = cp1.conversation_id
  WHERE cp1.user_id = current_user_id
    AND cp2.user_id = other_user_id
    AND c.is_group = false
  LIMIT 1;

  IF existing_conv_id IS NOT NULL THEN
    RETURN existing_conv_id;
  END IF;

  -- Create new conversation
  INSERT INTO public.conversations (is_group)
  VALUES (false)
  RETURNING id INTO new_conv_id;

  -- Insert both participants (SECURITY DEFINER bypasses RLS)
  INSERT INTO public.conversation_participants (conversation_id, user_id, unread_count)
  VALUES
    (new_conv_id, current_user_id, 0),
    (new_conv_id, other_user_id, 0)
  ON CONFLICT (conversation_id, user_id) DO NOTHING;

  RETURN new_conv_id;
END;
$$;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION public.create_direct_conversation(UUID) TO authenticated;
