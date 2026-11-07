-- Fix: Allow any authenticated user to read ACCEPTED friendships
-- so that viewing another user's friends list shows all their friends,
-- not just the ones involving the current user.
-- INSERT/UPDATE/DELETE policies remain restricted to participants only.

DROP POLICY IF EXISTS "users_read_own_friendships" ON public.friendships;

-- New policy: any authenticated user can read accepted friendships (public social graph).
-- Pending/blocked rows are still hidden unless the current user is a participant.
CREATE POLICY "users_read_friendships" ON public.friendships
  FOR SELECT TO authenticated
  USING (
    status = 'accepted'::public.friendship_status
    OR requester_id = auth.uid()
    OR addressee_id = auth.uid()
  );
