import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../routes/app_routes.dart';
import '../../services/supabase_service.dart';
import '../../services/security_service.dart';
import '../forgot_password_screen/forgot_password_screen.dart';

// ── Auth-only neon palette ──────────────────────────────────────────────────
const _kBg = Color(0xFF0A0A0E);
const _kPurple = Color(0xFFC026D3);
const _kViolet = Color(0xFF7C3AED);
const _kCyan = Color(0xFF00D2FF);
const _kFieldBg = Color(0xFF18181B);
const _kHint = Color(0xFFA1A1AA);
// ───────────────────────────────────────────────────────────────────────────

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _isResettingPassword = false;
  String? _errorMessage;

  // ── Brute-force protection ──────────────────────────────────────────────
  DateTime? _lockoutExpiry;
  int _failedAttempts = 0;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic));
    _fadeCtrl.forward();
    _checkLockoutStatus();
  }

  Future<void> _checkLockoutStatus() async {
    final expiry = await SecurityService.instance.getLoginLockoutExpiry();
    final attempts = await SecurityService.instance.getFailedAttemptCount();
    if (mounted) {
      setState(() {
        _lockoutExpiry = expiry;
        _failedAttempts = attempts;
      });
    }
  }

  bool get _isLockedOut {
    if (_lockoutExpiry == null) return false;
    return DateTime.now().isBefore(_lockoutExpiry!);
  }

  String get _lockoutMessage {
    if (_lockoutExpiry == null) return '';
    final remaining = _lockoutExpiry!.difference(DateTime.now());
    final mins = remaining.inMinutes + 1;
    return 'Muitas tentativas. Tente novamente em $mins minuto${mins > 1 ? 's' : ''}.';
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    // ── Brute-force lockout check ──────────────────────────────────────────
    await _checkLockoutStatus();
    if (_isLockedOut) {
      setState(() => _errorMessage = _lockoutMessage);
      return;
    }

    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      // ── Sanitize inputs before use ─────────────────────────────────────
      final email = SecurityService.sanitizeEmail(_emailCtrl.text.trim());
      final password = _passwordCtrl
          .text; // passwords are NOT sanitized (preserve special chars)

      // 1. Authenticate with credentials
      final response = await SupabaseService.instance.signIn(
        email: email,
        password: password,
      );
      if (!mounted) return;

      if (response.user != null) {
        // ── Clear failed attempts on success ───────────────────────────
        await SecurityService.instance.clearLoginAttempts();

        // 2. Check if 2FA is enabled for this user
        final is2FAEnabled =
            response.user!.userMetadata?['two_fa_enabled'] == true;

        if (is2FAEnabled) {
          // Send 2FA code and redirect to verification screen
          await SupabaseService.instance.send2FACode(email: email);
          if (!mounted) return;
          setState(() => _isLoading = false);
          context.push(AppRoutes.twoFactorVerify, extra: email);
          return;
        }

        final profile = await SupabaseService.instance
            .fetchCurrentUserProfile();
        if (!mounted) return;
        final onboardingCompleted =
            profile?['onboarding_completed'] as bool? ?? false;
        if (!onboardingCompleted) {
          context.go(AppRoutes.firstTimeSetup);
        } else {
          context.go(AppRoutes.homeFeedScreen);
        }
      } else {
        await SecurityService.instance.recordFailedLoginAttempt();
        await _checkLockoutStatus();
        setState(() {
          _isLoading = false;
          _errorMessage = 'Não foi possível fazer login. Tente novamente.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      // ── Record failed attempt on auth error ────────────────────────────
      await SecurityService.instance.recordFailedLoginAttempt();
      await _checkLockoutStatus();
      final remaining = SecurityService.maxAttempts - _failedAttempts;
      final errorStr = e.toString();
      // Handle "account not found" case — direct to signup
      if (errorStr.contains('Invalid login credentials') ||
          errorStr.contains('invalid_credentials')) {
        setState(() {
          _isLoading = false;
          _errorMessage = _isLockedOut
              ? _lockoutMessage
              : _mapAuthError(errorStr, remaining);
        });
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = _isLockedOut
              ? _lockoutMessage
              : _mapAuthError(errorStr, remaining);
        });
      }
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(
        () => _errorMessage = 'Digite seu e-mail para redefinir a senha.',
      );
      return;
    }
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$',
    );
    if (!emailRegex.hasMatch(email)) {
      setState(() => _errorMessage = 'Digite um e-mail válido.');
      return;
    }
    setState(() {
      _isResettingPassword = true;
      _errorMessage = null;
    });
    try {
      await SupabaseService.instance.client.auth.resetPasswordForEmail(email);
      if (!mounted) return;
      setState(() => _isResettingPassword = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'E-mail de redefinição enviado! Verifique sua caixa de entrada.',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: _kViolet,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isResettingPassword = false;
        _errorMessage = 'Não foi possível enviar o e-mail. Tente novamente.';
      });
    }
  }

  String _mapAuthError(String error, [int? remainingAttempts]) {
    String base;
    if (error.contains('Invalid login credentials') ||
        error.contains('invalid_credentials')) {
      base = 'E-mail ou senha incorretos.';
    } else if (error.contains('Email not confirmed')) {
      base = 'Confirme seu e-mail antes de entrar.';
    } else if (error.contains('Too many requests')) {
      base = 'Muitas tentativas. Aguarde um momento.';
    } else if (error.contains('network') || error.contains('SocketException')) {
      base = 'Sem conexão. Verifique sua internet.';
    } else {
      base = 'Erro ao entrar. Tente novamente.';
    }

    if (remainingAttempts != null &&
        remainingAttempts > 0 &&
        remainingAttempts < SecurityService.maxAttempts) {
      base +=
          ' ($remainingAttempts tentativa${remainingAttempts > 1 ? 's' : ''} restante${remainingAttempts > 1 ? 's' : ''})';
    }
    return base;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight:
                  size.height -
                  MediaQuery.of(context).padding.top -
                  MediaQuery.of(context).padding.bottom,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SlideTransition(
                  position: _slideAnim,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 52),
                      // ── Logo + Title ──────────────────────────────────
                      Center(
                        child: Column(
                          children: [
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  width: 130,
                                  height: 130,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(
                                      colors: [
                                        Color(0x55C026D3),
                                        Color(0x337C3AED),
                                        Colors.transparent,
                                      ],
                                    ),
                                  ),
                                ),
                                Image.asset(
                                  'assets/images/logo-sem-fundo.png',
                                  width: 140,
                                  height: 102,
                                  fit: BoxFit.contain,
                                  semanticLabel:
                                      'SintonIA logo com balões de conversa em gradiente roxo e azul neon',
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            ShaderMask(
                              shaderCallback: (bounds) => const LinearGradient(
                                colors: [_kPurple, _kViolet, _kCyan],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ).createShader(bounds),
                              child: Text(
                                'SintonIA',
                                style: GoogleFonts.nunitoSans(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Seu espaço seguro de conexões',
                              style: GoogleFonts.nunitoSans(
                                fontSize: 13,
                                color: _kHint,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 40),
                      // ── Welcome text ──────────────────────────────────
                      Text(
                        'Bem-vindo de volta 👋',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.nunitoSans(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Entre para continuar sua jornada',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.nunitoSans(
                          fontSize: 14,
                          color: _kHint,
                        ),
                      ),
                      const SizedBox(height: 28),
                      // ── Form ──────────────────────────────────────────
                      Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            _buildEmailField(),
                            const SizedBox(height: 16),
                            _buildPasswordField(),
                            if (_errorMessage != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.red.withAlpha(26),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.red.withAlpha(102),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.error_outline_rounded,
                                      color: Colors.redAccent,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _errorMessage!,
                                        style: GoogleFonts.nunitoSans(
                                          color: Colors.redAccent,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 4),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const ForgotPasswordScreen(),
                                    ),
                                  );
                                },
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 8,
                                  ),
                                ),
                                child: Text(
                                  'Esqueci minha senha',
                                  style: GoogleFonts.nunitoSans(
                                    color: _kCyan,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            _buildLoginButton(),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      _buildDivider(),
                      const SizedBox(height: 24),
                      _buildRegisterRow(),
                      const SizedBox(height: 36),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailCtrl,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      style: GoogleFonts.nunitoSans(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        labelText: 'E-mail',
        labelStyle: GoogleFonts.nunitoSans(color: _kHint, fontSize: 14),
        hintText: 'seu@email.com',
        hintStyle: GoogleFonts.nunitoSans(color: _kHint.withAlpha(153)),
        prefixIcon: const Icon(Icons.email_outlined, size: 20, color: _kHint),
        filled: true,
        fillColor: _kFieldBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: _kViolet.withAlpha(77)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: _kViolet.withAlpha(77)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _kCyan, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Informe seu e-mail';
        final emailRegex = RegExp(
          r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$',
        );
        if (!emailRegex.hasMatch(v.trim())) return 'E-mail inválido';
        return null;
      },
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordCtrl,
      obscureText: _obscurePassword,
      textInputAction: TextInputAction.done,
      onFieldSubmitted: (_) => _login(),
      style: GoogleFonts.nunitoSans(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        labelText: 'Senha',
        labelStyle: GoogleFonts.nunitoSans(color: _kHint, fontSize: 14),
        hintText: '••••••••',
        hintStyle: GoogleFonts.nunitoSans(color: _kHint.withAlpha(153)),
        prefixIcon: const Icon(Icons.lock_outlined, size: 20, color: _kHint),
        suffixIcon: IconButton(
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
          icon: Icon(
            _obscurePassword
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            size: 20,
            color: _kHint,
          ),
        ),
        filled: true,
        fillColor: _kFieldBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: _kViolet.withAlpha(77)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: _kViolet.withAlpha(77)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _kPurple, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
      ),
      validator: (v) {
        if (v == null || v.isEmpty) return 'Informe sua senha';
        if (v.length < 6) return 'Senha muito curta';
        return null;
      },
    );
  }

  Widget _buildLoginButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _isLoading
                ? [_kPurple.withAlpha(128), _kCyan.withAlpha(128)]
                : [_kPurple, _kViolet, _kCyan],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(30),
          boxShadow: _isLoading
              ? []
              : [
                  BoxShadow(
                    color: _kPurple.withAlpha(115),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _isLoading ? null : _login,
            borderRadius: BorderRadius.circular(30),
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
                  : Text(
                      'Entrar',
                      style: GoogleFonts.nunitoSans(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.white.withAlpha(31))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'ou',
            style: GoogleFonts.nunitoSans(color: _kHint, fontSize: 13),
          ),
        ),
        Expanded(child: Divider(color: Colors.white.withAlpha(31))),
      ],
    );
  }

  Widget _buildRegisterRow() {
    return Center(
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: GoogleFonts.nunitoSans(color: _kHint, fontSize: 14),
          children: [
            const TextSpan(text: 'Não tem uma conta? '),
            TextSpan(
              text: 'Criar conta',
              style: GoogleFonts.nunitoSans(
                color: _kCyan,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () => context.push(AppRoutes.onboardingScreen),
            ),
          ],
        ),
      ),
    );
  }
}
