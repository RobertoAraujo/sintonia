-- ─── Notifications Module ────────────────────────────────────────────────────
-- Stores in-app notifications for likes, comments, friend requests, and messages

-- 1. Notification type enum
DROP TYPE IF EXISTS public.notification_type CASCADE;
CREATE TYPE public.notification_type AS ENUM (
  'like',
  'comment',
  'friend_request',
  'friend_accepted',
  'message'
);

-- 2. Notifications table
CREATE TABLE IF NOT EXISTS public.notifications (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient_id  UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  actor_id      UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  type          public.notification_type NOT NULL,
  title         TEXT NOT NULL DEFAULT '',
  body          TEXT NOT NULL DEFAULT '',
  reference_id  UUID,          -- post_id / comment_id / friendship_id / message_id
  is_read       BOOLEAN NOT NULL DEFAULT false,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 3. Indexes
CREATE INDEX IF NOT EXISTS idx_notifications_recipient_id
  ON public.notifications(recipient_id);

CREATE INDEX IF NOT EXISTS idx_notifications_recipient_unread
  ON public.notifications(recipient_id, is_read)
  WHERE is_read = false;

CREATE INDEX IF NOT EXISTS idx_notifications_created_at
  ON public.notifications(created_at DESC);

-- 4. Enable RLS
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- 5. RLS Policies
DROP POLICY IF EXISTS "users_view_own_notifications" ON public.notifications;
CREATE POLICY "users_view_own_notifications"
  ON public.notifications
  FOR SELECT
  TO authenticated
  USING (recipient_id = auth.uid());

DROP POLICY IF EXISTS "users_update_own_notifications" ON public.notifications;
CREATE POLICY "users_update_own_notifications"
  ON public.notifications
  FOR UPDATE
  TO authenticated
  USING (recipient_id = auth.uid())
  WITH CHECK (recipient_id = auth.uid());

DROP POLICY IF EXISTS "authenticated_insert_notifications" ON public.notifications;
CREATE POLICY "authenticated_insert_notifications"
  ON public.notifications
  FOR INSERT
  TO authenticated
  WITH CHECK (actor_id = auth.uid());

DROP POLICY IF EXISTS "users_delete_own_notifications" ON public.notifications;
CREATE POLICY "users_delete_own_notifications"
  ON public.notifications
  FOR DELETE
  TO authenticated
  USING (recipient_id = auth.uid());

-- 6. Function: create notification helper (SECURITY DEFINER so triggers can call it)
CREATE OR REPLACE FUNCTION public.create_notification(
  p_recipient_id UUID,
  p_actor_id     UUID,
  p_type         public.notification_type,
  p_title        TEXT,
  p_body         TEXT,
  p_reference_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_id UUID;
BEGIN
  -- Do not notify yourself
  IF p_recipient_id = p_actor_id THEN
    RETURN NULL;
  END IF;

  INSERT INTO public.notifications (recipient_id, actor_id, type, title, body, reference_id)
  VALUES (p_recipient_id, p_actor_id, p_type, p_title, p_body, p_reference_id)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- 7. Trigger: notify post author on new like
CREATE OR REPLACE FUNCTION public.notify_on_post_like()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $func$
DECLARE
  v_post_author UUID;
  v_actor_name  TEXT;
BEGIN
  SELECT author_id INTO v_post_author FROM public.posts WHERE id = NEW.post_id LIMIT 1;
  SELECT COALESCE(full_name, username, 'Alguém') INTO v_actor_name
    FROM public.user_profiles WHERE id = NEW.user_id LIMIT 1;

  IF v_post_author IS NOT NULL THEN
    PERFORM public.create_notification(
      v_post_author,
      NEW.user_id,
      'like'::public.notification_type,
      'Nova curtida',
      v_actor_name || ' curtiu sua publicação.',
      NEW.post_id
    );
  END IF;
  RETURN NEW;
END;
$func$;

DROP TRIGGER IF EXISTS trg_notify_post_like ON public.post_likes;
CREATE TRIGGER trg_notify_post_like
  AFTER INSERT ON public.post_likes
  FOR EACH ROW EXECUTE FUNCTION public.notify_on_post_like();

-- 8. Trigger: notify post author on new comment
CREATE OR REPLACE FUNCTION public.notify_on_post_comment()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $func$
DECLARE
  v_post_author UUID;
  v_actor_name  TEXT;
BEGIN
  SELECT author_id INTO v_post_author FROM public.posts WHERE id = NEW.post_id LIMIT 1;
  SELECT COALESCE(full_name, username, 'Alguém') INTO v_actor_name
    FROM public.user_profiles WHERE id = NEW.author_id LIMIT 1;

  IF v_post_author IS NOT NULL THEN
    PERFORM public.create_notification(
      v_post_author,
      NEW.author_id,
      'comment'::public.notification_type,
      'Novo comentário',
      v_actor_name || ' comentou na sua publicação.',
      NEW.post_id
    );
  END IF;
  RETURN NEW;
END;
$func$;

DROP TRIGGER IF EXISTS trg_notify_post_comment ON public.post_comments;
CREATE TRIGGER trg_notify_post_comment
  AFTER INSERT ON public.post_comments
  FOR EACH ROW EXECUTE FUNCTION public.notify_on_post_comment();

-- 9. Trigger: notify on friend request
CREATE OR REPLACE FUNCTION public.notify_on_friendship_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $func$
DECLARE
  v_actor_name TEXT;
BEGIN
  SELECT COALESCE(full_name, username, 'Alguém') INTO v_actor_name
    FROM public.user_profiles WHERE id = NEW.requester_id LIMIT 1;

  -- New pending request → notify addressee
  IF TG_OP = 'INSERT' AND NEW.status = 'pending' THEN
    PERFORM public.create_notification(
      NEW.addressee_id,
      NEW.requester_id,
      'friend_request'::public.notification_type,
      'Pedido de amizade',
      v_actor_name || ' enviou um pedido de amizade.',
      NEW.id
    );
  END IF;

  -- Accepted → notify original requester
  IF TG_OP = 'UPDATE' AND NEW.status = 'accepted' AND OLD.status = 'pending' THEN
    SELECT COALESCE(full_name, username, 'Alguém') INTO v_actor_name
      FROM public.user_profiles WHERE id = NEW.addressee_id LIMIT 1;
    PERFORM public.create_notification(
      NEW.requester_id,
      NEW.addressee_id,
      'friend_accepted'::public.notification_type,
      'Amizade aceita',
      v_actor_name || ' aceitou seu pedido de amizade.',
      NEW.id
    );
  END IF;

  RETURN NEW;
END;
$func$;

DROP TRIGGER IF EXISTS trg_notify_friendship ON public.friendships;
CREATE TRIGGER trg_notify_friendship
  AFTER INSERT OR UPDATE ON public.friendships
  FOR EACH ROW EXECUTE FUNCTION public.notify_on_friendship_change();

-- 10. Trigger: notify on new message
CREATE OR REPLACE FUNCTION public.notify_on_new_message()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $func$
DECLARE
  v_participant RECORD;
  v_actor_name  TEXT;
BEGIN
  SELECT COALESCE(full_name, username, 'Alguém') INTO v_actor_name
    FROM public.user_profiles WHERE id = NEW.sender_id LIMIT 1;

  FOR v_participant IN
    SELECT user_id FROM public.conversation_participants
    WHERE conversation_id = NEW.conversation_id
      AND user_id <> NEW.sender_id
  LOOP
    PERFORM public.create_notification(
      v_participant.user_id,
      NEW.sender_id,
      'message'::public.notification_type,
      'Nova mensagem',
      v_actor_name || ' enviou uma mensagem.',
      NEW.conversation_id
    );
  END LOOP;

  RETURN NEW;
END;
$func$;

DROP TRIGGER IF EXISTS trg_notify_new_message ON public.messages;
CREATE TRIGGER trg_notify_new_message
  AFTER INSERT ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.notify_on_new_message();
