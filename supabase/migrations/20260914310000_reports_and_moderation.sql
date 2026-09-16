-- ============================================================
-- Reports table (UGC moderation - Google Play compliance)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  reported_user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  content_type VARCHAR(50) NOT NULL, -- 'post', 'comment', 'message', 'profile'
  content_id UUID,
  reason TEXT NOT NULL,
  status VARCHAR(20) DEFAULT 'pending', -- 'pending', 'reviewed', 'action_taken'
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;

-- Users can create reports
CREATE POLICY "Usuários podem criar denúncias"
ON public.reports FOR INSERT
WITH CHECK (auth.uid() = reporter_id);

-- Users can view their own reports
CREATE POLICY "Usuários podem ver suas próprias denúncias"
ON public.reports FOR SELECT
USING (auth.uid() = reporter_id);

-- ============================================================
-- Content moderation: blocked words filter function
-- ============================================================
CREATE OR REPLACE FUNCTION public.check_content_moderation()
RETURNS TRIGGER AS $$
DECLARE
  content_text TEXT;
  blocked_patterns TEXT[] := ARRAY[
    -- Hate speech / violence patterns (Portuguese + English)
    'odeio\s+\w+', 'matar\s+\w+', 'morte\s+a\s+', 'se\s+mata',
    'vai\s+se\s+matar', 'se\s+suicide', 'suicida', 'suicídio\s+é\s+bom',
    'n[i1]gg[ae3]r', 'fagg[o0]t', 'viado\s+de\s+merda', 'puta\s+que\s+pariu',
    'filho\s+da\s+puta', 'vai\s+tomar\s+no\s+cu', 'cuzão', 'arrombado',
    'conteúdo\s+sexual\s+explícito', 'pornô', 'nude\s+grátis'
  ];
  pattern TEXT;
BEGIN
  -- Determine which column holds the text content
  IF TG_TABLE_NAME = 'posts' THEN
    content_text := LOWER(COALESCE(NEW.content, ''));
  ELSIF TG_TABLE_NAME = 'post_comments' THEN
    content_text := LOWER(COALESCE(NEW.content, ''));
  ELSIF TG_TABLE_NAME = 'messages' THEN
    content_text := LOWER(COALESCE(NEW.content, ''));
  ELSE
    RETURN NEW;
  END IF;

  -- Check each blocked pattern
  FOREACH pattern IN ARRAY blocked_patterns LOOP
    IF content_text ~ pattern THEN
      RAISE EXCEPTION 'CONTENT_BLOCKED: Este conteúdo viola as diretrizes da comunidade SintonIA e não pode ser publicado.'
        USING ERRCODE = 'P0001';
    END IF;
  END LOOP;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Attach trigger to posts
DROP TRIGGER IF EXISTS trg_moderate_posts ON public.posts;
CREATE TRIGGER trg_moderate_posts
  BEFORE INSERT OR UPDATE ON public.posts
  FOR EACH ROW EXECUTE FUNCTION public.check_content_moderation();

-- Attach trigger to post_comments
DROP TRIGGER IF EXISTS trg_moderate_comments ON public.post_comments;
CREATE TRIGGER trg_moderate_comments
  BEFORE INSERT OR UPDATE ON public.post_comments
  FOR EACH ROW EXECUTE FUNCTION public.check_content_moderation();

-- Attach trigger to messages
DROP TRIGGER IF EXISTS trg_moderate_messages ON public.messages;
CREATE TRIGGER trg_moderate_messages
  BEFORE INSERT OR UPDATE ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.check_content_moderation();
