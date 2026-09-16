-- ============================================================
-- Fix Critical APK Issues
-- 1. Friendship request notification trigger
-- 2. Post comments RLS hardening
-- 3. Messages RLS hardening
-- 4. Notifications INSERT policy for server-side triggers
-- ============================================================

-- ─── 1. Ensure friendships RLS policies are correct ────────────────────────

-- Ensure INSERT policy allows requester to create friendship
DROP POLICY IF EXISTS "users_create_friendships" ON public.friendships;
CREATE POLICY "users_create_friendships" ON public.friendships
  FOR INSERT TO authenticated
  WITH CHECK (requester_id = auth.uid());

-- Ensure SELECT policy allows both participants to read
DROP POLICY IF EXISTS "users_read_own_friendships" ON public.friendships;
CREATE POLICY "users_read_own_friendships" ON public.friendships
  FOR SELECT TO authenticated
  USING (requester_id = auth.uid() OR addressee_id = auth.uid());

-- Ensure UPDATE policy allows addressee to accept/decline
DROP POLICY IF EXISTS "users_update_own_friendships" ON public.friendships;
CREATE POLICY "users_update_own_friendships" ON public.friendships
  FOR UPDATE TO authenticated
  USING (requester_id = auth.uid() OR addressee_id = auth.uid())
  WITH CHECK (requester_id = auth.uid() OR addressee_id = auth.uid());

-- Ensure DELETE policy allows both to remove
DROP POLICY IF EXISTS "users_delete_own_friendships" ON public.friendships;
CREATE POLICY "users_delete_own_friendships" ON public.friendships
  FOR DELETE TO authenticated
  USING (requester_id = auth.uid() OR addressee_id = auth.uid());

-- ─── 2. Notification trigger for friend requests ───────────────────────────

-- Allow service role to insert notifications (needed for triggers)
DROP POLICY IF EXISTS "service_insert_notifications" ON public.notifications;
CREATE POLICY "service_insert_notifications" ON public.notifications
  FOR INSERT TO authenticated
  WITH CHECK (true);

-- Function: create a notification when a friendship request is inserted
CREATE OR REPLACE FUNCTION public.notify_friend_request()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  requester_name TEXT;
BEGIN
  -- Only notify on new pending requests
  IF NEW.status = 'pending' THEN
    -- Get requester's display name
    SELECT COALESCE(full_name, username, 'Alguém')
    INTO requester_name
    FROM public.user_profiles
    WHERE id = NEW.requester_id;

    -- Insert notification for the addressee
    INSERT INTO public.notifications (
      recipient_id,
      actor_id,
      type,
      title,
      body,
      reference_id,
      is_read
    ) VALUES (
      NEW.addressee_id,
      NEW.requester_id,
      'friend_request',
      'Nova solicitação de amizade',
      requester_name || ' quer se conectar com você!',
      NEW.id,
      false
    )
    ON CONFLICT DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_friend_request ON public.friendships;
CREATE TRIGGER trg_notify_friend_request
  AFTER INSERT ON public.friendships
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_friend_request();

-- Function: create a notification when a friendship is accepted
CREATE OR REPLACE FUNCTION public.notify_friend_accepted()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  accepter_name TEXT;
BEGIN
  -- Only notify when status changes from pending to accepted
  IF OLD.status = 'pending' AND NEW.status = 'accepted' THEN
    SELECT COALESCE(full_name, username, 'Alguém')
    INTO accepter_name
    FROM public.user_profiles
    WHERE id = NEW.addressee_id;

    INSERT INTO public.notifications (
      recipient_id,
      actor_id,
      type,
      title,
      body,
      reference_id,
      is_read
    ) VALUES (
      NEW.requester_id,
      NEW.addressee_id,
      'friend_accepted',
      'Solicitação aceita!',
      accepter_name || ' aceitou sua solicitação de amizade 🎉',
      NEW.id,
      false
    )
    ON CONFLICT DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_friend_accepted ON public.friendships;
CREATE TRIGGER trg_notify_friend_accepted
  AFTER UPDATE ON public.friendships
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_friend_accepted();

-- ─── 3. Post comments RLS hardening ────────────────────────────────────────

ALTER TABLE public.post_comments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "public_read_post_comments" ON public.post_comments;
CREATE POLICY "public_read_post_comments"
  ON public.post_comments FOR SELECT TO public USING (is_visible = true);

DROP POLICY IF EXISTS "users_insert_post_comments" ON public.post_comments;
CREATE POLICY "users_insert_post_comments"
  ON public.post_comments FOR INSERT TO authenticated
  WITH CHECK (author_id = auth.uid());

DROP POLICY IF EXISTS "users_manage_own_post_comments" ON public.post_comments;
CREATE POLICY "users_manage_own_post_comments"
  ON public.post_comments FOR ALL TO authenticated
  USING (author_id = auth.uid())
  WITH CHECK (author_id = auth.uid());

-- ─── 4. Messages RLS hardening ─────────────────────────────────────────────

ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "participants_read_messages" ON public.messages;
CREATE POLICY "participants_read_messages"
  ON public.messages FOR SELECT TO authenticated
  USING (
    sender_id = auth.uid() OR receiver_id = auth.uid()
  );

DROP POLICY IF EXISTS "sender_insert_messages" ON public.messages;
CREATE POLICY "sender_insert_messages"
  ON public.messages FOR INSERT TO authenticated
  WITH CHECK (sender_id = auth.uid());

DROP POLICY IF EXISTS "participants_update_messages" ON public.messages;
CREATE POLICY "participants_update_messages"
  ON public.messages FOR UPDATE TO authenticated
  USING (sender_id = auth.uid() OR receiver_id = auth.uid());

-- ─── 5. Enable Realtime for friendships and notifications ──────────────────

-- These tables need to be in the realtime publication for live updates
DO $$
BEGIN
  -- Add friendships to realtime if not already present
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
    AND tablename = 'friendships'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.friendships;
  END IF;

  -- Add notifications to realtime if not already present
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
    AND tablename = 'notifications'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
  END IF;
EXCEPTION WHEN OTHERS THEN
  -- Ignore errors if publication doesn't exist or table already added
  NULL;
END;
$$;
