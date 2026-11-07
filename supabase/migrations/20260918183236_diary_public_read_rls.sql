-- Ensure is_private column exists on user_diary_entries
ALTER TABLE public.user_diary_entries
  ADD COLUMN IF NOT EXISTS is_private BOOLEAN NOT NULL DEFAULT true;

-- Allow any authenticated user to read public diary entries from other users
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'user_diary_entries'
      AND policyname = 'Public diary entries are readable by authenticated users'
  ) THEN
    CREATE POLICY "Public diary entries are readable by authenticated users"
      ON public.user_diary_entries
      FOR SELECT
      TO authenticated
      USING (is_private = false OR auth.uid() = user_id);
  END IF;
END $$;
