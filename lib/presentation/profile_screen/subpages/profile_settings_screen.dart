import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/app_export.dart';
import '../../../services/supabase_service.dart';
import '../../../services/theme_notifier.dart';
import '../../../services/user_settings_service.dart';
import './blocked_users_screen.dart';
import './security_settings_screen.dart';

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  bool _isLoading = true;
  bool _isDeletingAccount = false;

  // Settings state
  bool _profilePublic = true;
  bool _showHyperfocuses = true;
  bool _showInterests = true;
  bool _showPets = true;
  bool _allowMessages = true;
  bool _notifMessages = true;
  bool _notifFriends = true;
  bool _notifFeed = true;
  bool _notifAI = false;
  bool _reduceAnimations = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await UserSettingsService.instance.fetchSettings();
    if (!mounted) return;
    setState(() {
      _profilePublic = settings['is_public_profile'] ?? true;
      _showHyperfocuses = settings['show_hyperfocus'] ?? true;
      _showInterests = settings['show_interests'] ?? true;
      _showPets = settings['show_pets'] ?? true;
      _allowMessages = settings['allow_direct_messages'] ?? true;
      _notifMessages = settings['notify_messages'] ?? true;
      _notifFriends = settings['notify_friendships'] ?? true;
      _notifFeed = settings['notify_feed'] ?? true;
      _notifAI = settings['notify_ai_suggestions'] ?? false;
      _reduceAnimations = settings['reduce_animations'] ?? false;
      _isLoading = false;
    });
  }

  Future<void> _updateSetting(String field, bool value) async {
    await UserSettingsService.instance.updateSetting(field, value);
  }

  // ── Account deletion ──────────────────────────────────────────────────────

  Future<void> _showDeleteAccountDialog() async {
    final TextEditingController confirmController = TextEditingController();
    bool canDelete = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20.0),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withAlpha(20),
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                    child: Icon(
                      Icons.warning_amber_rounded,
                      color: AppTheme.error,
                      size: 22,
                    ),
                  ),
                  SizedBox(width: 2.w),
                  Expanded(
                    child: Text(
                      'Excluir conta',
                      style: TextStyle(
                        color: AppTheme.error,
                        fontWeight: FontWeight.w700,
                        fontSize: 15.sp,
                      ),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: EdgeInsets.all(3.w),
                      decoration: BoxDecoration(
                        color: AppTheme.error.withAlpha(12),
                        borderRadius: BorderRadius.circular(12.0),
                        border: Border.all(color: AppTheme.error.withAlpha(60)),
                      ),
                      child: Text(
                        '⚠️ Esta ação é IRREVERSÍVEL. Todos os seus dados serão permanentemente apagados:',
                        style: TextStyle(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.error,
                        ),
                      ),
                    ),
                    SizedBox(height: 1.5.h),
                    _DeleteDataItem(
                      icon: Icons.person_outline_rounded,
                      text: 'Perfil e dados pessoais',
                    ),
                    _DeleteDataItem(
                      icon: Icons.psychology_outlined,
                      text: 'Perfil sensorial e preferências',
                    ),
                    _DeleteDataItem(
                      icon: Icons.pets_rounded,
                      text: 'Pets e fotos dos pets',
                    ),
                    _DeleteDataItem(
                      icon: Icons.photo_library_outlined,
                      text: 'Fotos e arquivos no Storage',
                    ),
                    _DeleteDataItem(
                      icon: Icons.chat_bubble_outline_rounded,
                      text: 'Mensagens e histórico de chat',
                    ),
                    _DeleteDataItem(
                      icon: Icons.feed_outlined,
                      text: 'Publicações e interações',
                    ),
                    _DeleteDataItem(
                      icon: Icons.manage_accounts_outlined,
                      text: 'Conta de autenticação',
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      'Para confirmar, digite EXCLUIR abaixo:',
                      style: TextStyle(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 1.h),
                    TextField(
                      controller: confirmController,
                      autofocus: true,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        hintText: 'Digite EXCLUIR',
                        filled: true,
                        fillColor: Theme.of(
                          ctx,
                        ).colorScheme.surfaceContainerHighest,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.0),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.0),
                          borderSide: BorderSide(
                            color: AppTheme.error,
                            width: 1.5,
                          ),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 3.w,
                          vertical: 1.2.h,
                        ),
                      ),
                      onChanged: (val) {
                        setDialogState(() {
                          canDelete = val.trim() == 'EXCLUIR';
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    confirmController.dispose();
                    Navigator.pop(dialogContext);
                  },
                  child: Text(
                    'Cancelar',
                    style: TextStyle(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                FilledButton(
                  onPressed: canDelete
                      ? () async {
                          confirmController.dispose();
                          Navigator.pop(dialogContext);
                          await _performAccountDeletion();
                        }
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.error,
                    disabledBackgroundColor: AppTheme.error.withAlpha(60),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                  ),
                  child: const Text(
                    'Excluir permanentemente',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _performAccountDeletion() async {
    if (!mounted) return;
    setState(() => _isDeletingAccount = true);
    try {
      await SupabaseService.instance.client.rpc('delete_user_account');
      await SupabaseService.instance.signOut();
      if (mounted) {
        context.go('/login');
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  'Sua conta e todos os dados foram excluídos permanentemente.',
                ),
                backgroundColor: AppTheme.primary,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isDeletingAccount = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao excluir conta. Tente novamente. ($e)'),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.0),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.error.withAlpha(20),
                borderRadius: BorderRadius.circular(10.0),
              ),
              child: Icon(
                Icons.logout_rounded,
                color: AppTheme.error,
                size: 20,
              ),
            ),
            SizedBox(width: 2.w),
            const Expanded(child: Text('Sair da conta?')),
          ],
        ),
        content: const Text('Deseja realmente sair do SintonIA?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext, rootNavigator: true).pop();
            },
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(dialogContext, rootNavigator: true).pop();
              try {
                await Supabase.instance.client.auth.signOut();
                if (context.mounted) {
                  context.go('/login');
                }
              } catch (e) {
                debugPrint('Erro ao deslogar: $e');
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Erro ao sair da conta: $e'),
                      backgroundColor: AppTheme.error,
                    ),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.error,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.0),
              ),
            ),
            child: const Text('Sair', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = theme.scaffoldBackgroundColor;
    final isDark = ThemeNotifier.instance.isDark;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'Configurações',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
        ),
      ),
      body: _isDeletingAccount
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppTheme.error),
                  SizedBox(height: 2.h),
                  Text(
                    'Excluindo sua conta e dados...',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppTheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 0.8.h),
                  Text(
                    'Por favor, aguarde.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          : _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.symmetric(
                horizontal: 4.w,
                vertical: 1.h,
              ).copyWith(bottom: 10.h),
              children: [
                // ── Aparência ─────────────────────────────────────────
                _SectionHeader('Aparência'),
                SizedBox(height: 0.8.h),
                _SettingsTile(
                  icon: isDark
                      ? Icons.dark_mode_rounded
                      : Icons.light_mode_rounded,
                  title: 'Modo escuro',
                  subtitle: isDark
                      ? 'Tema escuro ativado'
                      : 'Tema claro ativado',
                  value: isDark,
                  onChanged: (v) async {
                    await ThemeNotifier.instance.setDark(v);
                    await _updateSetting('dark_mode', v);
                    if (mounted) setState(() {});
                  },
                ),

                // ── Notificações ──────────────────────────────────────
                SizedBox(height: 1.5.h),
                _SectionHeader('Notificações'),
                SizedBox(height: 0.8.h),
                _SettingsTile(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: 'Mensagens',
                  subtitle: 'Notificações de novas mensagens',
                  value: _notifMessages,
                  onChanged: (v) {
                    setState(() => _notifMessages = v);
                    _updateSetting('notify_messages', v);
                  },
                ),
                _SettingsTile(
                  icon: Icons.people_outline_rounded,
                  title: 'Amizades',
                  subtitle: 'Solicitações e conexões',
                  value: _notifFriends,
                  onChanged: (v) {
                    setState(() => _notifFriends = v);
                    _updateSetting('notify_friendships', v);
                  },
                ),
                _SettingsTile(
                  icon: Icons.feed_outlined,
                  title: 'Feed',
                  subtitle: 'Curtidas, comentários e compartilhamentos',
                  value: _notifFeed,
                  onChanged: (v) {
                    setState(() => _notifFeed = v);
                    _updateSetting('notify_feed', v);
                  },
                ),
                _SettingsTile(
                  icon: Icons.auto_awesome_outlined,
                  title: 'SintonIA',
                  subtitle: 'Sugestões e lembretes da IA',
                  value: _notifAI,
                  onChanged: (v) {
                    setState(() => _notifAI = v);
                    _updateSetting('notify_ai_suggestions', v);
                  },
                ),

                // ── Privacidade ───────────────────────────────────────
                SizedBox(height: 1.5.h),
                _SectionHeader('Privacidade'),
                SizedBox(height: 0.8.h),
                _SettingsTile(
                  icon: Icons.lock_outline_rounded,
                  title: 'Perfil público',
                  subtitle: 'Qualquer pessoa pode ver seu perfil',
                  value: _profilePublic,
                  onChanged: (v) {
                    setState(() => _profilePublic = v);
                    _updateSetting('is_public_profile', v);
                  },
                ),
                _SettingsTile(
                  icon: Icons.psychology_outlined,
                  title: 'Mostrar hiperfocos',
                  subtitle: 'Exibir seus hiperfocos no perfil',
                  value: _showHyperfocuses,
                  onChanged: (v) {
                    setState(() => _showHyperfocuses = v);
                    _updateSetting('show_hyperfocus', v);
                  },
                ),
                _SettingsTile(
                  icon: Icons.interests_outlined,
                  title: 'Mostrar interesses',
                  subtitle: 'Exibir seus interesses no perfil',
                  value: _showInterests,
                  onChanged: (v) {
                    setState(() => _showInterests = v);
                    _updateSetting('show_interests', v);
                  },
                ),
                _SettingsTile(
                  icon: Icons.pets_rounded,
                  title: 'Mostrar pets',
                  subtitle: 'Exibir seus pets no perfil',
                  value: _showPets,
                  onChanged: (v) {
                    setState(() => _showPets = v);
                    _updateSetting('show_pets', v);
                  },
                ),
                _SettingsTile(
                  icon: Icons.message_outlined,
                  title: 'Permitir mensagens',
                  subtitle: 'Receber mensagens de qualquer pessoa',
                  value: _allowMessages,
                  onChanged: (v) {
                    setState(() => _allowMessages = v);
                    _updateSetting('allow_direct_messages', v);
                  },
                ),

                // ── Acessibilidade ────────────────────────────────────
                SizedBox(height: 1.5.h),
                _SectionHeader('Acessibilidade'),
                SizedBox(height: 0.8.h),
                _SettingsTile(
                  icon: Icons.animation_rounded,
                  title: 'Reduzir animações',
                  subtitle: 'Minimizar movimentos na interface',
                  value: _reduceAnimations,
                  onChanged: (v) {
                    setState(() => _reduceAnimations = v);
                    _updateSetting('reduce_animations', v);
                  },
                ),

                // ── Conta ─────────────────────────────────────────────
                SizedBox(height: 1.5.h),
                _SectionHeader('Conta'),
                SizedBox(height: 0.8.h),
                _ActionTile(
                  icon: Icons.security_outlined,
                  title: 'Segurança',
                  subtitle: 'Senha e autenticação',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SecuritySettingsScreen(),
                    ),
                  ),
                ),
                _ActionTile(
                  icon: Icons.block_rounded,
                  title: 'Usuários bloqueados',
                  subtitle: 'Gerenciar bloqueios',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const BlockedUsersScreen(),
                    ),
                  ),
                ),
                _ActionTile(
                  icon: Icons.logout_rounded,
                  title: 'Sair da conta',
                  subtitle: 'Encerrar sessão',
                  isDestructive: true,
                  onTap: _showLogoutDialog,
                ),

                // ── Privacidade e Conta (LGPD) ────────────────────────
                SizedBox(height: 1.5.h),
                _SectionHeader('Privacidade e Conta'),
                SizedBox(height: 0.8.h),
                Container(
                  padding: EdgeInsets.all(3.w),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withAlpha(10),
                    borderRadius: BorderRadius.circular(16.0),
                    border: Border.all(
                      color: AppTheme.error.withAlpha(80),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.shield_outlined,
                            color: AppTheme.error,
                            size: 18,
                          ),
                          SizedBox(width: 2.w),
                          Text(
                            'Direito ao Esquecimento (LGPD)',
                            style: TextStyle(
                              color: AppTheme.error,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.sp,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 1.h),
                      Text(
                        'Você tem o direito de solicitar a exclusão permanente de todos os seus dados pessoais do SintonIA, conforme a Lei Geral de Proteção de Dados (LGPD - Lei nº 13.709/2018).',
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                      SizedBox(height: 1.5.h),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _showDeleteAccountDialog,
                          icon: const Icon(
                            Icons.delete_forever_rounded,
                            size: 18,
                            color: Colors.white,
                          ),
                          label: const Text(
                            'Excluir minha conta e dados',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.error,
                            minimumSize: const Size(double.infinity, 48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12.0),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Isenção de Responsabilidade Médica ───────────────
                SizedBox(height: 1.5.h),
                _SectionHeader('Isenção de Responsabilidade Médica'),
                SizedBox(height: 0.8.h),
                Container(
                  padding: EdgeInsets.all(3.w),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3CD),
                    borderRadius: BorderRadius.circular(16.0),
                    border: Border.all(
                      color: const Color(0xFFFFD700),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF856404).withAlpha(20),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.health_and_safety_outlined,
                              color: Color(0xFF856404),
                              size: 18,
                            ),
                          ),
                          SizedBox(width: 2.w),
                          Expanded(
                            child: Text(
                              '⚠️ Aviso Médico Importante',
                              style: TextStyle(
                                color: const Color(0xFF856404),
                                fontWeight: FontWeight.w800,
                                fontSize: 13.sp,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 1.h),
                      Text(
                        'O SintonIA é uma rede social de acolhimento e suporte comunitário. '
                        'Nenhum recurso do aplicativo, incluindo a assistente virtual (IA), '
                        'substitui consultas, diagnósticos ou tratamentos médicos, '
                        'psicológicos ou psiquiátricos profissionais.',
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: const Color(0xFF856404),
                          height: 1.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 1.h),
                      Text(
                        'Em caso de crise de saúde mental, busque ajuda imediatamente:',
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: const Color(0xFF856404),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 0.8.h),
                      _EmergencyContactTile(
                        icon: Icons.phone_rounded,
                        label: 'CVV — Centro de Valorização da Vida',
                        contact: '188',
                        detail: '24h por dia, gratuito',
                      ),
                      SizedBox(height: 0.5.h),
                      _EmergencyContactTile(
                        icon: Icons.local_hospital_outlined,
                        label: 'SAMU — Serviço de Atendimento Móvel',
                        contact: '192',
                        detail: 'Emergências médicas',
                      ),
                      SizedBox(height: 0.5.h),
                      _EmergencyContactTile(
                        icon: Icons.emergency_outlined,
                        label: 'Bombeiros / Emergência Geral',
                        contact: '193',
                        detail: 'Situações de risco de vida',
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 5.h),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper widget for delete dialog data items
// ─────────────────────────────────────────────────────────────────────────────
class _DeleteDataItem extends StatelessWidget {
  final IconData icon;
  final String text;
  const _DeleteDataItem({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 0.6.h),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppTheme.error.withAlpha(180)),
          SizedBox(width: 2.w),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11.sp,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Emergency contact tile for medical disclaimer section
// ─────────────────────────────────────────────────────────────────────────────
class _EmergencyContactTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String contact;
  final String detail;

  const _EmergencyContactTile({
    required this.icon,
    required this.label,
    required this.contact,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 0.4.h),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF856404).withAlpha(12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF856404)),
          SizedBox(width: 2.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF856404),
                  ),
                ),
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: 10.sp,
                    color: const Color(0xFF856404).withAlpha(180),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF856404),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              contact,
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section header
// ─────────────────────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 1.w),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: AppTheme.primary,
          fontWeight: FontWeight.w700,
          fontSize: 13.sp,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Toggle tile
// ─────────────────────────────────────────────────────────────────────────────
class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final void Function(bool) onChanged;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: EdgeInsets.only(bottom: 1.h),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withAlpha(120),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 3.w, vertical: 0.5.h),
        child: Row(
          children: [
            Container(
              width: 9.w,
              height: 9.w,
              decoration: BoxDecoration(
                color: AppTheme.primary.withAlpha(20),
                borderRadius: BorderRadius.circular(10.0),
              ),
              child: Icon(icon, color: AppTheme.primary, size: 18),
            ),
            SizedBox(width: 3.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.sp,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 0.2.h),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11.sp,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: Colors.white,
              activeTrackColor: AppTheme.primary,
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: theme.colorScheme.outlineVariant,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Action tile (with arrow)
// ─────────────────────────────────────────────────────────────────────────────
class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isDestructive;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isDestructive ? AppTheme.error : AppTheme.primary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(bottom: 1.h),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16.0),
          border: Border.all(
            color: isDestructive
                ? AppTheme.error.withAlpha(60)
                : theme.colorScheme.outlineVariant.withAlpha(120),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(8),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 3.w, vertical: 1.5.h),
          child: Row(
            children: [
              Container(
                width: 9.w,
                height: 9.w,
                decoration: BoxDecoration(
                  color: color.withAlpha(20),
                  borderRadius: BorderRadius.circular(10.0),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              SizedBox(width: 3.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 13.sp,
                        color: isDestructive ? AppTheme.error : null,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 0.2.h),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11.sp,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
