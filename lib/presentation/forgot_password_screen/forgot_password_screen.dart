import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/supabase_service.dart';
import '../../services/security_service.dart';

// ── Auth-only neon palette ──────────────────────────────────────────────────
const _kBg = Color(0xFF0A0A0E);
const _kPurple = Color(0xFFC026D3);
const _kViolet = Color(0xFF7C3AED);
const _kCyan = Color(0xFF00D2FF);
const _kFieldBg = Color(0xFF18181B);
const _kHint = Color(0xFFA1A1AA);
// ───────────────────────────────────────────────────────────────────────────

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();

  bool _isLoading = false;
  bool _codeSent = false; // Controls 2-step display
  bool _obscurePassword = true;
  bool _resetSuccess = false;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic));
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _newPasswordCtrl.dispose();
    super.dispose();
  }

  // ── STEP 1: Send temporary code via Edge Function ─────────────────────────
  Future<void> _sendTemporaryCode() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      // Sanitize email before sending to backend
      final sanitizedEmail = SecurityService.sanitizeEmail(
        _emailCtrl.text.trim(),
      );

      final response = await SupabaseService.instance.client.functions.invoke(
        'send-reset-code',
        body: {'email': sanitizedEmail},
      );

      if (!mounted) return;

      final data = response.data as Map<String, dynamic>?;
      final error = data?['error'] as String?;

      if (error != null) {
        _showSnackBar(error, isError: true);
        return;
      }

      // Animate to step 2
      await _fadeCtrl.reverse();
      setState(() => _codeSent = true);
      _fadeCtrl.forward();

      _showSnackBar(
        'Código enviado para ${_emailCtrl.text.trim()}! Verifique sua caixa de entrada.',
        isError: false,
      );
    } catch (e) {
      if (!mounted) return;
      _showSnackBar(
        'Não foi possível enviar o código. Tente novamente.',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── STEP 2: Verify code + reset password via Edge Function ────────────────
  Future<void> _verifyAndResetPassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final response = await SupabaseService.instance.client.functions.invoke(
        'verify-reset-code',
        body: {
          'email': _emailCtrl.text.trim().toLowerCase(),
          'code': _codeCtrl.text.trim(),
          'newPassword': _newPasswordCtrl.text,
        },
      );

      if (!mounted) return;

      final data = response.data as Map<String, dynamic>?;
      final error = data?['error'] as String?;

      if (error != null) {
        _showSnackBar(error, isError: true);
        return;
      }

      // Show success state
      await _fadeCtrl.reverse();
      setState(() => _resetSuccess = true);
      _fadeCtrl.forward();
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Erro ao redefinir senha. Tente novamente.', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.nunitoSans(color: Colors.white),
        ),
        backgroundColor: isError ? Colors.redAccent : _kPurple,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ── Gradient button ───────────────────────────────────────────────────────
  Widget _buildGradientButton({
    required String label,
    required VoidCallback? onTap,
  }) {
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
            onTap: onTap,
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
                      label,
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

  // ── Input field builder ───────────────────────────────────────────────────
  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData prefixIcon,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
    bool enabled = true,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      enabled: enabled,
      style: GoogleFonts.nunitoSans(
        color: enabled ? Colors.white : _kHint,
        fontSize: 15,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.nunitoSans(color: _kHint, fontSize: 14),
        hintText: hint,
        hintStyle: GoogleFonts.nunitoSans(color: _kHint.withAlpha(153)),
        prefixIcon: Icon(prefixIcon, size: 20, color: _kHint),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: enabled ? _kFieldBg : _kFieldBg.withAlpha(128),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: _kViolet.withAlpha(77)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: _kViolet.withAlpha(77)),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: _kViolet.withAlpha(40)),
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
      validator: validator,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 24),

                    // ── Logo ──────────────────────────────────────────
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
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20.0),
                          child: Image.asset(
                            'assets/images/image-1789766339147.png',
                            width: 90,
                            height: 90,
                            fit: BoxFit.cover,
                            semanticLabel:
                                'SintonIA logo com balões de conversa em gradiente roxo e azul neon',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // ── Title ─────────────────────────────────────────
                    Text(
                      'Recuperar Senha 🔑',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.nunitoSans(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _resetSuccess
                          ? 'Sua senha foi redefinida com sucesso!'
                          : _codeSent
                          ? 'Insira o código recebido no e-mail e crie sua nova senha.'
                          : 'Digite o e-mail cadastrado para receber o código de verificação.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.nunitoSans(
                        fontSize: 14,
                        color: _kHint,
                      ),
                    ),
                    const SizedBox(height: 36),

                    // ── SUCCESS STATE ─────────────────────────────────
                    if (_resetSuccess) ...[
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: _kViolet.withAlpha(30),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _kCyan.withAlpha(80)),
                        ),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.check_circle_rounded,
                              color: _kCyan,
                              size: 52,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Senha redefinida!',
                              style: GoogleFonts.nunitoSans(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Sua nova senha foi salva com sucesso. Faça login para continuar.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.nunitoSans(
                                fontSize: 13,
                                color: _kHint,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      _buildGradientButton(
                        label: 'Ir para o Login',
                        onTap: () => Navigator.of(context).pop(),
                      ),
                    ]
                    // ── FORM (STEP 1 + STEP 2) ────────────────────────
                    else ...[
                      Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            // ── STEP 1: Email field (disabled after code sent) ──
                            _buildInputField(
                              controller: _emailCtrl,
                              label: 'E-mail',
                              hint: 'seu@email.com',
                              prefixIcon: Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress,
                              enabled: !_codeSent,
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Informe seu e-mail';
                                }
                                final emailRegex = RegExp(
                                  r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$',
                                );
                                if (!emailRegex.hasMatch(v.trim())) {
                                  return 'E-mail inválido';
                                }
                                return null;
                              },
                            ),

                            // ── STEP 2: Code + New Password fields ──────────
                            if (_codeSent) ...[
                              const SizedBox(height: 16),

                              // Code field
                              _buildInputField(
                                controller: _codeCtrl,
                                label: 'Código de Verificação',
                                hint: '000000',
                                prefixIcon: Icons.vpn_key_outlined,
                                keyboardType: TextInputType.number,
                                validator: (v) {
                                  if (v == null || v.trim().length < 4) {
                                    return 'Digite o código completo recebido no e-mail';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),

                              // New password field
                              _buildInputField(
                                controller: _newPasswordCtrl,
                                label: 'Nova Senha',
                                hint: 'Mínimo 6 caracteres',
                                prefixIcon: Icons.lock_outline_rounded,
                                obscureText: _obscurePassword,
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    color: _kHint,
                                    size: 20,
                                  ),
                                  onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword,
                                  ),
                                ),
                                validator: (v) {
                                  if (v == null || v.length < 6) {
                                    return 'A nova senha deve ter no mínimo 6 caracteres';
                                  }
                                  return null;
                                },
                              ),

                              // Resend code link
                              const SizedBox(height: 12),
                              GestureDetector(
                                onTap: _isLoading
                                    ? null
                                    : () async {
                                        await _fadeCtrl.reverse();
                                        setState(() {
                                          _codeSent = false;
                                          _codeCtrl.clear();
                                          _newPasswordCtrl.clear();
                                        });
                                        _fadeCtrl.forward();
                                      },
                                child: Text(
                                  'Reenviar código',
                                  style: GoogleFonts.nunitoSans(
                                    color: _kCyan,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    decoration: TextDecoration.underline,
                                    decorationColor: _kCyan,
                                  ),
                                ),
                              ),
                            ],

                            const SizedBox(height: 28),

                            // ── Action button (changes label per step) ──
                            _buildGradientButton(
                              label: _codeSent
                                  ? 'Redefinir Senha e Entrar'
                                  : 'Enviar Código de Verificação',
                              onTap: _isLoading
                                  ? null
                                  : (_codeSent
                                        ? _verifyAndResetPassword
                                        : _sendTemporaryCode),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 36),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
