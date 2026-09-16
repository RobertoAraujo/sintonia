-- Migration: Ensure friendship RLS allows addressee to delete (decline) requests
-- and add index for faster friendship lookups

-- Ensure the delete policy covers both requester and addressee
DROP POLICY IF EXISTS "users_delete_own_friendships" ON public.friendships;
CREATE POLICY "users_delete_own_friendships" ON public.friendships
  FOR DELETE TO authenticated
  USING (requester_id = auth.uid() OR addressee_id = auth.uid());

-- Composite index for bidirectional friendship lookups
CREATE INDEX IF NOT EXISTS idx_friendships_bidirectional
  ON public.friendships (requester_id, addressee_id, status);
