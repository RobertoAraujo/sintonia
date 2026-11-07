-- ============================================================
-- Fix Demo Accounts: Ensure ana.silva@email.com and other demo
-- users exist in auth.users + auth.identities for login to work
-- ============================================================

DO $$
DECLARE
  u1 UUID;
  u2 UUID;
  u3 UUID;
  u4 UUID;
  u5 UUID;
  u6 UUID;
BEGIN

  -- Generate stable UUIDs for demo users
  u1 := gen_random_uuid();
  u2 := gen_random_uuid();
  u3 := gen_random_uuid();
  u4 := gen_random_uuid();
  u5 := gen_random_uuid();
  u6 := gen_random_uuid();

  -- ============================================================
  -- 1. UPSERT AUTH USERS
  --    ON CONFLICT (email) DO UPDATE ensures existing rows are
  --    refreshed with correct encrypted_password and confirmed state
  -- ============================================================
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_user_meta_data, raw_app_meta_data,
    is_sso_user, is_anonymous,
    confirmation_token, confirmation_sent_at,
    recovery_token, recovery_sent_at,
    email_change_token_new, email_change, email_change_sent_at,
    email_change_token_current, email_change_confirm_status,
    reauthentication_token, reauthentication_sent_at,
    phone, phone_change, phone_change_token, phone_change_sent_at
  ) VALUES
    (u1, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'admin@sintonia.app', crypt('sintonia123', gen_salt('bf', 10)),
     now(), now(), now(),
     jsonb_build_object('full_name', 'Admin SintonIA', 'username', 'admin_sintonia', 'role', 'admin'),
     jsonb_build_object('provider', 'email', 'providers', ARRAY['email']::TEXT[]),
     false, false, '', null, '', null, '', '', null, '', 0, '', null, null, '', '', null),

    (u2, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'ana.silva@email.com', crypt('sintonia123', gen_salt('bf', 10)),
     now(), now(), now(),
     jsonb_build_object('full_name', 'Ana Silva', 'username', 'ana_silva'),
     jsonb_build_object('provider', 'email', 'providers', ARRAY['email']::TEXT[]),
     false, false, '', null, '', null, '', '', null, '', 0, '', null, null, '', '', null),

    (u3, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'carlos.mendes@email.com', crypt('sintonia123', gen_salt('bf', 10)),
     now(), now(), now(),
     jsonb_build_object('full_name', 'Carlos Mendes', 'username', 'carlos_mendes'),
     jsonb_build_object('provider', 'email', 'providers', ARRAY['email']::TEXT[]),
     false, false, '', null, '', null, '', '', null, '', 0, '', null, null, '', '', null),

    (u4, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'julia.costa@email.com', crypt('sintonia123', gen_salt('bf', 10)),
     now(), now(), now(),
     jsonb_build_object('full_name', 'Julia Costa', 'username', 'julia_costa'),
     jsonb_build_object('provider', 'email', 'providers', ARRAY['email']::TEXT[]),
     false, false, '', null, '', null, '', '', null, '', 0, '', null, null, '', '', null),

    (u5, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'pedro.lima@email.com', crypt('sintonia123', gen_salt('bf', 10)),
     now(), now(), now(),
     jsonb_build_object('full_name', 'Pedro Lima', 'username', 'pedro_lima'),
     jsonb_build_object('provider', 'email', 'providers', ARRAY['email']::TEXT[]),
     false, false, '', null, '', null, '', '', null, '', 0, '', null, null, '', '', null),

    (u6, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'mariana.rocha@email.com', crypt('sintonia123', gen_salt('bf', 10)),
     now(), now(), now(),
     jsonb_build_object('full_name', 'Mariana Rocha', 'username', 'mariana_rocha'),
     jsonb_build_object('provider', 'email', 'providers', ARRAY['email']::TEXT[]),
     false, false, '', null, '', null, '', '', null, '', 0, '', null, null, '', '', null)
  ON CONFLICT (email) DO UPDATE SET
    encrypted_password = crypt('sintonia123', gen_salt('bf', 10)),
    email_confirmed_at = COALESCE(auth.users.email_confirmed_at, now()),
    updated_at = now(),
    is_anonymous = false;

  -- Re-fetch actual UUIDs (in case users already existed with different UUIDs)
  SELECT id INTO u1 FROM auth.users WHERE email = 'admin@sintonia.app';
  SELECT id INTO u2 FROM auth.users WHERE email = 'ana.silva@email.com';
  SELECT id INTO u3 FROM auth.users WHERE email = 'carlos.mendes@email.com';
  SELECT id INTO u4 FROM auth.users WHERE email = 'julia.costa@email.com';
  SELECT id INTO u5 FROM auth.users WHERE email = 'pedro.lima@email.com';
  SELECT id INTO u6 FROM auth.users WHERE email = 'mariana.rocha@email.com';

  -- ============================================================
  -- 2. UPSERT AUTH IDENTITIES
  --    Required for Supabase email/password authentication.
  --    Without this entry, signInWithPassword returns "Invalid login credentials"
  -- ============================================================
  INSERT INTO auth.identities (
    id, user_id, provider_id, provider,
    identity_data, last_sign_in_at, created_at, updated_at
  ) VALUES
    (gen_random_uuid(), u1, u1::TEXT, 'email',
     jsonb_build_object('sub', u1::TEXT, 'email', 'admin@sintonia.app', 'email_verified', true),
     now(), now(), now()),

    (gen_random_uuid(), u2, u2::TEXT, 'email',
     jsonb_build_object('sub', u2::TEXT, 'email', 'ana.silva@email.com', 'email_verified', true),
     now(), now(), now()),

    (gen_random_uuid(), u3, u3::TEXT, 'email',
     jsonb_build_object('sub', u3::TEXT, 'email', 'carlos.mendes@email.com', 'email_verified', true),
     now(), now(), now()),

    (gen_random_uuid(), u4, u4::TEXT, 'email',
     jsonb_build_object('sub', u4::TEXT, 'email', 'julia.costa@email.com', 'email_verified', true),
     now(), now(), now()),

    (gen_random_uuid(), u5, u5::TEXT, 'email',
     jsonb_build_object('sub', u5::TEXT, 'email', 'pedro.lima@email.com', 'email_verified', true),
     now(), now(), now()),

    (gen_random_uuid(), u6, u6::TEXT, 'email',
     jsonb_build_object('sub', u6::TEXT, 'email', 'mariana.rocha@email.com', 'email_verified', true),
     now(), now(), now())
  ON CONFLICT (provider, provider_id) DO NOTHING;

  -- ============================================================
  -- 3. UPSERT USER PROFILES
  --    Insert directly in case the trigger did not fire
  -- ============================================================
  INSERT INTO public.user_profiles (
    id, email, full_name, username, avatar_url,
    bio, neurodiv_type, role,
    hyperfocuses, interests,
    communication_preferences, values_and_ideas, communication_styles
  ) VALUES
    (u1, 'admin@sintonia.app', 'Admin SintonIA', 'admin_sintonia',
     'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=200&h=200&fit=crop',
     'Administrador da plataforma SintonIA. Aqui para ajudar a comunidade neurodivergente.',
     'TDAH', 'admin',
     '["tecnologia", "acessibilidade", "comunidade"]'::jsonb,
     '["programacao", "design", "psicologia"]'::jsonb,
     '{"preferencia": "texto", "ritmo": "flexivel"}'::jsonb,
     '["inclusao", "empatia", "inovacao"]'::jsonb,
     '["direto", "visual"]'::jsonb),

    (u2, 'ana.silva@email.com', 'Ana Silva', 'ana_silva',
     'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=200&h=200&fit=crop',
     'Artista e escritora com TEA. Apaixonada por gatos, livros e aquarela. Cada dia e uma nova descoberta.',
     'TEA', 'user',
     '["aquarela", "literatura", "gatos"]'::jsonb,
     '["arte", "leitura", "natureza"]'::jsonb,
     '{"preferencia": "escrita", "ritmo": "pausado"}'::jsonb,
     '["criatividade", "autenticidade", "paz"]'::jsonb,
     '["visual", "metaforico"]'::jsonb),

    (u3, 'carlos.mendes@email.com', 'Carlos Mendes', 'carlos_mendes',
     'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=200&h=200&fit=crop',
     'Desenvolvedor de software com TDAH. Hiperfoco em jogos retro e musica eletronica. Sempre em movimento!',
     'TDAH', 'user',
     '["jogos_retro", "musica_eletronica", "programacao"]'::jsonb,
     '["tecnologia", "musica", "games"]'::jsonb,
     '{"preferencia": "audio", "ritmo": "rapido"}'::jsonb,
     '["liberdade", "criatividade", "diversao"]'::jsonb,
     '["informal", "humoristico"]'::jsonb),

    (u4, 'julia.costa@email.com', 'Julia Costa', 'julia_costa',
     'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=200&h=200&fit=crop',
     'Estudante de psicologia com dislexia. Defendo a neurodiversidade e o bem-estar mental. Amo cachorros!',
     'Dislexia', 'user',
     '["psicologia", "bem_estar", "cachorros"]'::jsonb,
     '["saude_mental", "animais", "educacao"]'::jsonb,
     '{"preferencia": "visual", "ritmo": "moderado"}'::jsonb,
     '["empatia", "cuidado", "inclusao"]'::jsonb,
     '["empatico", "acolhedor"]'::jsonb),

    (u5, 'pedro.lima@email.com', 'Pedro Lima', 'pedro_lima',
     'https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?w=200&h=200&fit=crop',
     'Musico e compositor com Tourette. A musica e minha forma de me expressar sem filtros.',
     'Tourette', 'user',
     '["composicao", "guitarra", "producao_musical"]'::jsonb,
     '["musica", "arte", "filosofia"]'::jsonb,
     '{"preferencia": "audio", "ritmo": "variavel"}'::jsonb,
     '["autenticidade", "expressao", "liberdade"]'::jsonb,
     '["expressivo", "artistico"]'::jsonb),

    (u6, 'mariana.rocha@email.com', 'Mariana Rocha', 'mariana_rocha',
     'https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=200&h=200&fit=crop',
     'Professora com superdotacao. Apaixonada por matematica, xadrez e astronomia. Sempre aprendendo.',
     'Superdotacao', 'user',
     '["matematica", "xadrez", "astronomia"]'::jsonb,
     '["ciencia", "educacao", "tecnologia"]'::jsonb,
     '{"preferencia": "texto", "ritmo": "detalhado"}'::jsonb,
     '["conhecimento", "precisao", "crescimento"]'::jsonb,
     '["analitico", "estruturado"]'::jsonb)
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    full_name = EXCLUDED.full_name,
    username = EXCLUDED.username,
    avatar_url = EXCLUDED.avatar_url,
    bio = EXCLUDED.bio,
    neurodiv_type = EXCLUDED.neurodiv_type,
    role = EXCLUDED.role;

  -- ============================================================
  -- 4. USER SETTINGS (ensure each demo user has settings)
  -- ============================================================
  INSERT INTO public.user_settings (user_id, dark_mode, notify_messages, notify_friendships, notify_feed, is_public_profile, show_hyperfocus, show_pets)
  VALUES
    (u1, true, true, true, true, true, true, true),
    (u2, false, true, true, true, true, true, true),
    (u3, true, true, false, true, true, true, true),
    (u4, false, true, true, true, true, true, true),
    (u5, true, false, true, false, true, true, true),
    (u6, false, true, true, true, false, true, false)
  ON CONFLICT (user_id) DO NOTHING;

  RAISE NOTICE '=== Demo accounts ready ===';
  RAISE NOTICE 'ana.silva@email.com / sintonia123';
  RAISE NOTICE 'carlos.mendes@email.com / sintonia123';
  RAISE NOTICE 'julia.costa@email.com / sintonia123';
  RAISE NOTICE 'pedro.lima@email.com / sintonia123';
  RAISE NOTICE 'mariana.rocha@email.com / sintonia123';
  RAISE NOTICE 'admin@sintonia.app / sintonia123';

EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'Fix demo accounts error: % %', SQLERRM, SQLSTATE;
END $$;
