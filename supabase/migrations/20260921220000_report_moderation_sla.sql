-- ============================================================
-- Report Moderation SLA: 24h auto-delete + in-app notification
-- ============================================================

-- 1. Add 'report' value to notification_type enum (idempotent)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum
    WHERE enumlabel = 'report'
      AND enumtypid = (
        SELECT oid FROM pg_type WHERE typname = 'notification_type'
      )
  ) THEN
    ALTER TYPE public.notification_type ADD VALUE 'report';
  END IF;
END $$;

-- 2. Add 'action_taken' to report_status enum if missing (idempotent)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum
    WHERE enumlabel = 'action_taken'
      AND enumtypid = (
        SELECT oid FROM pg_type WHERE typname = 'report_status'
      )
  ) THEN
    ALTER TYPE public.report_status ADD VALUE 'action_taken';
  END IF;
END $$;

-- 3. Add deadline column to reports table for SLA tracking
ALTER TABLE public.reports
  ADD COLUMN IF NOT EXISTS deadline_at TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '24 hours');

-- 4. Function: send moderation notification to post author on new report
CREATE OR REPLACE FUNCTION public.notify_post_author_on_report()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_author_id UUID;
BEGIN
  -- Only act on post reports
  IF NEW.reported_post_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Get post author
  SELECT author_id INTO v_author_id
  FROM public.posts
  WHERE id = NEW.reported_post_id;

  IF v_author_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Do not notify the reporter themselves (edge case: self-report)
  IF v_author_id = NEW.reporter_id THEN
    RETURN NEW;
  END IF;

  -- Insert in-app notification to post author
  INSERT INTO public.notifications (
    recipient_id,
    actor_id,
    type,
    title,
    body,
    reference_id,
    is_read
  ) VALUES (
    v_author_id,
    NEW.reporter_id,
    'report'::public.notification_type,
    '⚠️ Sua publicação foi denunciada',
    'Uma denúncia foi registrada em sua publicação. Você tem 24 horas para editar ou remover o conteúdo. Caso contrário, ele será removido automaticamente.',
    NEW.reported_post_id,
    false
  );

  RETURN NEW;
END;
$$;

-- 5. Attach trigger to reports table
DROP TRIGGER IF EXISTS trg_notify_author_on_report ON public.reports;
CREATE TRIGGER trg_notify_author_on_report
  AFTER INSERT ON public.reports
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_post_author_on_report();

-- 6. Function: auto-delete posts with unresolved reports past 24h SLA
CREATE OR REPLACE FUNCTION public.enforce_report_sla()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_report RECORD;
BEGIN
  FOR v_report IN
    SELECT r.id AS report_id, r.reported_post_id, p.updated_at AS post_updated_at, r.created_at AS report_created_at
    FROM public.reports r
    JOIN public.posts p ON p.id = r.reported_post_id
    WHERE r.status = 'pending'
      AND r.reported_post_id IS NOT NULL
      AND r.deadline_at IS NOT NULL
      AND NOW() > r.deadline_at
      -- Post has NOT been edited after the report was created (no action taken)
      AND p.updated_at <= r.created_at + INTERVAL '1 minute'
  LOOP
    -- Delete the post
    DELETE FROM public.posts WHERE id = v_report.reported_post_id;

    -- Update report status to action_taken
    UPDATE public.reports
    SET status = 'action_taken',
        updated_at = NOW()
    WHERE id = v_report.report_id;
  END LOOP;
END;
$$;

-- 7. Schedule the SLA enforcement job via pg_cron (runs every hour)
-- pg_cron must be enabled in the Supabase project (it is enabled by default)
DO $$
BEGIN
  -- Remove existing job if present to avoid duplicates
  IF EXISTS (
    SELECT 1 FROM cron.job WHERE jobname = 'enforce_report_sla_hourly'
  ) THEN
    PERFORM cron.unschedule('enforce_report_sla_hourly');
  END IF;

  PERFORM cron.schedule(
    'enforce_report_sla_hourly',
    '0 * * * *',  -- every hour at minute 0
    $cron$SELECT public.enforce_report_sla();$cron$
  );
EXCEPTION
  WHEN OTHERS THEN
    -- pg_cron may not be available in all environments; log and continue
    RAISE NOTICE 'pg_cron scheduling skipped: %. The enforce_report_sla() function can be called manually or via an external scheduler.', SQLERRM;
END $$;

-- 8. Index for efficient SLA queries
CREATE INDEX IF NOT EXISTS idx_reports_pending_deadline
  ON public.reports (status, deadline_at)
  WHERE status = 'pending';
