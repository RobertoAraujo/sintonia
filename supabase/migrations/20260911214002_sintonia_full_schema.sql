-- ============================================================
-- SintonIA Full Database Schema
-- Social network for neurodivergent people
-- ============================================================

-- ============================================================
-- 1. ENUMS / TYPES
-- ============================================================

DROP TYPE IF EXISTS public.neurodiv_type CASCADE;
CREATE TYPE public.neurodiv_type AS ENUM (
  'TEA', 'TDAH', 'Dislexia', 'Tourette', 'Dislalia', 'Discalculia',
  'Superdotacao', 'TOC', 'Outro'
);

DROP TYPE IF EXISTS public.pet_role CASCADE;
CREATE TYPE public.pet_role AS ENUM (
  'pet', 'suporte_emocional', 'cao_assistencia', 'animal_terapia'
);

DROP TYPE IF EXISTS public.friendship_status CASCADE;
CREATE TYPE public.friendship_status AS ENUM (
  'pending', 'accepted', 'blocked'
);

DROP TYPE IF EXISTS public.message_type CASCADE;
CREATE TYPE public.message_type AS ENUM (
  'text', 'image', 'audio', 'sticker'
);

DROP TYPE IF EXISTS public.report_status CASCADE;
CREATE TYPE public.report_status AS ENUM (
  'open', 'reviewing', 'resolved', 'dismissed'
);

DROP TYPE IF EXISTS public.report_reason CASCADE;
CREATE TYPE public.report_reason AS ENUM (
  'harassment', 'hate_speech', 'spam', 'misinformation', 'inappropriate_content', 'other'
);

DROP TYPE IF EXISTS public.user_role CASCADE;
CREATE TYPE public.user_role AS ENUM ('user', 'moderator', 'admin');

-- ============================================================
-- 2. CORE TABLES
-- ============================================================

-- User profiles (linked to auth.users via trigger)
CREATE TABLE IF NOT EXISTS public.user_profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT NOT NULL UNIQUE,
  full_name TEXT NOT NULL DEFAULT '',
  username TEXT UNIQUE,
  bio TEXT DEFAULT '',
  avatar_url TEXT DEFAULT '',
  neurodiv_type public.neurodiv_type,
  role public.user_role DEFAULT 'user'::public.user_role,
  is_active BOOLEAN DEFAULT true,
  hyperfocuses JSONB DEFAULT '[]'::jsonb,
  interests JSONB DEFAULT '[]'::jsonb,
  communication_preferences JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Pets
CREATE TABLE IF NOT EXISTS public.pets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  species TEXT NOT NULL DEFAULT '',
  breed TEXT DEFAULT '',
  age TEXT DEFAULT '',
  role public.pet_role DEFAULT 'pet'::public.pet_role,
  photo_url TEXT DEFAULT '',
  photo_semantic TEXT DEFAULT '',
  bio TEXT DEFAULT '',
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Posts
CREATE TABLE IF NOT EXISTS public.posts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  author_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  content TEXT NOT NULL DEFAULT '',
  image_url TEXT DEFAULT '',
  image_semantic TEXT DEFAULT '',
  hyperfocus_tags JSONB DEFAULT '[]'::jsonb,
  likes_count INTEGER DEFAULT 0,
  comments_count INTEGER DEFAULT 0,
  is_published BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Post likes
CREATE TABLE IF NOT EXISTS public.post_likes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Post comments
CREATE TABLE IF NOT EXISTS public.post_comments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  author_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  is_visible BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Saved posts
CREATE TABLE IF NOT EXISTS public.saved_posts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  post_id UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Friendships
CREATE TABLE IF NOT EXISTS public.friendships (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  requester_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  addressee_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  status public.friendship_status DEFAULT 'pending'::public.friendship_status,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Groups
CREATE TABLE IF NOT EXISTS public.groups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  creator_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT DEFAULT '',
  cover_url TEXT DEFAULT '',
  cover_semantic TEXT DEFAULT '',
  neurodiv_focus JSONB DEFAULT '[]'::jsonb,
  hyperfocus_tags JSONB DEFAULT '[]'::jsonb,
  members_count INTEGER DEFAULT 1,
  is_public BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Group members
CREATE TABLE IF NOT EXISTS public.group_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id UUID NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  is_admin BOOLEAN DEFAULT false,
  joined_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Conversations (DMs and group chats)
CREATE TABLE IF NOT EXISTS public.conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  is_group BOOLEAN DEFAULT false,
  group_name TEXT DEFAULT '',
  group_image_url TEXT DEFAULT '',
  last_message TEXT DEFAULT '',
  last_message_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Conversation participants
CREATE TABLE IF NOT EXISTS public.conversation_participants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  unread_count INTEGER DEFAULT 0,
  joined_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Messages
CREATE TABLE IF NOT EXISTS public.messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  content TEXT NOT NULL DEFAULT '',
  message_type public.message_type DEFAULT 'text'::public.message_type,
  media_url TEXT DEFAULT '',
  is_read BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Pet diary entries
CREATE TABLE IF NOT EXISTS public.pet_diary_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pet_id UUID NOT NULL REFERENCES public.pets(id) ON DELETE CASCADE,
  owner_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  entry_text TEXT NOT NULL,
  image_url TEXT DEFAULT '',
  image_semantic TEXT DEFAULT '',
  likes_count INTEGER DEFAULT 0,
  comments_count INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Pet diary likes
CREATE TABLE IF NOT EXISTS public.pet_diary_likes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  entry_id UUID NOT NULL REFERENCES public.pet_diary_entries(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Reports
CREATE TABLE IF NOT EXISTS public.reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  reported_user_id UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL,
  reported_post_id UUID REFERENCES public.posts(id) ON DELETE SET NULL,
  reported_comment_id UUID REFERENCES public.post_comments(id) ON DELETE SET NULL,
  reason public.report_reason NOT NULL,
  description TEXT DEFAULT '',
  status public.report_status DEFAULT 'open'::public.report_status,
  reviewed_by UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Stories
CREATE TABLE IF NOT EXISTS public.stories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  author_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  media_url TEXT NOT NULL DEFAULT '',
  media_semantic TEXT DEFAULT '',
  expires_at TIMESTAMPTZ DEFAULT (CURRENT_TIMESTAMP + INTERVAL '24 hours'),
  views_count INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- User diary (personal diary)
CREATE TABLE IF NOT EXISTS public.user_diary_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  title TEXT DEFAULT '',
  content TEXT NOT NULL,
  mood TEXT DEFAULT '',
  tags JSONB DEFAULT '[]'::jsonb,
  is_private BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- 3. UNIQUE INDEXES
-- ============================================================

CREATE UNIQUE INDEX IF NOT EXISTS idx_post_likes_unique
  ON public.post_likes (post_id, user_id);

CREATE UNIQUE INDEX IF NOT EXISTS idx_saved_posts_unique
  ON public.saved_posts (user_id, post_id);

CREATE UNIQUE INDEX IF NOT EXISTS idx_friendships_unique
  ON public.friendships (requester_id, addressee_id);

CREATE UNIQUE INDEX IF NOT EXISTS idx_group_members_unique
  ON public.group_members (group_id, user_id);

CREATE UNIQUE INDEX IF NOT EXISTS idx_conversation_participants_unique
  ON public.conversation_participants (conversation_id, user_id);

CREATE UNIQUE INDEX IF NOT EXISTS idx_pet_diary_likes_unique
  ON public.pet_diary_likes (entry_id, user_id);

-- Performance indexes
CREATE INDEX IF NOT EXISTS idx_posts_author_id ON public.posts(author_id);
CREATE INDEX IF NOT EXISTS idx_posts_created_at ON public.posts(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_post_comments_post_id ON public.post_comments(post_id);
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id ON public.messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_messages_created_at ON public.messages(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_pets_owner_id ON public.pets(owner_id);
CREATE INDEX IF NOT EXISTS idx_friendships_requester ON public.friendships(requester_id);
CREATE INDEX IF NOT EXISTS idx_friendships_addressee ON public.friendships(addressee_id);
CREATE INDEX IF NOT EXISTS idx_pet_diary_entries_owner ON public.pet_diary_entries(owner_id);
CREATE INDEX IF NOT EXISTS idx_stories_author_id ON public.stories(author_id);
CREATE INDEX IF NOT EXISTS idx_stories_expires_at ON public.stories(expires_at);
CREATE INDEX IF NOT EXISTS idx_user_diary_user_id ON public.user_diary_entries(user_id);

-- ============================================================
-- 4. FUNCTIONS (MUST BE BEFORE RLS POLICIES)
-- ============================================================

-- Auto-create user_profiles on auth signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO public.user_profiles (id, email, full_name, avatar_url, username, role)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1)),
    COALESCE(NEW.raw_user_meta_data->>'avatar_url', ''),
    COALESCE(NEW.raw_user_meta_data->>'username', split_part(NEW.email, '@', 1)),
    COALESCE(NEW.raw_user_meta_data->>'role', 'user')::public.user_role
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

-- Update updated_at timestamp
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$$;

-- Increment post likes count
CREATE OR REPLACE FUNCTION public.increment_post_likes()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.posts SET likes_count = likes_count + 1 WHERE id = NEW.post_id;
  RETURN NEW;
END;
$$;

-- Decrement post likes count
CREATE OR REPLACE FUNCTION public.decrement_post_likes()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.posts SET likes_count = GREATEST(likes_count - 1, 0) WHERE id = OLD.post_id;
  RETURN OLD;
END;
$$;

-- Increment post comments count
CREATE OR REPLACE FUNCTION public.increment_post_comments()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.posts SET comments_count = comments_count + 1 WHERE id = NEW.post_id;
  RETURN NEW;
END;
$$;

-- Decrement post comments count
CREATE OR REPLACE FUNCTION public.decrement_post_comments()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.posts SET comments_count = GREATEST(comments_count - 1, 0) WHERE id = OLD.post_id;
  RETURN OLD;
END;
$$;

-- Increment pet diary likes count
CREATE OR REPLACE FUNCTION public.increment_diary_likes()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.pet_diary_entries SET likes_count = likes_count + 1 WHERE id = NEW.entry_id;
  RETURN NEW;
END;
$$;

-- Decrement pet diary likes count
CREATE OR REPLACE FUNCTION public.decrement_diary_likes()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.pet_diary_entries SET likes_count = GREATEST(likes_count - 1, 0) WHERE id = OLD.entry_id;
  RETURN OLD;
END;
$$;

-- Update last message in conversation
CREATE OR REPLACE FUNCTION public.update_conversation_last_message()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.conversations
  SET last_message = NEW.content,
      last_message_at = NEW.created_at
  WHERE id = NEW.conversation_id;
  RETURN NEW;
END;
$$;

-- Check if user is admin
CREATE OR REPLACE FUNCTION public.is_admin_from_auth()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
SELECT EXISTS (
  SELECT 1 FROM auth.users au
  WHERE au.id = auth.uid()
  AND (au.raw_user_meta_data->>'role' = 'admin'
       OR au.raw_app_meta_data->>'role' = 'admin')
)
$$;

-- ============================================================
-- 5. ENABLE ROW LEVEL SECURITY
-- ============================================================

ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.post_likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.post_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.saved_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.friendships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pet_diary_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pet_diary_likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_diary_entries ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 6. RLS POLICIES
-- ============================================================

-- user_profiles: public read, own write
DROP POLICY IF EXISTS "public_read_user_profiles" ON public.user_profiles;
CREATE POLICY "public_read_user_profiles" ON public.user_profiles
  FOR SELECT TO public USING (true);

DROP POLICY IF EXISTS "users_manage_own_user_profiles" ON public.user_profiles;
CREATE POLICY "users_manage_own_user_profiles" ON public.user_profiles
  FOR ALL TO authenticated USING (id = auth.uid()) WITH CHECK (id = auth.uid());

-- pets: public read, owner write
DROP POLICY IF EXISTS "public_read_pets" ON public.pets;
CREATE POLICY "public_read_pets" ON public.pets
  FOR SELECT TO public USING (true);

DROP POLICY IF EXISTS "users_manage_own_pets" ON public.pets;
CREATE POLICY "users_manage_own_pets" ON public.pets
  FOR ALL TO authenticated USING (owner_id = auth.uid()) WITH CHECK (owner_id = auth.uid());

-- posts: public read, author write
DROP POLICY IF EXISTS "public_read_posts" ON public.posts;
CREATE POLICY "public_read_posts" ON public.posts
  FOR SELECT TO public USING (is_published = true);

DROP POLICY IF EXISTS "users_manage_own_posts" ON public.posts;
CREATE POLICY "users_manage_own_posts" ON public.posts
  FOR ALL TO authenticated USING (author_id = auth.uid()) WITH CHECK (author_id = auth.uid());

-- post_likes: public read, own write
DROP POLICY IF EXISTS "public_read_post_likes" ON public.post_likes;
CREATE POLICY "public_read_post_likes" ON public.post_likes
  FOR SELECT TO public USING (true);

DROP POLICY IF EXISTS "users_manage_own_post_likes" ON public.post_likes;
CREATE POLICY "users_manage_own_post_likes" ON public.post_likes
  FOR ALL TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- post_comments: public read, own write
DROP POLICY IF EXISTS "public_read_post_comments" ON public.post_comments;
CREATE POLICY "public_read_post_comments" ON public.post_comments
  FOR SELECT TO public USING (is_visible = true);

DROP POLICY IF EXISTS "users_manage_own_post_comments" ON public.post_comments;
CREATE POLICY "users_manage_own_post_comments" ON public.post_comments
  FOR ALL TO authenticated USING (author_id = auth.uid()) WITH CHECK (author_id = auth.uid());

-- saved_posts: own only
DROP POLICY IF EXISTS "users_manage_own_saved_posts" ON public.saved_posts;
CREATE POLICY "users_manage_own_saved_posts" ON public.saved_posts
  FOR ALL TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- friendships: participants only
DROP POLICY IF EXISTS "users_read_own_friendships" ON public.friendships;
CREATE POLICY "users_read_own_friendships" ON public.friendships
  FOR SELECT TO authenticated USING (requester_id = auth.uid() OR addressee_id = auth.uid());

DROP POLICY IF EXISTS "users_create_friendships" ON public.friendships;
CREATE POLICY "users_create_friendships" ON public.friendships
  FOR INSERT TO authenticated WITH CHECK (requester_id = auth.uid());

DROP POLICY IF EXISTS "users_update_own_friendships" ON public.friendships;
CREATE POLICY "users_update_own_friendships" ON public.friendships
  FOR UPDATE TO authenticated USING (requester_id = auth.uid() OR addressee_id = auth.uid())
  WITH CHECK (requester_id = auth.uid() OR addressee_id = auth.uid());

DROP POLICY IF EXISTS "users_delete_own_friendships" ON public.friendships;
CREATE POLICY "users_delete_own_friendships" ON public.friendships
  FOR DELETE TO authenticated USING (requester_id = auth.uid() OR addressee_id = auth.uid());

-- groups: public read, creator write
DROP POLICY IF EXISTS "public_read_groups" ON public.groups;
CREATE POLICY "public_read_groups" ON public.groups
  FOR SELECT TO public USING (is_public = true);

DROP POLICY IF EXISTS "users_manage_own_groups" ON public.groups;
CREATE POLICY "users_manage_own_groups" ON public.groups
  FOR ALL TO authenticated USING (creator_id = auth.uid()) WITH CHECK (creator_id = auth.uid());

-- group_members: members read, own write
DROP POLICY IF EXISTS "users_read_group_members" ON public.group_members;
CREATE POLICY "users_read_group_members" ON public.group_members
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "users_manage_own_group_membership" ON public.group_members;
CREATE POLICY "users_manage_own_group_membership" ON public.group_members
  FOR ALL TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- conversations: participants only
DROP POLICY IF EXISTS "users_read_own_conversations" ON public.conversations;
CREATE POLICY "users_read_own_conversations" ON public.conversations
  FOR SELECT TO authenticated USING (
    EXISTS (
      SELECT 1 FROM public.conversation_participants cp
      WHERE cp.conversation_id = id AND cp.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "users_create_conversations" ON public.conversations;
CREATE POLICY "users_create_conversations" ON public.conversations
  FOR INSERT TO authenticated WITH CHECK (true);

-- conversation_participants: own only
DROP POLICY IF EXISTS "users_read_own_conversation_participants" ON public.conversation_participants;
CREATE POLICY "users_read_own_conversation_participants" ON public.conversation_participants
  FOR SELECT TO authenticated USING (user_id = auth.uid());

DROP POLICY IF EXISTS "users_manage_own_conversation_participants" ON public.conversation_participants;
CREATE POLICY "users_manage_own_conversation_participants" ON public.conversation_participants
  FOR ALL TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- messages: conversation participants only
DROP POLICY IF EXISTS "users_read_conversation_messages" ON public.messages;
CREATE POLICY "users_read_conversation_messages" ON public.messages
  FOR SELECT TO authenticated USING (
    EXISTS (
      SELECT 1 FROM public.conversation_participants cp
      WHERE cp.conversation_id = conversation_id AND cp.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "users_send_messages" ON public.messages;
CREATE POLICY "users_send_messages" ON public.messages
  FOR INSERT TO authenticated WITH CHECK (sender_id = auth.uid());

DROP POLICY IF EXISTS "users_delete_own_messages" ON public.messages;
CREATE POLICY "users_delete_own_messages" ON public.messages
  FOR DELETE TO authenticated USING (sender_id = auth.uid());

-- pet_diary_entries: public read, owner write
DROP POLICY IF EXISTS "public_read_pet_diary_entries" ON public.pet_diary_entries;
CREATE POLICY "public_read_pet_diary_entries" ON public.pet_diary_entries
  FOR SELECT TO public USING (true);

DROP POLICY IF EXISTS "users_manage_own_pet_diary_entries" ON public.pet_diary_entries;
CREATE POLICY "users_manage_own_pet_diary_entries" ON public.pet_diary_entries
  FOR ALL TO authenticated USING (owner_id = auth.uid()) WITH CHECK (owner_id = auth.uid());

-- pet_diary_likes: public read, own write
DROP POLICY IF EXISTS "public_read_pet_diary_likes" ON public.pet_diary_likes;
CREATE POLICY "public_read_pet_diary_likes" ON public.pet_diary_likes
  FOR SELECT TO public USING (true);

DROP POLICY IF EXISTS "users_manage_own_pet_diary_likes" ON public.pet_diary_likes;
CREATE POLICY "users_manage_own_pet_diary_likes" ON public.pet_diary_likes
  FOR ALL TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- reports: own only
DROP POLICY IF EXISTS "users_manage_own_reports" ON public.reports;
CREATE POLICY "users_manage_own_reports" ON public.reports
  FOR ALL TO authenticated USING (reporter_id = auth.uid()) WITH CHECK (reporter_id = auth.uid());

DROP POLICY IF EXISTS "admin_read_all_reports" ON public.reports;
CREATE POLICY "admin_read_all_reports" ON public.reports
  FOR SELECT TO authenticated USING (public.is_admin_from_auth());

-- stories: public read, own write
DROP POLICY IF EXISTS "public_read_stories" ON public.stories;
CREATE POLICY "public_read_stories" ON public.stories
  FOR SELECT TO public USING (expires_at > CURRENT_TIMESTAMP);

DROP POLICY IF EXISTS "users_manage_own_stories" ON public.stories;
CREATE POLICY "users_manage_own_stories" ON public.stories
  FOR ALL TO authenticated USING (author_id = auth.uid()) WITH CHECK (author_id = auth.uid());

-- user_diary_entries: private (own only)
DROP POLICY IF EXISTS "users_manage_own_diary_entries" ON public.user_diary_entries;
CREATE POLICY "users_manage_own_diary_entries" ON public.user_diary_entries
  FOR ALL TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- ============================================================
-- 7. TRIGGERS
-- ============================================================

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

DROP TRIGGER IF EXISTS set_user_profiles_updated_at ON public.user_profiles;
CREATE TRIGGER set_user_profiles_updated_at
  BEFORE UPDATE ON public.user_profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_posts_updated_at ON public.posts;
CREATE TRIGGER set_posts_updated_at
  BEFORE UPDATE ON public.posts
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_post_comments_updated_at ON public.post_comments;
CREATE TRIGGER set_post_comments_updated_at
  BEFORE UPDATE ON public.post_comments
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_pets_updated_at ON public.pets;
CREATE TRIGGER set_pets_updated_at
  BEFORE UPDATE ON public.pets
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS on_post_like_insert ON public.post_likes;
CREATE TRIGGER on_post_like_insert
  AFTER INSERT ON public.post_likes
  FOR EACH ROW EXECUTE FUNCTION public.increment_post_likes();

DROP TRIGGER IF EXISTS on_post_like_delete ON public.post_likes;
CREATE TRIGGER on_post_like_delete
  AFTER DELETE ON public.post_likes
  FOR EACH ROW EXECUTE FUNCTION public.decrement_post_likes();

DROP TRIGGER IF EXISTS on_post_comment_insert ON public.post_comments;
CREATE TRIGGER on_post_comment_insert
  AFTER INSERT ON public.post_comments
  FOR EACH ROW EXECUTE FUNCTION public.increment_post_comments();

DROP TRIGGER IF EXISTS on_post_comment_delete ON public.post_comments;
CREATE TRIGGER on_post_comment_delete
  AFTER DELETE ON public.post_comments
  FOR EACH ROW EXECUTE FUNCTION public.decrement_post_comments();

DROP TRIGGER IF EXISTS on_diary_like_insert ON public.pet_diary_likes;
CREATE TRIGGER on_diary_like_insert
  AFTER INSERT ON public.pet_diary_likes
  FOR EACH ROW EXECUTE FUNCTION public.increment_diary_likes();

DROP TRIGGER IF EXISTS on_diary_like_delete ON public.pet_diary_likes;
CREATE TRIGGER on_diary_like_delete
  AFTER DELETE ON public.pet_diary_likes
  FOR EACH ROW EXECUTE FUNCTION public.decrement_diary_likes();

DROP TRIGGER IF EXISTS on_message_insert ON public.messages;
CREATE TRIGGER on_message_insert
  AFTER INSERT ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.update_conversation_last_message();

-- ============================================================
-- 8. MOCK DATA
-- Demo credentials: amara@sintonia.app / sintonia123
--                   rafael@sintonia.app / sintonia123
-- ============================================================

DO $$
DECLARE
  amara_uuid UUID := gen_random_uuid();
  rafael_uuid UUID := gen_random_uuid();
  yuki_uuid UUID := gen_random_uuid();
  diego_uuid UUID := gen_random_uuid();
  priya_uuid UUID := gen_random_uuid();
  post1_uuid UUID := gen_random_uuid();
  post2_uuid UUID := gen_random_uuid();
  post3_uuid UUID := gen_random_uuid();
  pet1_uuid UUID := gen_random_uuid();
  pet2_uuid UUID := gen_random_uuid();
  group1_uuid UUID := gen_random_uuid();
  conv1_uuid UUID := gen_random_uuid();
BEGIN
  -- Create auth users (trigger creates user_profiles automatically)
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
    created_at, updated_at, raw_user_meta_data, raw_app_meta_data,
    is_sso_user, is_anonymous, confirmation_token, confirmation_sent_at,
    recovery_token, recovery_sent_at, email_change_token_new, email_change,
    email_change_sent_at, email_change_token_current, email_change_confirm_status,
    reauthentication_token, reauthentication_sent_at, phone, phone_change,
    phone_change_token, phone_change_sent_at
  ) VALUES
    (amara_uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'amara@sintonia.app', crypt('sintonia123', gen_salt('bf', 10)), now(), now(), now(),
     jsonb_build_object('full_name', 'Amara Osei', 'username', 'amara.osei', 'avatar_url',
       'https://img.rocket.new/generatedImages/rocket_gen_img_10a397da6-1772094815227.png'),
     jsonb_build_object('provider', 'email', 'providers', ARRAY['email']::TEXT[]),
     false, false, '', null, '', null, '', '', null, '', 0, '', null, null, '', '', null),
    (rafael_uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'rafael@sintonia.app', crypt('sintonia123', gen_salt('bf', 10)), now(), now(), now(),
     jsonb_build_object('full_name', 'Rafael Nakamura', 'username', 'rafael.naka', 'avatar_url',
       'https://img.rocket.new/generatedImages/rocket_gen_img_15323d9ba-1772556075899.png'),
     jsonb_build_object('provider', 'email', 'providers', ARRAY['email']::TEXT[]),
     false, false, '', null, '', null, '', '', null, '', 0, '', null, null, '', '', null),
    (yuki_uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'yuki@sintonia.app', crypt('sintonia123', gen_salt('bf', 10)), now(), now(), now(),
     jsonb_build_object('full_name', 'Yuki Tanaka', 'username', 'yuki.tanaka', 'avatar_url',
       'https://img.rocket.new/generatedImages/rocket_gen_img_1bde5382a-1772054100745.png'),
     jsonb_build_object('provider', 'email', 'providers', ARRAY['email']::TEXT[]),
     false, false, '', null, '', null, '', '', null, '', 0, '', null, null, '', '', null),
    (diego_uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'diego@sintonia.app', crypt('sintonia123', gen_salt('bf', 10)), now(), now(), now(),
     jsonb_build_object('full_name', 'Diego Herrera', 'username', 'diego.herrera', 'avatar_url',
       'https://images.unsplash.com/photo-1601239156071-15ec4c7beff2'),
     jsonb_build_object('provider', 'email', 'providers', ARRAY['email']::TEXT[]),
     false, false, '', null, '', null, '', '', null, '', 0, '', null, null, '', '', null),
    (priya_uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'priya@sintonia.app', crypt('sintonia123', gen_salt('bf', 10)), now(), now(), now(),
     jsonb_build_object('full_name', 'Priya Sharma', 'username', 'priya.sharma', 'avatar_url',
       'https://images.unsplash.com/photo-1730575959795-c55aba81e703'),
     jsonb_build_object('provider', 'email', 'providers', ARRAY['email']::TEXT[]),
     false, false, '', null, '', null, '', '', null, '', 0, '', null, null, '', '', null)
  ON CONFLICT (id) DO NOTHING;

  -- Update user_profiles with extra data (trigger already created them)
  UPDATE public.user_profiles SET
    bio = 'Entusiasta de astronomia e xadrez ♟️🌌 TEA nível 1. Aqui me sinto em casa.',
    neurodiv_type = 'TEA'::public.neurodiv_type,
    hyperfocuses = '[{"name":"Astronomia","color":4904153},{"name":"Xadrez","color":8151236},{"name":"Física Quântica","color":2981999}]'::jsonb,
    interests = '["Leitura","Documentários","Culinária Japonesa","Origami","Meditação","Gatos"]'::jsonb
  WHERE id = amara_uuid;

  UPDATE public.user_profiles SET
    bio = 'Produtor musical 🎵 TDAH e orgulhoso. Minha mente nunca para — e isso é lindo.',
    neurodiv_type = 'TDAH'::public.neurodiv_type,
    hyperfocuses = '[{"name":"Música","color":15245344},{"name":"Produção","color":8151236}]'::jsonb,
    interests = '["Eletrônica","Síntese sonora","Videogames","Anime"]'::jsonb
  WHERE id = rafael_uuid;

  UPDATE public.user_profiles SET
    bio = 'Origami + matemática = paz 📐 Dislexia não me define, me diferencia.',
    neurodiv_type = 'Dislexia'::public.neurodiv_type,
    hyperfocuses = '[{"name":"Origami","color":2600800},{"name":"Matemática","color":4904153}]'::jsonb,
    interests = '["Geometria","Culinária","Gatos","Meditação"]'::jsonb
  WHERE id = yuki_uuid;

  UPDATE public.user_profiles SET
    bio = 'RPG adaptado para neurodivergentes 🎲 Tourette não é barreira, é característica.',
    neurodiv_type = 'Tourette'::public.neurodiv_type,
    hyperfocuses = '[{"name":"Videogames","color":10179002},{"name":"RPG","color":15245344}]'::jsonb,
    interests = '["Fantasia","Ficção Científica","Boardgames","Programação"]'::jsonb
  WHERE id = diego_uuid;

  UPDATE public.user_profiles SET
    bio = 'Astrônoma amadora 🌌 TEA. Encontro paz nas estrelas e nos gatos.',
    neurodiv_type = 'TEA'::public.neurodiv_type,
    hyperfocuses = '[{"name":"Astronomia","color":4904153},{"name":"Astrofísica","color":2981999}]'::jsonb,
    interests = '["Telescópios","Física","Gatos","Chá"]'::jsonb
  WHERE id = priya_uuid;

  -- Pets
  INSERT INTO public.pets (id, owner_id, name, species, breed, age, role, photo_url, photo_semantic)
  VALUES
    (pet1_uuid, amara_uuid, 'Luna', 'Gata', 'Maine Coon', '3 anos', 'suporte_emocional'::public.pet_role,
     'https://images.unsplash.com/photo-1688335497497-5052fcef517e',
     'Luna, gata Maine Coon laranja e branca dormindo em almofada macia'),
    (pet2_uuid, rafael_uuid, 'Bento', 'Cachorro', 'Golden Retriever', '2 anos', 'suporte_emocional'::public.pet_role,
     'https://img.rocket.new/generatedImages/rocket_gen_img_1c8c55f52-1777247292089.png',
     'Bento, cachorro golden retriever com expressão alegre')
  ON CONFLICT (id) DO NOTHING;

  -- Posts
  INSERT INTO public.posts (id, author_id, content, image_url, image_semantic, hyperfocus_tags, likes_count, comments_count)
  VALUES
    (post1_uuid, priya_uuid,
     'Acabei de terminar minha maquete do sistema solar! Levei 3 semanas focada nisso e ficou incrível 🌌✨ Quem mais tem hiperfoco em astronomia?',
     'https://img.rocket.new/generatedImages/rocket_gen_img_100a0af07-1768620815857.png',
     'Maquete detalhada do sistema solar com planetas coloridos iluminados',
     '["Astronomia","Astrofísica"]'::jsonb, 142, 8),
    (post2_uuid, rafael_uuid,
     'Finalizei minha nova beat hoje! 🎵🔥 Passei 6 horas no estúdio sem perceber — hiperfoco total. Alguém quer ouvir?',
     null, '', '["Música","Produção"]'::jsonb, 87, 5),
    (post3_uuid, yuki_uuid,
     'Criei uma série de origamis inspirados em fractais matemáticos 📐✨ Cada dobra é uma equação!',
     'https://images.unsplash.com/photo-1659605429808-c4df9ac26161',
     'Coleção de figuras de origami coloridas em formato de fractais',
     '["Origami","Matemática"]'::jsonb, 203, 12)
  ON CONFLICT (id) DO NOTHING;

  -- Post comments
  INSERT INTO public.post_comments (post_id, author_id, content)
  VALUES
    (post1_uuid, amara_uuid, 'Que incrível! Eu também tenho hiperfoco em astronomia! 🌌'),
    (post1_uuid, rafael_uuid, 'Ficou lindo demais! Parabéns pela dedicação 🙌'),
    (post3_uuid, amara_uuid, 'Origami + matemática = perfeição! Adoro essa combinação 📐❤️')
  ON CONFLICT (id) DO NOTHING;

  -- Friendships
  INSERT INTO public.friendships (requester_id, addressee_id, status)
  VALUES
    (amara_uuid, rafael_uuid, 'accepted'::public.friendship_status),
    (amara_uuid, yuki_uuid, 'accepted'::public.friendship_status),
    (priya_uuid, amara_uuid, 'pending'::public.friendship_status),
    (diego_uuid, amara_uuid, 'pending'::public.friendship_status)
  ON CONFLICT DO NOTHING;

  -- Group
  INSERT INTO public.groups (id, creator_id, name, description, cover_url, neurodiv_focus, hyperfocus_tags, members_count)
  VALUES
    (group1_uuid, amara_uuid, 'TEA Astronomia', 'Grupo para pessoas TEA apaixonadas por astronomia e ciências do espaço 🌌',
     'https://img.rocket.new/generatedImages/rocket_gen_img_1a3009a1d-1787362027244.png',
     '["TEA"]'::jsonb, '["Astronomia","Astrofísica","Física"]'::jsonb, 3)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.group_members (group_id, user_id, is_admin)
  VALUES
    (group1_uuid, amara_uuid, true),
    (group1_uuid, priya_uuid, false),
    (group1_uuid, yuki_uuid, false)
  ON CONFLICT DO NOTHING;

  -- Conversation
  INSERT INTO public.conversations (id, is_group, last_message, last_message_at)
  VALUES
    (conv1_uuid, false, 'Cara, ouvi sua beat nova, ficou INCRÍVEL mesmo 🔥', now() - INTERVAL '2 hours')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.conversation_participants (conversation_id, user_id, unread_count)
  VALUES
    (conv1_uuid, amara_uuid, 0),
    (conv1_uuid, rafael_uuid, 3)
  ON CONFLICT DO NOTHING;

  INSERT INTO public.messages (conversation_id, sender_id, content)
  VALUES
    (conv1_uuid, rafael_uuid, 'Cara, ouvi sua beat nova, ficou INCRÍVEL mesmo 🔥')
  ON CONFLICT (id) DO NOTHING;

  -- Pet diary entries
  INSERT INTO public.pet_diary_entries (pet_id, owner_id, entry_text, image_url, image_semantic, likes_count, comments_count)
  VALUES
    (pet2_uuid, rafael_uuid,
     'Bento aprendeu um novo truque hoje! Ficou tentando por 2 horas — pura persistência, igualzinho ao dono 🐕🎵',
     'https://images.unsplash.com/photo-1616941842539-5d3dae67c9a4',
     'Bento, cachorro golden retriever sentado e dando a patinha', 47, 12),
    (pet1_uuid, amara_uuid,
     'Luna dormiu o dia todo no telescópio 🔭 Acho que ela também tem hiperfoco em astronomia!',
     null, '', 89, 7)
  ON CONFLICT (id) DO NOTHING;

EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'Mock data insertion failed: %', SQLERRM;
END $$;
