-- Add friends_only column to user_diary_entries
-- friends_only = true means visible to friends (default)
-- friends_only = false means private (only owner)
-- is_private = false means public (everyone can see)
ALTER TABLE public.user_diary_entries
  ADD COLUMN IF NOT EXISTS friends_only BOOLEAN NOT NULL DEFAULT true;

-- Update existing entries: if is_private = false, keep public; if is_private = true, set friends_only = true (friends can see)
UPDATE public.user_diary_entries
  SET friends_only = true
  WHERE is_private = true;

-- Drop old public read policy and replace with friends-aware policy
DO $$
BEGIN
  -- Drop existing policies to recreate them
  DROP POLICY IF EXISTS "Public diary entries are readable by authenticated users" ON public.user_diary_entries;
  DROP POLICY IF EXISTS "Friends can read friends_only diary entries" ON public.user_diary_entries;
  DROP POLICY IF EXISTS "Diary entries visibility policy" ON public.user_diary_entries;
END $$;

-- New unified read policy:
-- Owner can always read their own entries
-- friends_only=true: friends can read (users who have accepted friendship)
-- is_private=false: everyone authenticated can read (public)
CREATE POLICY "Diary entries visibility policy"
  ON public.user_diary_entries
  FOR SELECT
  TO authenticated
  USING (
    auth.uid() = user_id
    OR (
      is_private = false AND friends_only = false
    )
    OR (
      friends_only = true AND is_private = true AND EXISTS (
        SELECT 1 FROM public.friendships
        WHERE status = 'accepted'
          AND (
            (requester_id = auth.uid() AND addressee_id = user_diary_entries.user_id)
            OR (addressee_id = auth.uid() AND requester_id = user_diary_entries.user_id)
          )
      )
    )
  );
