-- Add 'post_edit' value to notification_type enum
-- This is safe to run multiple times (idempotent via DO block)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum
    WHERE enumlabel = 'post_edit'
      AND enumtypid = (
        SELECT oid FROM pg_type WHERE typname = 'notification_type'
      )
  ) THEN
    ALTER TYPE public.notification_type ADD VALUE 'post_edit';
  END IF;
END;
$$;
