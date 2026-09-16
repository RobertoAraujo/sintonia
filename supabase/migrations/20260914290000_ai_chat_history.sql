-- ============================================================
-- AI Chat History Table
-- Stores SintonIA chat history keyed to auth.users (not user_profiles)
-- This table is referenced by the delete button on SintonIA screen
-- ============================================================

CREATE TABLE IF NOT EXISTS public.ai_chat_history (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role       VARCHAR(10) NOT NULL CHECK (role IN ('user', 'model', 'assistant')),
  content    TEXT        NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── Indexes ──────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_ai_chat_history_user_id
  ON public.ai_chat_history(user_id);

CREATE INDEX IF NOT EXISTS idx_ai_chat_history_created_at
  ON public.ai_chat_history(created_at DESC);

-- ── RLS ──────────────────────────────────────────────────────
ALTER TABLE public.ai_chat_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "usuarios_gerenciam_proprio_historico_ia" ON public.ai_chat_history;
CREATE POLICY "usuarios_gerenciam_proprio_historico_ia"
  ON public.ai_chat_history
  FOR ALL
  TO authenticated
  USING  (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
