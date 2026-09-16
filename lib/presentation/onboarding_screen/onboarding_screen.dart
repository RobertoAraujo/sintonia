import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../routes/app_routes.dart';
import '../../services/media_permission_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/medical_disclaimer_banner_widget.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  final int _totalSteps = 9;

  late AnimationController _progressCtrl;
  late Animation<double> _progressAnim;

  // Step 1 — Basic info
  final _nameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;
  String? _authError;

  // Step 2 — Neurotype conditions
  final List<String> _allNeurotypes = [
    'TDAH',
    'TEA (Autismo)',
    'Dislexia',
    'Altas Habilidades / Superdotação',
    'Discalculia',
    'Dispraxia',
    'Síndrome de Tourette',
    'Síndrome de Asperger',
    'TOC (Transtorno Obsessivo-Compulsivo)',
    'TOD (Transtorno Opositor Desafiador)',
    'TAG (Ansiedade Generalizada)',
    'Ansiedade Social',
    'Depressão',
    'Transtorno Bipolar',
    'TEPT / TEPT-C',
    'Dificuldade de Processamento Sensorial',
    'Transtorno de Pânico',
    'Borderline (TPB)',
    'Transtorno Dissociativo',
    'Transtorno Alimentar',
    'Acalculia',
    'Agrafia / Disgrafia',
    'Neurotípico',
    'Em Diagnóstico / Investigação',
  ];
  final Set<String> _selectedNeurotypes = {};
  final _customNeuroCtrl = TextEditingController();

  // Step 3 — Social battery & sensory sensitivity
  double _socialBattery = 3;
  double _sensorySensitivity = 3;

  // Multi-select sensory triggers
  final List<String> _selectedSensoryTriggers = [];
  final List<String> _sensoryTriggers = [
    'Ruídos altos',
    'Luzes fortes',
    'Multidões',
    'Texturas específicas',
    'Cheiros intensos',
    'Contato físico inesperado',
    'Ambientes caóticos',
    'Nenhum gatilho específico',
  ];
  static const String _sensoryNeutral = 'Nenhum gatilho específico';

  // Step 4 — Political & religious views (multi-select)
  final List<String> _selectedPoliticalViews = [];
  final List<String> _selectedReligions = [];
  bool _politicalTolerance = true;
  bool _religiousTolerance = true;
  final List<String> _politicalOptions = [
    'Progressista',
    'Liberal',
    'Centro',
    'Conservador',
    'Libertário',
    'Anarquista',
    'Prefiro não dizer',
  ];
  final List<String> _religiousOptions = [
    'Ateu/Agnóstico',
    'Cristão',
    'Espírita',
    'Budista',
    'Umbanda/Candomblé',
    'Judeu',
    'Muçulmano',
    'Hinduísta',
    'Espiritualista',
    'Prefiro não dizer',
  ];
  static const String _politicalNeutral = 'Prefiro não dizer';
  static const String _religiousNeutral = 'Prefiro não dizer';

  // Step 5 — Diet & food selectivity
  String _dietProfile = '';
  bool _foodSelectivity = false;
  final List<String> _dietOptions = [
    'Onívoro',
    'Vegetariano',
    'Vegano',
    'Flexitariano',
    'Carnívoro',
    'Sem glúten',
    'Sem lactose',
    'Kosher',
    'Halal',
    'Seletivo (ARFID)',
  ];
  final List<String> _foodAvoidances = [];
  final _foodAvoidanceCtrl = TextEditingController();

  // Step 6 — Hyperfocuses & hobbies
  final List<String> _allHyperfocuses = [
    'Programação / Dev',
    'Jogos (Video Games)',
    'Anime / Mangá',
    'Música',
    'Arte / Desenho',
    'Escrita / Fanfic',
    'Ciências',
    'Matemática',
    'Astronomia',
    'Biologia / Natureza',
    'História',
    'Filosofia',
    'Filmes / Séries',
    'Fotografia',
    'Culinária / Confeitaria',
    'Esportes',
    'Leitura',
    'Tecnologia',
    'Moda',
    'Idiomas',
    'Política',
    'Psicologia',
    'Medicina',
    'Direito',
    'Economia',
    'Robótica',
    'Eletrônica',
    'RPG / D&D',
    'Cosplay',
    'Jardinagem / Plantas',
    'Animais / Pets',
    'Design / UI/UX',
    'Modelagem 3D',
    'True Crime',
    'Mitologia',
    'Música Clássica',
    'K-Pop',
    'Xadrez / Boardgames',
    'Arqueologia',
    'Colecionáveis',
  ];
  final Set<String> _selectedHyperfocuses = {};
  final _customHyperfocusCtrl = TextEditingController();

  // Step 7 — Communication style
  final List<Map<String, dynamic>> _commStyles = [
    {
      'label': 'Texto curto',
      'icon': Icons.short_text_rounded,
      'value': 'shortText',
    },
    {
      'label': 'Texto longo',
      'icon': Icons.article_outlined,
      'value': 'longText',
    },
    {'label': 'Áudio', 'icon': Icons.mic_none_rounded, 'value': 'audio'},
    {'label': 'Vídeo', 'icon': Icons.videocam_outlined, 'value': 'video'},
    {
      'label': 'Mensagens diretas',
      'icon': Icons.send_rounded,
      'value': 'directMessages',
    },
    {
      'label': 'Assíncrono',
      'icon': Icons.schedule_rounded,
      'value': 'asyncMessages',
    },
    {
      'label': 'Emojis 🎉',
      'icon': Icons.emoji_emotions_outlined,
      'value': 'emojiHeavy',
    },
    {
      'label': 'Tom formal',
      'icon': Icons.business_center_outlined,
      'value': 'formalTone',
    },
    {
      'label': 'Tom informal',
      'icon': Icons.chat_bubble_outline_rounded,
      'value': 'informalTone',
    },
  ];
  final Set<String> _selectedCommStyles = {};

  // Step 8 — Goals on the platform
  final List<Map<String, dynamic>> _goalOptions = [
    {
      'label': 'Fazer amizades',
      'icon': Icons.people_outline_rounded,
      'value': 'friendships',
    },
    {
      'label': 'Encontrar parceiro(a)',
      'icon': Icons.favorite_border_rounded,
      'value': 'romance',
    },
    {
      'label': 'Trocar experiências',
      'icon': Icons.swap_horiz_rounded,
      'value': 'experiences',
    },
    {
      'label': 'Suporte emocional',
      'icon': Icons.volunteer_activism_outlined,
      'value': 'support',
    },
    {
      'label': 'Colaborar em projetos',
      'icon': Icons.handshake_outlined,
      'value': 'collaboration',
    },
    {
      'label': 'Aprender juntos',
      'icon': Icons.school_outlined,
      'value': 'learning',
    },
    {
      'label': 'Comunidade neurodivergente',
      'icon': Icons.diversity_3_outlined,
      'value': 'community',
    },
    {
      'label': 'Só explorar',
      'icon': Icons.explore_outlined,
      'value': 'explore',
    },
  ];
  final Set<String> _selectedGoals = {};

  // Step 9 — Age verification & consents
  DateTime? _birthDate;
  String _birthDateText = '';
  bool _isAgeValid = false;
  bool _pushNotificationsEnabled = false;
  bool _locationEnabled = false;
  bool _cameraGalleryEnabled = false;
  bool _microphoneEnabled = false;
  bool _sensitiveDataConsent = false;
  bool _termsAccepted = false;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _progressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _progressAnim = Tween<double>(begin: 0, end: 1 / _totalSteps).animate(
      CurvedAnimation(parent: _progressCtrl, curve: Curves.easeOutCubic),
    );
    _progressCtrl.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _progressCtrl.dispose();
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _foodAvoidanceCtrl.dispose();
    _customHyperfocusCtrl.dispose();
    _customNeuroCtrl.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep < _totalSteps - 1) {
      setState(() => _currentStep++);
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
      _progressCtrl.animateTo((_currentStep + 1) / _totalSteps);
    } else {
      _finishOnboarding();
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
      _pageController.previousPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
      _progressCtrl.animateTo((_currentStep + 1) / _totalSteps);
    }
  }

  /// Toggle logic for multi-select chips with mutual-exclusion for neutral options.
  /// [neutralOption] — if provided, selecting it clears all others; selecting
  /// any other option clears the neutral one.
  void _toggleMultiSelect(
    List<String> list,
    String value, {
    String? neutralOption,
  }) {
    setState(() {
      if (list.contains(value)) {
        list.remove(value);
      } else {
        if (neutralOption != null && value == neutralOption) {
          // Selecting the neutral option → clear everything else
          list.clear();
          list.add(value);
        } else {
          // Selecting a regular option → remove neutral if present
          if (neutralOption != null) {
            list.remove(neutralOption);
          }
          list.add(value);
        }
      }
    });
  }

  Future<void> _toggleCameraGalleryPermission(bool enabled) async {
    if (!enabled) {
      if (mounted) setState(() => _cameraGalleryEnabled = false);
      return;
    }

    final cameraAllowed = await MediaPermissionService.request(camera: true);
    final galleryAllowed = await MediaPermissionService.request(camera: false);
    if (!mounted) return;

    setState(() => _cameraGalleryEnabled = cameraAllowed && galleryAllowed);
    if (!cameraAllowed || !galleryAllowed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permissão de câmera ou galeria negada.')),
      );
    }
  }

  Future<void> _finishOnboarding() async {
    setState(() {
      _isLoading = true;
      _authError = null;
    });

    try {
      // 1. Create auth account
      final signUpResponse = await SupabaseService.instance.signUp(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
        fullName: _nameCtrl.text.trim(),
        username: _nameCtrl.text.trim().toLowerCase().replaceAll(' ', '_'),
      );

      if (!mounted) return;

      if (signUpResponse.user == null) {
        setState(() {
          _isLoading = false;
          _authError = 'Não foi possível criar a conta. Tente novamente.';
        });
        return;
      }

      // 2. Sign in immediately to establish a valid session (required for RLS)
      final signInResponse = await SupabaseService.instance.signIn(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );

      if (!mounted) return;

      if (signInResponse.user == null || signInResponse.session == null) {
        setState(() {
          _isLoading = false;
          _authError =
              'Conta criada, mas não foi possível fazer login. Tente entrar manualmente.';
        });
        return;
      }

      // 3. Map selected neurotype to valid enum value
      String? neurodivTypeValue;
      if (_selectedNeurotypes.isNotEmpty) {
        const enumMap = {
          'TDAH': 'TDAH',
          'TEA (Autismo)': 'TEA',
          'Dislexia': 'Dislexia',
          'Síndrome de Tourette': 'Tourette',
          'Discalculia': 'Discalculia',
          'Altas Habilidades / Superdotação': 'Superdotacao',
          'TOC': 'TOC',
          'Síndrome de Asperger': 'TEA',
        };
        final first = _selectedNeurotypes.first;
        neurodivTypeValue = enumMap[first] ?? 'Outro';
      }

      // 4. Save full profile data — now we have a valid session so RLS allows it
      final uid = signInResponse.user!.id;
      final now = DateTime.now().toIso8601String();
      await SupabaseService.instance.client.from('user_profiles').upsert({
        'id': uid,
        'email': _emailCtrl.text.trim(),
        'full_name': _nameCtrl.text.trim(),
        'username': _nameCtrl.text.trim().toLowerCase().replaceAll(' ', '_'),
        'bio': _bioCtrl.text.trim(),
        if (neurodivTypeValue != null) 'neurodiv_type': neurodivTypeValue,
        'hyperfocuses': _selectedHyperfocuses
            .map((h) => {'name': h, 'color': 0xFF4A90D9})
            .toList(),
        'interests': _selectedHyperfocuses.toList(),
        // Dedicated TEXT[] columns for multi-select fields
        'sensory_triggers': _selectedSensoryTriggers,
        'political_views': _selectedPoliticalViews,
        'religions': _selectedReligions,
        // Step 9 — Age & consents
        if (_birthDate != null)
          'birth_date': _birthDate!.toIso8601String().split('T').first,
        'is_adult': _isAgeValid,
        'push_notifications_enabled': _pushNotificationsEnabled,
        'location_permissions_enabled': _locationEnabled,
        'camera_gallery_enabled': _cameraGalleryEnabled,
        'microphone_enabled': _microphoneEnabled,
        'sensitive_data_consent': _sensitiveDataConsent,
        if (_termsAccepted) 'privacy_policy_accepted_at': now,
        if (_termsAccepted) 'terms_accepted_at': now,
        // Store extra onboarding data in communication_preferences JSONB
        'communication_preferences': {
          'social_battery': _socialBattery.round(),
          'sensory_sensitivity': _sensorySensitivity.round(),
          'diet_profile': _dietProfile,
          'food_selectivity': _foodSelectivity,
          'food_avoidances': _foodAvoidances,
          'political_tolerance': _politicalTolerance,
          'religious_tolerance': _religiousTolerance,
          'goals': _selectedGoals.toList(),
          'comm_styles': _selectedCommStyles.toList(),
          'all_neurotypes': _selectedNeurotypes.toList(),
        },
      });

      if (!mounted) return;
      setState(() => _isLoading = false);
      context.go(AppRoutes.homeFeedScreen);
    } catch (e) {
      if (!mounted) return;
      final errorMsg = _mapSignUpError(e.toString());
      setState(() {
        _isLoading = false;
        _authError = errorMsg;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  String _mapSignUpError(String error) {
    if (error.contains('already registered') ||
        error.contains('already been registered') ||
        error.contains('user_already_exists') ||
        error.contains('already exists')) {
      return 'Este e-mail já está cadastrado. Faça login.';
    }
    if (error.contains('weak_password') || error.contains('weak password')) {
      return 'Senha muito fraca. Use pelo menos 6 caracteres.';
    }
    if (error.contains('invalid_email') || error.contains('Invalid email')) {
      return 'E-mail inválido.';
    }
    if (error.contains('network') || error.contains('SocketException')) {
      return 'Sem conexão. Verifique sua internet.';
    }
    if (error.contains('email not confirmed') ||
        error.contains('Email not confirmed')) {
      return 'Confirme seu e-mail antes de continuar.';
    }
    return 'Erro ao criar conta: ${error.length > 120 ? error.substring(0, 120) : error}';
  }

  bool _canProceed() {
    switch (_currentStep) {
      case 0:
        final emailRegex = RegExp(
          r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$',
        );
        return _nameCtrl.text.trim().isNotEmpty &&
            emailRegex.hasMatch(_emailCtrl.text.trim()) &&
            _passwordCtrl.text.length >= 8;
      case 1:
        return _selectedNeurotypes.isNotEmpty;
      case 5:
        return _selectedHyperfocuses.isNotEmpty;
      case 6:
        return _selectedCommStyles.isNotEmpty;
      case 7:
        return _selectedGoals.isNotEmpty;
      case 8:
        return _isAgeValid && _sensitiveDataConsent && _termsAccepted;
      default:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(theme),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildStep0BasicInfo(theme),
                  _buildStep1Neurotypes(theme),
                  _buildStep2SensoryProfile(theme),
                  _buildStep3Values(theme),
                  _buildStep4Diet(theme),
                  _buildStep5Hyperfocuses(theme),
                  _buildStep6CommStyle(theme),
                  _buildStep7Goals(theme),
                  _buildStep8Consents(theme),
                ],
              ),
            ),
            _buildBottomNav(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final stepTitles = [
      'Quem é você?',
      'Seu perfil neurodivergente',
      'Perfil sensorial',
      'Seus valores',
      'Alimentação',
      'Hiperfocos & Hobbies',
      'Como você se comunica?',
      'O que você busca?',
      'Idade e Consentimentos',
    ];
    final stepSubtitles = [
      'Crie sua conta na SintonIA',
      'Selecione seus diagnósticos ou identificações',
      'Bateria social e sensibilidade sensorial',
      'Política, religião e estilo de vida',
      'Dieta e seletividade alimentar',
      'Seus temas de interesse profundo',
      'Seu estilo de comunicação preferido',
      'Seus objetivos na SintonIA',
      'Confirmação de idade e permissões',
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () {
                  if (_currentStep == 0) {
                    context.go(AppRoutes.loginScreen);
                  } else {
                    _prevStep();
                  }
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(25),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 16,
                    color: Colors.black87,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_currentStep + 1} / $_totalSteps',
                  style: GoogleFonts.nunitoSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AnimatedBuilder(
            animation: _progressCtrl,
            builder: (context, _) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (_currentStep + 1) / _totalSteps,
                  backgroundColor: theme.colorScheme.outlineVariant,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppTheme.primary,
                  ),
                  minHeight: 6,
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          Text(
            stepTitles[_currentStep],
            style: GoogleFonts.nunitoSans(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            stepSubtitles[_currentStep],
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildBottomNav(ThemeData theme) {
    final isLast = _currentStep == _totalSteps - 1;
    final canProceed = _canProceed();
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: AppTheme.backgroundLight,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: 52,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: canProceed
                      ? [AppTheme.primary, AppTheme.primaryLight]
                      : [
                          theme.colorScheme.outlineVariant,
                          theme.colorScheme.outlineVariant,
                        ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: canProceed
                    ? [
                        BoxShadow(
                          color: AppTheme.primary.withAlpha(70),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
                        ),
                      ]
                    : [],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: canProceed && !_isLoading ? _nextStep : null,
                  borderRadius: BorderRadius.circular(16),
                  child: Center(
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                isLast ? 'Concluir Cadastro 🎉' : 'Continuar',
                                style: GoogleFonts.nunitoSans(
                                  color: canProceed
                                      ? Colors.white
                                      : theme.colorScheme.onSurfaceVariant,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (!isLast) ...[
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 18,
                                  color: canProceed
                                      ? Colors.white
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                              ],
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── STEP 0: Basic Info ───────────────────────────────────────────────────
  Widget _buildStep0BasicInfo(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Column(
              children: [
                Image.asset(
                  'assets/images/image-1789169868770.png',
                  width: 100,
                  height: 100,
                  fit: BoxFit.contain,
                  semanticLabel: 'SintonIA logotipo',
                ),
                const SizedBox(height: 8),
                Stack(
                  children: [
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppTheme.primary, AppTheme.secondary],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.person_rounded,
                        color: Colors.white,
                        size: 44,
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: AppTheme.secondary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          Icons.camera_alt_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildTextField(
            controller: _nameCtrl,
            label: 'Como quer ser chamado(a)?',
            hint: 'Seu nome ou apelido',
            icon: Icons.badge_outlined,
            theme: theme,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _bioCtrl,
            label: 'Bio (opcional)',
            hint: 'Conte algo sobre você em poucas palavras...',
            icon: Icons.edit_note_rounded,
            theme: theme,
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _emailCtrl,
            label: 'E-mail',
            hint: 'seu@email.com',
            icon: Icons.mail_outline_rounded,
            theme: theme,
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordCtrl,
            obscureText: _obscurePassword,
            onChanged: (_) => setState(() {}),
            style: theme.textTheme.bodyMedium,
            decoration: InputDecoration(
              labelText: 'Senha',
              hintText: 'Mínimo 6 caracteres',
              prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
              suffixIcon: IconButton(
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              filled: true,
              fillColor: theme.colorScheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppTheme.primary, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ─── STEP 1: Neurotypes ───────────────────────────────────────────────────
  Widget _buildStep1Neurotypes(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _allNeurotypes.map((n) {
              final isSelected = _selectedNeurotypes.contains(n);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _selectedNeurotypes.remove(n);
                    } else {
                      _selectedNeurotypes.add(n);
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primary
                        : theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.primary
                          : theme.colorScheme.outlineVariant,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Text(
                    n,
                    style: GoogleFonts.nunitoSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? Colors.white
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customNeuroCtrl,
                  decoration: InputDecoration(
                    hintText: 'Outro diagnóstico / identificação...',
                    filled: true,
                    fillColor: theme.colorScheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppTheme.primary,
                        width: 2,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () {
                  final v = _customNeuroCtrl.text.trim();
                  if (v.isNotEmpty) {
                    setState(() {
                      _selectedNeurotypes.add(v);
                      _customNeuroCtrl.clear();
                    });
                  }
                },
                icon: const Icon(Icons.add_circle_rounded),
                color: AppTheme.primary,
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ─── STEP 2: Sensory Profile ──────────────────────────────────────────────
  Widget _buildStep2SensoryProfile(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Bateria Social', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Quanto você se sente energizado por interações sociais?',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Slider(
            value: _socialBattery,
            min: 1,
            max: 5,
            divisions: 4,
            activeColor: AppTheme.primary,
            label: _socialBattery.round().toString(),
            onChanged: (v) => setState(() => _socialBattery = v),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Introvertido',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                'Extrovertido',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Sensibilidade Sensorial', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Quão sensível você é a estímulos sensoriais?',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Slider(
            value: _sensorySensitivity,
            min: 1,
            max: 5,
            divisions: 4,
            activeColor: AppTheme.secondary,
            label: _sensorySensitivity.round().toString(),
            onChanged: (v) => setState(() => _sensorySensitivity = v),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Baixa',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                'Alta',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Gatilhos Sensoriais', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Selecione todos que se aplicam',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          _buildMultiSelectChips(
            theme: theme,
            options: _sensoryTriggers,
            selected: _selectedSensoryTriggers,
            onToggle: (v) => _toggleMultiSelect(
              _selectedSensoryTriggers,
              v,
              neutralOption: _sensoryNeutral,
            ),
            color: AppTheme.secondary,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ─── STEP 3: Values ───────────────────────────────────────────────────────
  Widget _buildStep3Values(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Visão Política', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Selecione todas que se aplicam',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          _buildMultiSelectChips(
            theme: theme,
            options: _politicalOptions,
            selected: _selectedPoliticalViews,
            onToggle: (v) => _toggleMultiSelect(
              _selectedPoliticalViews,
              v,
              neutralOption: _politicalNeutral,
            ),
            color: AppTheme.primary,
          ),
          const SizedBox(height: 8),
          _buildToleranceToggle(
            theme,
            label: 'Aceito pessoas com visões políticas diferentes',
            value: _politicalTolerance,
            onChanged: (v) => setState(() => _politicalTolerance = v),
          ),
          const SizedBox(height: 24),
          Text('Religião / Espiritualidade', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Selecione todas que se aplicam',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          _buildMultiSelectChips(
            theme: theme,
            options: _religiousOptions,
            selected: _selectedReligions,
            onToggle: (v) => _toggleMultiSelect(
              _selectedReligions,
              v,
              neutralOption: _religiousNeutral,
            ),
            color: AppTheme.secondary,
          ),
          const SizedBox(height: 8),
          _buildToleranceToggle(
            theme,
            label: 'Aceito pessoas com crenças diferentes',
            value: _religiousTolerance,
            onChanged: (v) => setState(() => _religiousTolerance = v),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ─── STEP 4: Diet ─────────────────────────────────────────────────────────
  Widget _buildStep4Diet(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Perfil Alimentar', style: theme.textTheme.titleSmall),
          const SizedBox(height: 12),
          _buildSingleSelectChips(
            theme: theme,
            options: _dietOptions,
            selected: _dietProfile,
            onSelect: (v) => setState(() => _dietProfile = v),
            color: AppTheme.success,
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Tenho seletividade alimentar (ARFID)',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Switch(
                value: _foodSelectivity,
                onChanged: (v) => setState(() => _foodSelectivity = v),
                activeThumbColor: AppTheme.primary,
              ),
            ],
          ),
          if (_foodSelectivity) ...[
            const SizedBox(height: 16),
            Text('Alimentos que evito:', style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _foodAvoidanceCtrl,
                    decoration: InputDecoration(
                      hintText: 'Ex: tomate, cebola...',
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppTheme.primary,
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    final v = _foodAvoidanceCtrl.text.trim();
                    if (v.isNotEmpty) {
                      setState(() {
                        _foodAvoidances.add(v);
                        _foodAvoidanceCtrl.clear();
                      });
                    }
                  },
                  icon: const Icon(Icons.add_circle_rounded),
                  color: AppTheme.primary,
                ),
              ],
            ),
            if (_foodAvoidances.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _foodAvoidances
                    .map(
                      (f) => Chip(
                        label: Text(f),
                        deleteIcon: const Icon(Icons.close, size: 14),
                        onDeleted: () =>
                            setState(() => _foodAvoidances.remove(f)),
                        backgroundColor: AppTheme.error.withAlpha(20),
                        labelStyle: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.error,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ─── STEP 5: Hyperfocuses ─────────────────────────────────────────────────
  Widget _buildStep5Hyperfocuses(ThemeData theme) {
    // Chips to display: predefined list + any custom ones not in the predefined list
    final customSelected = _selectedHyperfocuses
        .where((h) => !_allHyperfocuses.contains(h))
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ..._allHyperfocuses.map((h) {
                final isSelected = _selectedHyperfocuses.contains(h);
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        _selectedHyperfocuses.remove(h);
                      } else {
                        _selectedHyperfocuses.add(h);
                      }
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.secondary
                          : theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.secondary
                            : theme.colorScheme.outlineVariant,
                      ),
                    ),
                    child: Text(
                      h,
                      style: GoogleFonts.nunitoSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? Colors.white
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                );
              }),
              ...customSelected.map(
                (h) => Chip(
                  label: Text(
                    h,
                    style: GoogleFonts.nunitoSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  backgroundColor: AppTheme.secondary,
                  deleteIcon: const Icon(
                    Icons.close,
                    size: 14,
                    color: Colors.white,
                  ),
                  onDeleted: () =>
                      setState(() => _selectedHyperfocuses.remove(h)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customHyperfocusCtrl,
                  decoration: InputDecoration(
                    hintText: 'Adicionar hiperfoco personalizado...',
                    filled: true,
                    fillColor: theme.colorScheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppTheme.secondary,
                        width: 2,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () {
                  final v = _customHyperfocusCtrl.text.trim();
                  if (v.isNotEmpty) {
                    setState(() {
                      _selectedHyperfocuses.add(v);
                      _customHyperfocusCtrl.clear();
                    });
                  }
                },
                icon: const Icon(Icons.add_circle_rounded),
                color: AppTheme.secondary,
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ─── STEP 6: Communication Style ─────────────────────────────────────────
  Widget _buildStep6CommStyle(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: _commStyles.map((style) {
          final isSelected = _selectedCommStyles.contains(
            style['value'] as String,
          );
          return GestureDetector(
            onTap: () {
              setState(() {
                final v = style['value'] as String;
                if (isSelected) {
                  _selectedCommStyles.remove(v);
                } else {
                  _selectedCommStyles.add(v);
                }
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.primary
                    : theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? AppTheme.primary
                      : theme.colorScheme.outlineVariant,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    style['icon'] as IconData,
                    size: 16,
                    color: isSelected
                        ? Colors.white
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    style['label'] as String,
                    style: GoogleFonts.nunitoSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? Colors.white
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── STEP 7: Goals ────────────────────────────────────────────────────────
  Widget _buildStep7Goals(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: _goalOptions.map((goal) {
          final isSelected = _selectedGoals.contains(goal['value'] as String);
          return GestureDetector(
            onTap: () {
              setState(() {
                final v = goal['value'] as String;
                if (isSelected) {
                  _selectedGoals.remove(v);
                } else {
                  _selectedGoals.add(v);
                }
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.secondary
                    : theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? AppTheme.secondary
                      : theme.colorScheme.outlineVariant,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    goal['icon'] as IconData,
                    size: 16,
                    color: isSelected
                        ? Colors.white
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    goal['label'] as String,
                    style: GoogleFonts.nunitoSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? Colors.white
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── STEP 8: Age Verification & Consents ─────────────────────────────────
  Future<void> _pickBirthDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 20, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: DateTime(now.year - 1, now.month, now.day),
      helpText: 'Selecione sua data de nascimento',
      cancelText: 'Cancelar',
      confirmText: 'Confirmar',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(
            context,
          ).colorScheme.copyWith(primary: AppTheme.primary),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      final age =
          now.year -
          picked.year -
          ((now.month < picked.month ||
                  (now.month == picked.month && now.day < picked.day))
              ? 1
              : 0);
      setState(() {
        _birthDate = picked;
        _birthDateText =
            '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
        _isAgeValid = age >= 18;
      });
    }
  }

  Widget _buildStep8Consents(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Medical Disclaimer (Google Play Health Compliance) ─────────────
          const MedicalDisclaimerBannerWidget(),
          const SizedBox(height: 16),

          // ── Date of Birth ──────────────────────────────────────────────
          Text(
            'Data de Nascimento',
            style: GoogleFonts.nunitoSans(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => _pickBirthDate(context),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _birthDate == null
                      ? theme.colorScheme.outlineVariant
                      : _isAgeValid
                      ? AppTheme.primary
                      : AppTheme.error,
                  width: _birthDate != null ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.cake_outlined,
                    size: 20,
                    color: _birthDate == null
                        ? theme.colorScheme.onSurfaceVariant
                        : _isAgeValid
                        ? AppTheme.primary
                        : AppTheme.error,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _birthDateText.isEmpty
                          ? 'Toque para selecionar (DD/MM/AAAA)'
                          : _birthDateText,
                      style: GoogleFonts.nunitoSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _birthDateText.isEmpty
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_birthDate != null && !_isAgeValid) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.error.withAlpha(15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.error.withAlpha(60)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.block_rounded,
                    color: AppTheme.error,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Você precisa ter pelo menos 18 anos para se cadastrar.',
                      style: GoogleFonts.nunitoSans(
                        fontSize: 12,
                        color: AppTheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_birthDate != null && _isAgeValid) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.success.withAlpha(20),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.success.withAlpha(80)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_outline_rounded,
                    color: AppTheme.success,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Idade confirmada ✓',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 12,
                      color: AppTheme.success,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),

          // ── Optional Permissions ───────────────────────────────────────
          _buildSectionLabel(theme, '🔔 Permissões Opcionais'),
          const SizedBox(height: 10),
          _buildConsentTile(
            theme: theme,
            icon: Icons.notifications_outlined,
            title: 'Notificações Push',
            subtitle: 'Para avisos de novas conexões e mensagens. (Opcional)',
            tag: 'Opcional',
            tagColor: AppTheme.primaryLight,
            value: _pushNotificationsEnabled,
            onChanged: (v) => setState(() => _pushNotificationsEnabled = v),
          ),
          const SizedBox(height: 10),
          _buildConsentTile(
            theme: theme,
            icon: Icons.location_on_outlined,
            title: 'Localização Aproximada / Precisa',
            subtitle:
                'Para recomendar pessoas próximas na comunidade. (Opcional)',
            tag: 'Opcional',
            tagColor: AppTheme.primaryLight,
            value: _locationEnabled,
            onChanged: (v) => setState(() => _locationEnabled = v),
          ),
          const SizedBox(height: 10),
          _buildConsentTile(
            theme: theme,
            icon: Icons.camera_alt_outlined,
            title: 'Câmera e Galeria',
            subtitle:
                'Para envio da foto do perfil e foto do pet. (Ao usar o recurso)',
            tag: 'Ao usar',
            tagColor: Colors.orange,
            value: _cameraGalleryEnabled,
            onChanged: _toggleCameraGalleryPermission,
          ),
          const SizedBox(height: 10),
          _buildConsentTile(
            theme: theme,
            icon: Icons.mic_outlined,
            title: 'Microfone e Áudio',
            subtitle: 'Para envio de notas de voz. (Ao usar o recurso)',
            tag: 'Ao usar',
            tagColor: Colors.orange,
            value: _microphoneEnabled,
            onChanged: (v) => setState(() => _microphoneEnabled = v),
          ),
          const SizedBox(height: 24),

          // ── Mandatory Consents ─────────────────────────────────────────
          _buildSectionLabel(theme, '🔒 Consentimentos Obrigatórios'),
          const SizedBox(height: 10),
          _buildConsentTile(
            theme: theme,
            icon: Icons.psychology_outlined,
            title: 'Dados Sensíveis e Perfil Sensorial',
            subtitle:
                'Autorizo o processamento de meus dados de perfil sensorial, valores e preferências para personalização do aplicativo. (LGPD / Google Play)',
            tag: 'Obrigatório',
            tagColor: AppTheme.error,
            value: _sensitiveDataConsent,
            onChanged: (v) {
              setState(() => _sensitiveDataConsent = v);
            },
            isRequired: true,
          ),
          const SizedBox(height: 10),
          _buildTermsConsentTile(theme),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(ThemeData theme, String label) {
    return Text(
      label,
      style: GoogleFonts.nunitoSans(
        fontSize: 14,
        fontWeight: FontWeight.w800,
        color: theme.colorScheme.onSurface,
      ),
    );
  }

  Widget _buildConsentTile({
    required ThemeData theme,
    required IconData icon,
    required String title,
    required String subtitle,
    required String tag,
    required Color tagColor,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool isRequired = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: (isRequired && value)
              ? AppTheme.primary
              : theme.colorScheme.outlineVariant,
          width: (isRequired && value) ? 2 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: tagColor.withAlpha(25),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: tagColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: GoogleFonts.nunitoSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: tagColor.withAlpha(25),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        tag,
                        style: GoogleFonts.nunitoSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: tagColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: GoogleFonts.nunitoSans(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppTheme.primary,
            activeTrackColor: AppTheme.primary.withAlpha(80),
          ),
        ],
      ),
    );
  }

  Widget _buildTermsConsentTile(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _termsAccepted
              ? AppTheme.primary
              : theme.colorScheme.outlineVariant,
          width: _termsAccepted ? 2 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => setState(() => _termsAccepted = !_termsAccepted),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: _termsAccepted ? AppTheme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _termsAccepted
                      ? AppTheme.primary
                      : theme.colorScheme.outlineVariant,
                  width: 2,
                ),
              ),
              child: _termsAccepted
                  ? const Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: Colors.white,
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Termos de Uso e Política de Privacidade',
                        style: GoogleFonts.nunitoSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.error.withAlpha(25),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Obrigatório',
                        style: GoogleFonts.nunitoSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                RichText(
                  text: TextSpan(
                    style: GoogleFonts.nunitoSans(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    children: [
                      const TextSpan(text: 'Li e aceito os '),
                      WidgetSpan(
                        child: GestureDetector(
                          onTap: () {
                            // TODO: open Terms of Use URL
                          },
                          child: Text(
                            'Termos de Uso',
                            style: GoogleFonts.nunitoSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primary,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ),
                      const TextSpan(text: ' e a '),
                      WidgetSpan(
                        child: GestureDetector(
                          onTap: () {
                            // TODO: open Privacy Policy URL
                          },
                          child: Text(
                            'Política de Privacidade',
                            style: GoogleFonts.nunitoSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primary,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ),
                      const TextSpan(
                        text:
                            ' da SintonIA, incluindo o tratamento de dados conforme a LGPD.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required ThemeData theme,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      onChanged: onChanged,
      style: theme.textTheme.bodyMedium,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        filled: true,
        fillColor: theme.colorScheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppTheme.primary, width: 2),
        ),
      ),
    );
  }

  /// Multi-select chip group. Calls [onToggle] with the tapped option value.
  Widget _buildMultiSelectChips({
    required ThemeData theme,
    required List<String> options,
    required List<String> selected,
    required ValueChanged<String> onToggle,
    required Color color,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((o) {
        final isSelected = selected.contains(o);
        return GestureDetector(
          onTap: () => onToggle(o),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: isSelected ? color : theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? color : theme.colorScheme.outlineVariant,
              ),
            ),
            child: Text(
              o,
              style: GoogleFonts.nunitoSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : theme.colorScheme.onSurface,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  /// Single-select chip group (kept for diet step).
  Widget _buildSingleSelectChips({
    required ThemeData theme,
    required List<String> options,
    required String selected,
    required ValueChanged<String> onSelect,
    required Color color,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((o) {
        final isSelected = selected == o;
        return GestureDetector(
          onTap: () => onSelect(isSelected ? '' : o),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: isSelected ? color : theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? color : theme.colorScheme.outlineVariant,
              ),
            ),
            child: Text(
              o,
              style: GoogleFonts.nunitoSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : theme.colorScheme.onSurface,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildToleranceToggle(
    ThemeData theme, {
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(
            value ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: value ? AppTheme.success : AppTheme.error,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.nunitoSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppTheme.primary,
          ),
        ],
      ),
    );
  }
}
