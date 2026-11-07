import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/app_export.dart';
import '../../../services/supabase_service.dart';
import '../../../theme/app_theme.dart';

class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  // Change password
  final _currentPasswordCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  bool _showCurrent = false;
  bool _showNew = false;
  bool _showConfirm = false;
  bool _isChangingPassword = false;

  // 2FA toggle (stored in user metadata)
  bool _twoFAEnabled = false;
  bool _isTogglingTwoFA = false;

  // Active sessions
  bool _isTerminatingSessions = false;

  @override
  void initState() {
    super.initState();
    _loadTwoFASetting();
  }

  void _loadTwoFASetting() {
    final user = SupabaseService.instance.currentUser;
    if (user != null) {
      final enabled = user.userMetadata?['two_fa_enabled'] == true;
      setState(() => _twoFAEnabled = enabled);
    }
  }

  @override
  void dispose() {
    _currentPasswordCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    final newPass = _newPasswordCtrl.text.trim();
    final confirmPass = _confirmPasswordCtrl.text.trim();

    if (newPass.isEmpty || confirmPass.isEmpty) {
      _showSnack('Preencha todos os campos de senha.', isError: true);
      return;
    }
    if (newPass.length < 6) {
      _showSnack(
        'A nova senha deve ter pelo menos 6 caracteres.',
        isError: true,
      );
      return;
    }
    if (newPass != confirmPass) {
      _showSnack('As senhas não coincidem.', isError: true);
      return;
    }

    setState(() => _isChangingPassword = true);
    try {
      await SupabaseService.instance.client.auth.updateUser(
        UserAttributes(password: newPass),
      );
      _currentPasswordCtrl.clear();
      _newPasswordCtrl.clear();
      _confirmPasswordCtrl.clear();
      _showSnack('Senha alterada com sucesso!');
    } catch (e) {
      _showSnack('Erro ao alterar senha: ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _isChangingPassword = false);
    }
  }

  Future<void> _toggleTwoFA(bool value) async {
    setState(() => _isTogglingTwoFA = true);
    try {
      // Store 2FA preference in user metadata
      await SupabaseService.instance.client.auth.updateUser(
        UserAttributes(data: {'two_fa_enabled': value}),
      );
      setState(() => _twoFAEnabled = value);
      _showSnack(
        value
            ? 'Verificação em duas etapas ativada.'
            : 'Verificação em duas etapas desativada.',
      );
    } catch (e) {
      _showSnack('Erro ao alterar 2FA: ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _isTogglingTwoFA = false);
    }
  }

  Future<void> _terminateOtherSessions() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF18181B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.0),
        ),
        title: const Text(
          'Encerrar outras sessões?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Todos os outros dispositivos serão desconectados. Você permanecerá conectado neste dispositivo.',
          style: TextStyle(color: Color(0xFFA1A1AA)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Color(0xFF00D2FF)),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFB91C1C),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Encerrar',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isTerminatingSessions = true);
    try {
      // Sign out from all other sessions except current
      await SupabaseService.instance.client.auth.signOut(
        scope: SignOutScope.others,
      );
      _showSnack('Outras sessões encerradas com sucesso!');
    } catch (e) {
      _showSnack('Erro ao encerrar sessões: ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _isTerminatingSessions = false);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppTheme.error : AppTheme.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = theme.scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'Segurança',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.symmetric(
          horizontal: 4.w,
          vertical: 1.h,
        ).copyWith(bottom: 10.h),
        children: [
          // ── Alterar Senha ─────────────────────────────────────────────
          _buildSectionHeader(context, 'Alterar Senha'),
          SizedBox(height: 1.h),
          _buildCard(
            context,
            child: Column(
              children: [
                _buildPasswordField(
                  context,
                  controller: _currentPasswordCtrl,
                  label: 'Senha Atual',
                  show: _showCurrent,
                  onToggle: () => setState(() => _showCurrent = !_showCurrent),
                ),
                SizedBox(height: 1.5.h),
                _buildPasswordField(
                  context,
                  controller: _newPasswordCtrl,
                  label: 'Nova Senha',
                  show: _showNew,
                  onToggle: () => setState(() => _showNew = !_showNew),
                ),
                SizedBox(height: 1.5.h),
                _buildPasswordField(
                  context,
                  controller: _confirmPasswordCtrl,
                  label: 'Confirmar Nova Senha',
                  show: _showConfirm,
                  onToggle: () => setState(() => _showConfirm = !_showConfirm),
                ),
                SizedBox(height: 2.h),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isChangingPassword ? null : _changePassword,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                    ),
                    child: _isChangingPassword
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Alterar Senha',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),

          // ── Autenticação em Duas Etapas ───────────────────────────────
          SizedBox(height: 2.h),
          _buildSectionHeader(context, 'Autenticação em Duas Etapas'),
          SizedBox(height: 1.h),
          _buildCard(
            context,
            child: Row(
              children: [
                Container(
                  width: 9.w,
                  height: 9.w,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withAlpha(20),
                    borderRadius: BorderRadius.circular(10.0),
                  ),
                  child: Icon(
                    Icons.verified_user_outlined,
                    color: AppTheme.primary,
                    size: 18,
                  ),
                ),
                SizedBox(width: 3.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Verificação em duas etapas',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 13.sp,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 0.2.h),
                      Text(
                        _twoFAEnabled
                            ? 'Ativada — maior segurança'
                            : 'Desativada',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 11.sp,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                _isTogglingTwoFA
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Switch(
                        value: _twoFAEnabled,
                        onChanged: _toggleTwoFA,
                        activeThumbColor: Colors.white,
                        activeTrackColor: AppTheme.primary,
                        inactiveThumbColor: Colors.white,
                        inactiveTrackColor: theme.colorScheme.outlineVariant,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
              ],
            ),
          ),

          // ── Sessões Ativas ────────────────────────────────────────────
          SizedBox(height: 2.h),
          _buildSectionHeader(context, 'Sessões Ativas'),
          SizedBox(height: 1.h),
          _buildCard(
            context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 9.w,
                      height: 9.w,
                      decoration: BoxDecoration(
                        color: Colors.green.withAlpha(30),
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                      child: const Icon(
                        Icons.smartphone_rounded,
                        color: Colors.green,
                        size: 18,
                      ),
                    ),
                    SizedBox(width: 3.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Este dispositivo',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.sp,
                            ),
                          ),
                          Text(
                            'Sessão atual — ativa agora',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.green,
                              fontSize: 11.sp,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 2.w,
                        vertical: 0.4.h,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.withAlpha(30),
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      child: Text(
                        'Ativo',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 10.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 2.h),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isTerminatingSessions
                        ? null
                        : _terminateOtherSessions,
                    icon: _isTerminatingSessions
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            Icons.logout_rounded,
                            size: 16,
                            color: AppTheme.error,
                          ),
                    label: Text(
                      'Encerrar outras sessões',
                      style: TextStyle(
                        color: AppTheme.error,
                        fontWeight: FontWeight.w600,
                        fontSize: 12.sp,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppTheme.error.withAlpha(120)),
                      minimumSize: const Size(double.infinity, 44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.0),
                      ),
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

  Widget _buildSectionHeader(BuildContext context, String title) {
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

  Widget _buildCard(BuildContext context, {required Widget child}) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.all(3.w),
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
      child: child,
    );
  }

  Widget _buildPasswordField(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    required bool show,
    required VoidCallback onToggle,
  }) {
    final theme = Theme.of(context);
    return TextField(
      controller: controller,
      obscureText: !show,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide(color: AppTheme.primary, width: 1.5),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 3.w, vertical: 1.5.h),
        suffixIcon: IconButton(
          icon: Icon(
            show ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            size: 18,
          ),
          onPressed: onToggle,
        ),
      ),
    );
  }
}
