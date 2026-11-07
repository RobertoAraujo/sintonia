-- ============================================================
-- SintonIA Seed Data
-- Realistic demo data for all main tables
-- ============================================================

DO $$
DECLARE
  -- User UUIDs
  u1 UUID := gen_random_uuid();
  u2 UUID := gen_random_uuid();
  u3 UUID := gen_random_uuid();
  u4 UUID := gen_random_uuid();
  u5 UUID := gen_random_uuid();
  u6 UUID := gen_random_uuid();

  -- Pet UUIDs
  p1 UUID := gen_random_uuid();
  p2 UUID := gen_random_uuid();
  p3 UUID := gen_random_uuid();
  p4 UUID := gen_random_uuid();

  -- Post UUIDs
  post1 UUID := gen_random_uuid();
  post2 UUID := gen_random_uuid();
  post3 UUID := gen_random_uuid();
  post4 UUID := gen_random_uuid();
  post5 UUID := gen_random_uuid();
  post6 UUID := gen_random_uuid();

  -- Group UUIDs
  g1 UUID := gen_random_uuid();
  g2 UUID := gen_random_uuid();

  -- Conversation UUIDs
  conv1 UUID := gen_random_uuid();
  conv2 UUID := gen_random_uuid();

  -- Story UUIDs
  s1 UUID := gen_random_uuid();
  s2 UUID := gen_random_uuid();

  -- Notification UUIDs
  n1 UUID := gen_random_uuid();
  n2 UUID := gen_random_uuid();
  n3 UUID := gen_random_uuid();

BEGIN

  -- ============================================================
  -- 1. AUTH USERS (trigger creates user_profiles automatically)
  -- ============================================================
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
    created_at, updated_at, raw_user_meta_data, raw_app_meta_data,
    is_sso_user, is_anonymous, confirmation_token, confirmation_sent_at,
    recovery_token, recovery_sent_at, email_change_token_new, email_change,
    email_change_sent_at, email_change_token_current, email_change_confirm_status,
    reauthentication_token, reauthentication_sent_at, phone, phone_change,
    phone_change_token, phone_change_sent_at
  ) VALUES
    (u1, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'admin@sintonia.app', crypt('sintonia123', gen_salt('bf', 10)), now(), now(), now(),
     jsonb_build_object('full_name', 'Admin SintonIA', 'username', 'admin_sintonia', 'role', 'admin'),
     jsonb_build_object('provider', 'email', 'providers', ARRAY['email']::TEXT[]),
     false, false, '', null, '', null, '', '', null, '', 0, '', null, null, '', '', null),

    (u2, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'ana.silva@email.com', crypt('sintonia123', gen_salt('bf', 10)), now(), now(), now(),
     jsonb_build_object('full_name', 'Ana Silva', 'username', 'ana_silva'),
     jsonb_build_object('provider', 'email', 'providers', ARRAY['email']::TEXT[]),
     false, false, '', null, '', null, '', '', null, '', 0, '', null, null, '', '', null),

    (u3, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'carlos.mendes@email.com', crypt('sintonia123', gen_salt('bf', 10)), now(), now(), now(),
     jsonb_build_object('full_name', 'Carlos Mendes', 'username', 'carlos_mendes'),
     jsonb_build_object('provider', 'email', 'providers', ARRAY['email']::TEXT[]),
     false, false, '', null, '', null, '', '', null, '', 0, '', null, null, '', '', null),

    (u4, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'julia.costa@email.com', crypt('sintonia123', gen_salt('bf', 10)), now(), now(), now(),
     jsonb_build_object('full_name', 'Julia Costa', 'username', 'julia_costa'),
     jsonb_build_object('provider', 'email', 'providers', ARRAY['email']::TEXT[]),
     false, false, '', null, '', null, '', '', null, '', 0, '', null, null, '', '', null),

    (u5, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'pedro.lima@email.com', crypt('sintonia123', gen_salt('bf', 10)), now(), now(), now(),
     jsonb_build_object('full_name', 'Pedro Lima', 'username', 'pedro_lima'),
     jsonb_build_object('provider', 'email', 'providers', ARRAY['email']::TEXT[]),
     false, false, '', null, '', null, '', '', null, '', 0, '', null, null, '', '', null),

    (u6, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'mariana.rocha@email.com', crypt('sintonia123', gen_salt('bf', 10)), now(), now(), now(),
     jsonb_build_object('full_name', 'Mariana Rocha', 'username', 'mariana_rocha'),
     jsonb_build_object('provider', 'email', 'providers', ARRAY['email']::TEXT[]),
     false, false, '', null, '', null, '', '', null, '', 0, '', null, null, '', '', null)
  ON CONFLICT (id) DO NOTHING;

  -- ============================================================
  -- 2. UPDATE USER PROFILES (trigger already created them)
  -- ============================================================
  UPDATE public.user_profiles SET
    bio = 'Administrador da plataforma SintonIA. Aqui para ajudar a comunidade neurodivergente.',
    avatar_url = 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=200&h=200&fit=crop',
    neurodiv_type = 'TDAH',
    role = 'admin',
    hyperfocuses = '["tecnologia", "acessibilidade", "comunidade"]'::jsonb,
    interests = '["programacao", "design", "psicologia"]'::jsonb,
    communication_preferences = '{"preferencia": "texto", "ritmo": "flexivel"}'::jsonb,
    values_and_ideas = '["inclusao", "empatia", "inovacao"]'::jsonb,
    communication_styles = '["direto", "visual"]'::jsonb
  WHERE id = u1;

  UPDATE public.user_profiles SET
    bio = 'Artista e escritora com TEA. Apaixonada por gatos, livros e aquarela. Cada dia e uma nova descoberta.',
    avatar_url = 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=200&h=200&fit=crop',
    neurodiv_type = 'TEA',
    hyperfocuses = '["aquarela", "literatura", "gatos"]'::jsonb,
    interests = '["arte", "leitura", "natureza"]'::jsonb,
    communication_preferences = '{"preferencia": "escrita", "ritmo": "pausado"}'::jsonb,
    values_and_ideas = '["criatividade", "autenticidade", "paz"]'::jsonb,
    communication_styles = '["visual", "metaforico"]'::jsonb,
    sensory_triggers = ARRAY['barulho_alto', 'multidoes'],
    political_views = ARRAY['progressista'],
    religions = ARRAY['espiritualidade']
  WHERE id = u2;

  UPDATE public.user_profiles SET
    bio = 'Desenvolvedor de software com TDAH. Hiperfoco em jogos retro e musica eletronica. Sempre em movimento!',
    avatar_url = 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=200&h=200&fit=crop',
    neurodiv_type = 'TDAH',
    hyperfocuses = '["jogos_retro", "musica_eletronica", "programacao"]'::jsonb,
    interests = '["tecnologia", "musica", "games"]'::jsonb,
    communication_preferences = '{"preferencia": "audio", "ritmo": "rapido"}'::jsonb,
    values_and_ideas = '["liberdade", "criatividade", "diversao"]'::jsonb,
    communication_styles = '["informal", "humoristico"]'::jsonb
  WHERE id = u3;

  UPDATE public.user_profiles SET
    bio = 'Estudante de psicologia com dislexia. Defendo a neurodiversidade e o bem-estar mental. Amo cachorros!',
    avatar_url = 'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=200&h=200&fit=crop',
    neurodiv_type = 'Dislexia',
    hyperfocuses = '["psicologia", "bem_estar", "cachorros"]'::jsonb,
    interests = '["saude_mental", "animais", "educacao"]'::jsonb,
    communication_preferences = '{"preferencia": "visual", "ritmo": "moderado"}'::jsonb,
    values_and_ideas = '["empatia", "cuidado", "inclusao"]'::jsonb,
    communication_styles = '["empatico", "acolhedor"]'::jsonb
  WHERE id = u4;

  UPDATE public.user_profiles SET
    bio = 'Musico e compositor com Tourette. A musica e minha forma de me expressar sem filtros.',
    avatar_url = 'https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?w=200&h=200&fit=crop',
    neurodiv_type = 'Tourette',
    hyperfocuses = '["composicao", "guitarra", "producao_musical"]'::jsonb,
    interests = '["musica", "arte", "filosofia"]'::jsonb,
    communication_preferences = '{"preferencia": "audio", "ritmo": "variavel"}'::jsonb,
    values_and_ideas = '["autenticidade", "expressao", "liberdade"]'::jsonb,
    communication_styles = '["expressivo", "artistico"]'::jsonb
  WHERE id = u5;

  UPDATE public.user_profiles SET
    bio = 'Professora com superdotacao. Apaixonada por matematica, xadrez e astronomia. Sempre aprendendo.',
    avatar_url = 'https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=200&h=200&fit=crop',
    neurodiv_type = 'Superdotacao',
    hyperfocuses = '["matematica", "xadrez", "astronomia"]'::jsonb,
    interests = '["ciencia", "educacao", "tecnologia"]'::jsonb,
    communication_preferences = '{"preferencia": "texto", "ritmo": "detalhado"}'::jsonb,
    values_and_ideas = '["conhecimento", "precisao", "crescimento"]'::jsonb,
    communication_styles = '["analitico", "estruturado"]'::jsonb
  WHERE id = u6;

  -- ============================================================
  -- 3. PETS
  -- ============================================================
  INSERT INTO public.pets (id, owner_id, name, species, breed, age, role, photo_url, photo_semantic, bio)
  VALUES
    (p1, u2, 'Mochi', 'Gato', 'Persa', '3 anos', 'suporte_emocional',
     'https://images.unsplash.com/photo-1514888286974-6c03e2ca1dba?w=400&h=400&fit=crop',
     'Gato persa branco e fofo deitado em almofada azul',
     'Mochi e meu companheiro de hiperfoco. Ele sabe quando preciso de um abraco.'),

    (p2, u4, 'Thor', 'Cachorro', 'Golden Retriever', '2 anos', 'cao_assistencia',
     'https://images.unsplash.com/photo-1552053831-71594a27632d?w=400&h=400&fit=crop',
     'Cachorro golden retriever sorridente com lingua de fora em parque verde',
     'Thor e meu cao de assistencia. Ele me ajuda nos momentos de ansiedade.'),

    (p3, u3, 'Pixel', 'Gato', 'Siames', '1 ano', 'pet',
     'https://images.unsplash.com/photo-1573865526739-10659fec78a5?w=400&h=400&fit=crop',
     'Gato siames de olhos azuis olhando para camera com expressao curiosa',
     'Pixel e meu gato gamer. Ele sempre fica do meu lado quando estou programando.'),

    (p4, u5, 'Jazz', 'Cachorro', 'Beagle', '4 anos', 'pet',
     'https://images.unsplash.com/photo-1505628346881-b72b27e84530?w=400&h=400&fit=crop',
     'Cachorro beagle com orelhas longas sentado em sofa marrom',
     'Jazz e meu critico musical. Ele late quando a musica esta boa!')
  ON CONFLICT (id) DO NOTHING;

  -- Set active pets
  UPDATE public.user_profiles SET active_pet_id = p1 WHERE id = u2;
  UPDATE public.user_profiles SET active_pet_id = p2 WHERE id = u4;
  UPDATE public.user_profiles SET active_pet_id = p3 WHERE id = u3;
  UPDATE public.user_profiles SET active_pet_id = p4 WHERE id = u5;

  -- ============================================================
  -- 4. POSTS
  -- ============================================================
  INSERT INTO public.posts (id, author_id, content, image_url, image_semantic, hyperfocus_tags, likes_count, comments_count, is_published)
  VALUES
    (post1, u2,
     'Hoje finalmente terminei minha serie de aquarelas sobre o outono. Cada pincelada foi uma meditacao. Para quem tem TEA, o hiperfoco em arte pode ser uma forma incrivel de regulacao sensorial. Compartilhando aqui com muito carinho!',
     'https://images.unsplash.com/photo-1579783902614-a3fb3927b6a5?w=800&h=600&fit=crop',
     'Pintura em aquarela com tons de laranja e vermelho representando folhas de outono',
     '["aquarela", "arte", "TEA", "regulacao_sensorial"]'::jsonb,
     24, 8, true),

    (post2, u3,
     'Dica de produtividade para quem tem TDAH: o metodo Pomodoro mudou minha vida! 25 minutos de foco total, 5 de descanso. Meu cerebro adora essa estrutura. Alguem mais usa essa tecnica?',
     '',
     '',
     '["TDAH", "produtividade", "dicas", "pomodoro"]'::jsonb,
     41, 15, true),

    (post3, u4,
     'Hoje e o Dia Mundial da Consciencia sobre o Autismo. Quero lembrar que neurodiversidade nao e um problema a ser resolvido, e uma forma diferente de ver e sentir o mundo. Abrace quem voce e!',
     'https://images.unsplash.com/photo-1559757148-5c350d0d3c56?w=800&h=600&fit=crop',
     'Maos coloridas unidas formando circulo simbolizando unidade e diversidade',
     '["neurodiversidade", "autismo", "inclusao", "conscientizacao"]'::jsonb,
     87, 23, true),

    (post4, u5,
     'Acabei de compor uma musica nova. O Tourette as vezes me faz sentir que nao tenho controle, mas na musica eu encontro minha voz. Vou postar o audio em breve. Quem quiser ouvir, me avisa!',
     '',
     '',
     '["musica", "Tourette", "composicao", "expressao"]'::jsonb,
     33, 11, true),

    (post5, u6,
     'Reflexao do dia: superdotacao nao significa que tudo e facil. Significa que seu cerebro processa de forma diferente, as vezes mais rapido, as vezes com mais profundidade. Mas os desafios emocionais e sociais sao muito reais. Voce nao esta sozinho.',
     '',
     '',
     '["superdotacao", "saude_mental", "reflexao", "neurodiversidade"]'::jsonb,
     56, 19, true),

    (post6, u1,
     'Bem-vindos a SintonIA! Esta plataforma foi criada para que pessoas neurodivergentes possam se conectar, compartilhar experiencias e encontrar apoio. Aqui voce e aceito como e. Vamos construir essa comunidade juntos!',
     'https://images.unsplash.com/photo-1529156069898-49953e39b3ac?w=800&h=600&fit=crop',
     'Grupo de pessoas diversas sorrindo e se abraçando em ambiente acolhedor',
     '["comunidade", "neurodiversidade", "boas_vindas", "inclusao"]'::jsonb,
     112, 34, true)
  ON CONFLICT (id) DO NOTHING;

  -- ============================================================
  -- 5. POST COMMENTS
  -- ============================================================
  INSERT INTO public.post_comments (post_id, author_id, content, is_visible)
  VALUES
    (post1, u4, 'Que lindo! A arte realmente tem esse poder de nos ancorar. Parabens pela serie!', true),
    (post1, u3, 'Incrivel! Voce tem um talento enorme. Ja pensei em fazer um curso de aquarela.', true),
    (post2, u2, 'Uso o Pomodoro ha 2 anos e transformou minha rotina. Dica de ouro!', true),
    (post2, u6, 'Excelente tecnica. Combina muito bem com o funcionamento do cerebro com TDAH.', true),
    (post3, u2, 'Obrigada por esse lembrete tao importante. Precisamos de mais vozes como a sua!', true),
    (post3, u5, 'Compartilhei com minha familia. Muito necessario esse tipo de conscientizacao.', true),
    (post4, u2, 'Mal posso esperar para ouvir! A musica tem um poder incrivel de cura.', true),
    (post5, u4, 'Isso precisa ser dito mais vezes. Obrigada por compartilhar com tanta honestidade.', true),
    (post6, u2, 'Que plataforma incrivel! Finalmente um lugar onde me sinto em casa.', true),
    (post6, u3, 'Ja indiquei para varios amigos. Essa comunidade e especial!', true)
  ON CONFLICT (id) DO NOTHING;

  -- ============================================================
  -- 6. POST LIKES
  -- ============================================================
  INSERT INTO public.post_likes (post_id, user_id)
  VALUES
    (post1, u3), (post1, u4), (post1, u5), (post1, u6), (post1, u1),
    (post2, u2), (post2, u4), (post2, u5), (post2, u6), (post2, u1),
    (post3, u1), (post3, u2), (post3, u3), (post3, u5), (post3, u6),
    (post4, u1), (post4, u2), (post4, u4), (post4, u6),
    (post5, u1), (post5, u2), (post5, u3), (post5, u4),
    (post6, u2), (post6, u3), (post6, u4), (post6, u5), (post6, u6)
  ON CONFLICT DO NOTHING;

  -- ============================================================
  -- 7. FRIENDSHIPS
  -- ============================================================
  INSERT INTO public.friendships (requester_id, addressee_id, status)
  VALUES
    (u2, u3, 'accepted'),
    (u2, u4, 'accepted'),
    (u3, u5, 'accepted'),
    (u4, u6, 'accepted'),
    (u5, u6, 'accepted'),
    (u1, u2, 'accepted'),
    (u1, u3, 'accepted'),
    (u2, u5, 'pending'),
    (u3, u6, 'pending')
  ON CONFLICT DO NOTHING;

  -- ============================================================
  -- 8. GROUPS
  -- ============================================================
  INSERT INTO public.groups (id, creator_id, name, description, cover_url, cover_semantic, neurodiv_focus, hyperfocus_tags, members_count, is_public)
  VALUES
    (g1, u1,
     'TEA & Arte Terapia',
     'Espaco para pessoas no espectro autista compartilharem experiencias com arte terapia, aquarela, desenho e outras formas de expressao criativa como ferramenta de regulacao sensorial.',
     'https://images.unsplash.com/photo-1513364776144-60967b0f800f?w=800&h=400&fit=crop',
     'Pinceis coloridos e paleta de tintas sobre mesa de madeira',
     '["TEA"]'::jsonb,
     '["arte", "aquarela", "terapia", "regulacao_sensorial"]'::jsonb,
     4, true),

    (g2, u3,
     'TDAH Produtivo',
     'Grupo para trocar dicas, tecnicas e estrategias de produtividade especificas para o cerebro com TDAH. Pomodoro, GTD, bullet journal e muito mais.',
     'https://images.unsplash.com/photo-1484480974693-6ca0a78fb36b?w=800&h=400&fit=crop',
     'Agenda aberta com canetas coloridas e post-its organizados sobre mesa',
     '["TDAH"]'::jsonb,
     '["produtividade", "organizacao", "foco", "rotina"]'::jsonb,
     3, true)
  ON CONFLICT (id) DO NOTHING;

  -- Group members
  INSERT INTO public.group_members (group_id, user_id, is_admin)
  VALUES
    (g1, u1, true),
    (g1, u2, false),
    (g1, u4, false),
    (g1, u6, false),
    (g2, u3, true),
    (g2, u2, false),
    (g2, u5, false)
  ON CONFLICT DO NOTHING;

  -- ============================================================
  -- 9. CONVERSATIONS & MESSAGES
  -- ============================================================
  INSERT INTO public.conversations (id, is_group, last_message, last_message_at)
  VALUES
    (conv1, false, 'Adorei sua serie de aquarelas! Voce aceita encomendas?', now() - interval '2 hours'),
    (conv2, false, 'Obrigado pela dica do Pomodoro, funcionou muito bem!', now() - interval '1 day')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.conversation_participants (conversation_id, user_id, unread_count)
  VALUES
    (conv1, u2, 0),
    (conv1, u4, 1),
    (conv2, u3, 0),
    (conv2, u6, 0)
  ON CONFLICT DO NOTHING;

  INSERT INTO public.messages (conversation_id, sender_id, content, message_type, is_read)
  VALUES
    (conv1, u4, 'Oi Ana! Vi seus posts de aquarela e fiquei encantada.', 'text', true),
    (conv1, u2, 'Oi Julia! Que bom que gostou, obrigada!', 'text', true),
    (conv1, u4, 'Voce aceita encomendas? Queria um quadro para meu consultorio.', 'text', true),
    (conv1, u2, 'Adorei sua serie de aquarelas! Voce aceita encomendas?', 'text', false),
    (conv2, u6, 'Carlos, vi sua dica sobre Pomodoro no feed.', 'text', true),
    (conv2, u3, 'Oi Mariana! Sim, mudou minha vida. Posso te explicar melhor.', 'text', true),
    (conv2, u3, 'Obrigado pela dica do Pomodoro, funcionou muito bem!', 'text', true)
  ON CONFLICT (id) DO NOTHING;

  -- ============================================================
  -- 10. STORIES
  -- ============================================================
  INSERT INTO public.stories (id, author_id, media_url, media_semantic, expires_at, views_count)
  VALUES
    (s1, u2,
     'https://images.unsplash.com/photo-1541961017774-22349e4a1262?w=600&h=1000&fit=crop',
     'Pintura em aquarela de flores silvestres em tons de roxo e azul',
     now() + interval '20 hours', 12),

    (s2, u3,
     'https://images.unsplash.com/photo-1498050108023-c5249f4df085?w=600&h=1000&fit=crop',
     'Tela de computador com codigo colorido em editor de texto escuro',
     now() + interval '18 hours', 8)
  ON CONFLICT (id) DO NOTHING;

  -- ============================================================
  -- 11. PET DIARY ENTRIES
  -- ============================================================
  INSERT INTO public.pet_diary_entries (pet_id, owner_id, entry_text, image_url, image_semantic, likes_count)
  VALUES
    (p1, u2,
     'Mochi ficou do meu lado a tarde toda enquanto eu pintava. Ele parece sentir quando estou em modo hiperfoco e simplesmente fica quietinho perto de mim. Amor puro.',
     'https://images.unsplash.com/photo-1514888286974-6c03e2ca1dba?w=600&h=400&fit=crop',
     'Gato persa branco dormindo ao lado de materiais de pintura coloridos',
     7),

    (p2, u4,
     'Thor completou mais uma semana de treinamento de assistencia emocional. Ele ja reconhece quando estou ansiosa e vem me dar apoio. Estou tao orgulhosa dele!',
     'https://images.unsplash.com/photo-1552053831-71594a27632d?w=600&h=400&fit=crop',
     'Cachorro golden retriever com colete de cao de assistencia sentado ao lado de jovem',
     15),

    (p3, u3,
     'Pixel descobriu que pode sentar no teclado enquanto eu programo. Agora toda vez que paro de digitar ele ocupa o espaco. Acho que ele quer ser desenvolvedor tambem.',
     'https://images.unsplash.com/photo-1573865526739-10659fec78a5?w=600&h=400&fit=crop',
     'Gato siames sentado sobre teclado de computador com expressao satisfeita',
     21)
  ON CONFLICT (id) DO NOTHING;

  -- ============================================================
  -- 12. USER DIARY ENTRIES
  -- ============================================================
  INSERT INTO public.user_diary_entries (user_id, title, content, mood, tags, is_private)
  VALUES
    (u2,
     'Dia de hiperfoco na aquarela',
     'Hoje acordei com aquela energia especial que so aparece quando o hiperfoco bate. Passei 6 horas pintando sem perceber o tempo passar. Minha serie de outono esta quase pronta. Me sinto completa quando estou criando.',
     'feliz',
     '["hiperfoco", "arte", "aquarela", "criatividade"]'::jsonb,
     true),

    (u4,
     'Reflexao sobre minha jornada com a dislexia',
     'Hoje um aluno me perguntou como eu me tornei professora tendo dislexia. Respondi que a dislexia me ensinou a pensar de forma diferente, a encontrar caminhos alternativos. Nao e uma limitacao, e uma perspectiva unica.',
     'reflexivo',
     '["dislexia", "educacao", "superacao", "perspectiva"]'::jsonb,
     false),

    (u5,
     'Nova composicao finalizada',
     'Finalmente terminei a musica que estava compondo ha tres semanas. O Tourette me deu alguns desafios durante a gravacao, mas o resultado ficou autentico. A musica captura exatamente o que queria expressar.',
     'realizado',
     '["musica", "composicao", "Tourette", "expressao"]'::jsonb,
     true)
  ON CONFLICT (id) DO NOTHING;

  -- ============================================================
  -- 13. USER SETTINGS
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

  -- ============================================================
  -- 14. NOTIFICATIONS
  -- ============================================================
  -- Check if notifications table exists before inserting
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'notifications'
  ) THEN
    INSERT INTO public.notifications (id, user_id, type, title, body, is_read, created_at)
    VALUES
      (n1, u2,
       'friend_request',
       'Nova solicitacao de amizade',
       'Pedro Lima quer se conectar com voce',
       false,
       now() - interval '30 minutes'),

      (n2, u2,
       'post_like',
       'Curtida na sua publicacao',
       'Carlos Mendes curtiu sua publicacao sobre aquarela',
       true,
       now() - interval '2 hours'),

      (n3, u4,
       'post_comment',
       'Comentario na sua publicacao',
       'Ana Silva comentou: "Obrigada por esse lembrete tao importante!"',
       false,
       now() - interval '1 hour')
    ON CONFLICT (id) DO NOTHING;
  END IF;

  -- ============================================================
  -- 15. AI CHAT HISTORY (sample)
  -- ============================================================
  INSERT INTO public.ai_chat_history (user_id, role, content)
  VALUES
    (u2, 'user', 'Oi SintonIA! Estou me sentindo sobrecarregada hoje. Tive muita estimulacao sensorial.'),
    (u2, 'model', 'Oi Ana! Entendo como isso pode ser exaustivo. Estimulacao sensorial excessiva e muito comum para pessoas com TEA. Voce ja tentou alguma tecnica de regulacao sensorial? Algumas pessoas acham util usar fones de ouvido com cancelamento de ruido, ou passar um tempo em um ambiente mais calmo e com pouca luz.'),
    (u2, 'user', 'Sim, vou tentar isso. Obrigada!'),
    (u3, 'user', 'SintonIA, tenho dificuldade em manter o foco nas tarefas. Alguma dica?'),
    (u3, 'model', 'Ola Carlos! Para o TDAH, tecnicas de gerenciamento de tempo podem ajudar muito. O metodo Pomodoro (25 min de foco + 5 de pausa) e muito eficaz. Tambem e importante eliminar distractores do ambiente e dividir tarefas grandes em partes menores. Voce ja experimentou alguma dessas abordagens?')
  ON CONFLICT (id) DO NOTHING;

  RAISE NOTICE 'Seed data inserted successfully!';
  RAISE NOTICE 'Demo accounts:';
  RAISE NOTICE '  admin@sintonia.app / sintonia123 (admin)';
  RAISE NOTICE '  ana.silva@email.com / sintonia123';
  RAISE NOTICE '  carlos.mendes@email.com / sintonia123';
  RAISE NOTICE '  julia.costa@email.com / sintonia123';
  RAISE NOTICE '  pedro.lima@email.com / sintonia123';
  RAISE NOTICE '  mariana.rocha@email.com / sintonia123';

EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'Seed data error: %', SQLERRM;
END $$;
