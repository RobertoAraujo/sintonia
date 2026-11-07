-- Add post_type column to posts table
-- Values: 'post' (default, regular feed post), 'diary' (shared from diary)
ALTER TABLE public.posts
ADD COLUMN IF NOT EXISTS post_type TEXT NOT NULL DEFAULT 'post';

-- Index for filtering by post_type
CREATE INDEX IF NOT EXISTS idx_posts_post_type ON public.posts(post_type);
