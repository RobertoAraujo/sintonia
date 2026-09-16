import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../routes/app_routes.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';

/// First-time user setup flow shown after login for users who haven't
/// configured their neurodivergence type, hyperfocus tags, and communication style.
class FirstTimeSetupScreen extends StatefulWidget {
  const FirstTimeSetupScreen({super.key});

  @override
  State<FirstTimeSetupScreen> createState() => _FirstTimeSetupScreenState();
}

class _FirstTimeSetupScreenState extends State<FirstTimeSetupScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  static const int _totalSteps = 3;
  bool _isSaving = false;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  // Step 1 — Neurodivergence type
  final List<Map<String, dynamic>> _neurotypes = [
    {'label': 'TDAH', 'emoji': '⚡', 'value': 'TDAH'},
    {'label': 'Autismo (TEA)', 'emoji': '🌈', 'value': 'TEA'},
    {'label': 'Dislexia', 'emoji': '📖', 'value': 'Dislexia'},
    {'label': 'Altas Habilidades', 'emoji': '🌟', 'value': 'Superdotacao'},
    {'label': 'Discalculia', 'emoji': '🔢', 'value': 'Discalculia'},
    {'label': 'Asperger', 'emoji': '🧩', 'value': 'TEA'},
    {'label': 'TOC', 'emoji': '🔄', 'value': 'TOC'},
    {'label': 'Ansiedade', 'emoji': '🌊', 'value': 'Ansiedade'},
    {'label': 'Neurotípico', 'emoji': '🤝', 'value': 'Neurotipico'},
    {'label': 'Em diagnóstico', 'emoji': '🔍', 'value': 'EmDiagnostico'},
    {'label': 'Prefiro não dizer', 'emoji': '💜', 'value': 'Outro'},
  ];
  String? _selectedNeurotype;

  // Step 2 — Hyperfocus tags
  final List<Map<String, dynamic>> _hyperfocusOptions = [
    {'label': 'Programação', 'emoji': '💻'},
    {'label': 'Jogos', 'emoji': '🎮'},
    {'label': 'Anime/Mangá', 'emoji': '🎌'},
    {'label': 'Música', 'emoji': '🎵'},
    {'label': 'Arte/Desenho', 'emoji': '🎨'},
    {'label': 'Escrita', 'emoji': '✍️'},
    {'label': 'Ciências', 'emoji': '🔬'},
    {'label': 'Matemática', 'emoji': '📐'},
    {'label': 'Astronomia', 'emoji': '🌌'},
    {'label': 'Biologia', 'emoji': '🌿'},
    {'label': 'História', 'emoji': '📜'},
    {'label': 'Filosofia', 'emoji': '🤔'},
    {'label': 'Filmes/Séries', 'emoji': '🎬'},
    {'label': 'Fotografia', 'emoji': '📷'},
    {'label': 'Culinária', 'emoji': '🍳'},
    {'label': 'Esportes', 'emoji': '⚽'},
    {'label': 'Leitura', 'emoji': '📚'},
    {'label': 'Tecnologia', 'emoji': '🤖'},
    {'label': 'Moda', 'emoji': '👗'},
    {'label': 'Idiomas', 'emoji': '🗣️'},
    {'label': 'RPG/D&D', 'emoji': '🎲'},
    {'label': 'Animais/Pets', 'emoji': '🐾'},
    {'label': 'K-Pop', 'emoji': '🎤'},
    {'label': 'True Crime', 'emoji': '🔎'},
  ];
  final Set<String> _selectedHyperfocuses = {};

  // Step 3 — Communication style
  final List<Map<String, dynamic>> _commStyles = [
    {'label': 'Mensagens curtas', 'emoji': '💬', 'value': 'shortText'},
    {'label': 'Mensagens longas', 'emoji': '📝', 'value': 'longText'},
    {'label': 'Direto ao ponto', 'emoji': '🎯', 'value': 'directMessages'},
    {'label': 'Com emojis 🎉', 'emoji': '😊', 'value': 'emojiHeavy'},
    {'label': 'Tom informal', 'emoji': '🤗', 'value': 'informalTone'},
    {'label': 'Tom formal', 'emoji': '💼', 'value': 'formalTone'},
    {'label': 'Assíncrono', 'emoji': '⏰', 'value': 'asyncMessages'},
    {'label': 'Áudio', 'emoji': '🎙️', 'value': 'audio'},
  ];
  final Set<String> _selectedCommStyles = {};

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep < _totalSteps - 1) {
      setState(() => _currentStep++);
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    } else {
      _saveAndContinue();
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
      _pageController.previousPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _saveAndContinue() async {
    setState(() => _isSaving = true);
    try {
      final uid = SupabaseService.instance.currentUserId;
      if (uid != null) {
        await SupabaseService.instance.client
            .from('user_profiles')
            .update({
              if (_selectedNeurotype != null)
                'neurodiv_type': _selectedNeurotype,
              'hyperfocus_tags': _selectedHyperfocuses.toList(),
              'comm_style': _selectedCommStyles.toList(),
              'onboarding_completed': true,
            })
            .eq('id', uid);
      }
    } catch (e) {
      debugPrint('FirstTimeSetup save error: $e');
    }
    if (!mounted) return;
    setState(() => _isSaving = false);
    context.go(AppRoutes.homeFeedScreen);
  }

  void _skipSetup() {
    // Mark as completed even if skipped so we don't show again
    final uid = SupabaseService.instance.currentUserId;
    if (uid != null) {
      SupabaseService.instance.client
          .from('user_profiles')
          .update({'onboarding_completed': true})
          .eq('id', uid)
          .then((_) {})
          .catchError((_) {});
    }
    context.go(AppRoutes.homeFeedScreen);
  }

  bool get _canProceed {
    switch (_currentStep) {
      case 0:
        return _selectedNeurotype != null;
      case 1:
        return _selectedHyperfocuses.isNotEmpty;
      case 2:
        return _selectedCommStyles.isNotEmpty;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Column(
            children: [
              _buildHeader(theme),
              _buildProgressBar(theme),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildStep1(theme),
                    _buildStep2(theme),
                    _buildStep3(theme),
                  ],
                ),
              ),
              _buildBottomBar(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.secondary, AppTheme.primary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
              child: Text('✨', style: TextStyle(fontSize: 22)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bem-vindo à SintonIA! 💜',
                  style: GoogleFonts.nunitoSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primary,
                  ),
                ),
                Text(
                  'Vamos personalizar sua experiência',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _skipSetup,
            child: Text(
              'Pular',
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: List.generate(_totalSteps, (i) {
          final isActive = i <= _currentStep;
          return Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 4,
              margin: EdgeInsets.only(right: i < _totalSteps - 1 ? 6 : 0),
              decoration: BoxDecoration(
                color: isActive
                    ? AppTheme.primary
                    : theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStep1(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Como você se identifica? 🧠',
            style: GoogleFonts.nunitoSans(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Isso nos ajuda a personalizar sua experiência e conectar você com pessoas que entendem sua jornada. 💜',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _neurotypes.map((n) {
              final isSelected = _selectedNeurotype == n['value'];
              return GestureDetector(
                onTap: () => setState(() => _selectedNeurotype = n['value']),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primary.withAlpha(20)
                        : theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.primary
                          : theme.colorScheme.outlineVariant,
                      width: isSelected ? 2 : 1,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: AppTheme.primary.withAlpha(30),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        n['emoji'] as String,
                        style: const TextStyle(fontSize: 18),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        n['label'] as String,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: isSelected
                              ? AppTheme.primary
                              : theme.colorScheme.onSurface,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Seus hiperfocos ✨',
            style: GoogleFonts.nunitoSans(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Selecione os temas que te fazem entrar em modo hiperfoco! Isso vai nos ajudar a encontrar pessoas com os mesmos interesses. 🎯',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${_selectedHyperfocuses.length} selecionado${_selectedHyperfocuses.length != 1 ? 's' : ''}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppTheme.secondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _hyperfocusOptions.map((h) {
              final label = h['label'] as String;
              final isSelected = _selectedHyperfocuses.contains(label);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _selectedHyperfocuses.remove(label);
                    } else {
                      _selectedHyperfocuses.add(label);
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.secondary.withAlpha(20)
                        : theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.secondary
                          : theme.colorScheme.outlineVariant,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        h['emoji'] as String,
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: isSelected
                              ? AppTheme.secondary
                              : theme.colorScheme.onSurface,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildStep3(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Como você prefere se comunicar? 💬',
            style: GoogleFonts.nunitoSans(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Isso nos ajuda a calcular sua compatibilidade com outras pessoas e personalizar como a SintonIA fala com você. 🤗',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 2.4,
            children: _commStyles.map((s) {
              final value = s['value'] as String;
              final isSelected = _selectedCommStyles.contains(value);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _selectedCommStyles.remove(value);
                    } else {
                      _selectedCommStyles.add(value);
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primary.withAlpha(20)
                        : theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.primary
                          : theme.colorScheme.outlineVariant,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        s['emoji'] as String,
                        style: const TextStyle(fontSize: 18),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          s['label'] as String,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: isSelected
                                ? AppTheme.primary
                                : theme.colorScheme.onSurface,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.secondary.withAlpha(15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.secondary.withAlpha(40)),
            ),
            child: Row(
              children: [
                const Text('🎯', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Suas escolhas alimentam o motor de compatibilidade da SintonIA para conectar você com pessoas que realmente combinam!',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppTheme.secondary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(ThemeData theme) {
    final isLastStep = _currentStep == _totalSteps - 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant, width: 1),
        ),
      ),
      child: Row(
        children: [
          if (_currentStep > 0)
            OutlinedButton(
              onPressed: _prevStep,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              child: const Icon(Icons.arrow_back_rounded),
            ),
          if (_currentStep > 0) const SizedBox(width: 12),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 52,
              child: ElevatedButton(
                onPressed: (_canProceed && !_isSaving) ? _nextStep : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  disabledBackgroundColor: theme.colorScheme.outlineVariant
                      .withAlpha(80),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        isLastStep ? 'Entrar na SintonIA 🚀' : 'Continuar →',
                        style: GoogleFonts.nunitoSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
