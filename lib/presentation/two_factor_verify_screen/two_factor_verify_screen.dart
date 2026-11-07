import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../routes/app_routes.dart';
import '../../services/supabase_service.dart';

const _kBg = Color(0xFF0A0A0E);
const _kPurple = Color(0xFFC026D3);
const _kViolet = Color(0xFF7C3AED);
const _kCyan = Color(0xFF00D2FF);
const _kFieldBg = Color(0xFF18181B);
const _kHint = Color(0xFFA1A1AA);

class TwoFactorVerifyScreen extends StatefulWidget {
  final String email;
  const TwoFactorVerifyScreen({super.key, required this.email});

  @override
  State<TwoFactorVerifyScreen> createState() => _TwoFactorVerifyScreenState();
}

class _TwoFactorVerifyScreenState extends State<TwoFactorVerifyScreen>
    with SingleTickerProviderStateMixin {
  final List<TextEditingController> _controllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _isLoading = false;
  bool _isResending = false;
  String? _errorMessage;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

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
    _fadeCtrl.dispose();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _fullCode => _controllers.map((c) => c.text).join();

  Future<void> _verify() async {
    final code = _fullCode;
    if (code.length < 6) {
      setState(() => _errorMessage = 'Digite o código completo de 6 dígitos.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await SupabaseService.instance.verify2FACode(
        email: widget.email,
        code: code,
      );

      if (!mounted) return;

      if (result) {
        // 2FA verified — navigate to home
        final profile = await SupabaseService.instance
            .fetchCurrentUserProfile();
        if (!mounted) return;
        final onboardingCompleted =
            profile?['onboarding_completed'] as bool? ?? false;
        if (onboardingCompleted) {
          context.go(AppRoutes.homeFeedScreen);
        } else {
          context.go(AppRoutes.firstTimeSetup);
        }
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Código inválido ou expirado. Tente novamente.';
        });
        _clearCode();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Erro ao verificar código. Tente novamente.';
      });
    }
  }

  Future<void> _resendCode() async {
    setState(() {
      _isResending = true;
      _errorMessage = null;
    });
    try {
      await SupabaseService.instance.send2FACode(email: widget.email);
      if (!mounted) return;
      setState(() => _isResending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Novo código enviado para ${widget.email}',
            style: GoogleFonts.nunitoSans(color: Colors.white),
          ),
          backgroundColor: _kViolet,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      _clearCode();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isResending = false;
        _errorMessage = 'Erro ao reenviar código.';
      });
    }
  }

  void _clearCode() {
    for (final c in _controllers) {
      c.clear();
    }
    _focusNodes[0].requestFocus();
  }

  void _onDigitChanged(int index, String value) {
    if (value.length == 1 && index < 5) {
      _focusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    // Auto-verify when all 6 digits entered
    if (_fullCode.length == 6) {
      _verify();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => context.go(AppRoutes.loginScreen),
        ),
      ),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 24),
                // Icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        _kPurple.withAlpha(80),
                        _kCyan.withAlpha(40),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: const Icon(
                    Icons.verified_user_rounded,
                    color: _kCyan,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Verificação em Duas Etapas',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.nunitoSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Digite o código de 6 dígitos enviado para\n${widget.email}',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.nunitoSans(
                    fontSize: 14,
                    color: _kHint,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 36),
                // 6-digit code input
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(6, (index) {
                    return Container(
                      width: 46,
                      height: 56,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      child: TextFormField(
                        controller: _controllers[index],
                        focusNode: _focusNodes[index],
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        maxLength: 1,
                        style: GoogleFonts.nunitoSans(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          counterText: '',
                          filled: true,
                          fillColor: _kFieldBg,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: _kViolet.withAlpha(77),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: _kViolet.withAlpha(77),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: _kCyan,
                              width: 2,
                            ),
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: (value) => _onDigitChanged(index, value),
                      ),
                    );
                  }),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withAlpha(26),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.withAlpha(102)),
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
                const SizedBox(height: 28),
                // Verify button
                SizedBox(
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
                        onTap: _isLoading ? null : _verify,
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
                                  'Verificar Código',
                                  style: GoogleFonts.nunitoSans(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Resend
                TextButton(
                  onPressed: _isResending ? null : _resendCode,
                  child: _isResending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _kCyan,
                          ),
                        )
                      : Text(
                          'Não recebeu o código? Reenviar',
                          style: GoogleFonts.nunitoSans(
                            color: _kCyan,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => context.go(AppRoutes.loginScreen),
                  child: Text(
                    'Voltar ao login',
                    style: GoogleFonts.nunitoSans(color: _kHint, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
