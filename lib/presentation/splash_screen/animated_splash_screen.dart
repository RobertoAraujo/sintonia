import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../routes/app_routes.dart';
import '../../services/supabase_service.dart';

class AnimatedSplashScreen extends StatefulWidget {
  const AnimatedSplashScreen({super.key});

  @override
  State<AnimatedSplashScreen> createState() => _AnimatedSplashScreenState();
}

class _AnimatedSplashScreenState extends State<AnimatedSplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _glowController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();

    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.elasticOut),
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _logoController, curve: Curves.easeIn));

    _glowAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    _logoController.forward();

    Timer(const Duration(milliseconds: 2800), () {
      if (!mounted) return;
      final isAuthenticated = SupabaseService.instance.isAuthenticated;
      context.go(
        isAuthenticated ? AppRoutes.homeFeedScreen : AppRoutes.loginScreen,
      );
    });
  }

  @override
  void dispose() {
    _logoController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0E),
      body: Center(
        child: AnimatedBuilder(
          animation: Listenable.merge([_logoController, _glowController]),
          builder: (context, child) {
            return FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        // Outer glow pulse
                        Container(
                          width: 240 * _glowAnimation.value,
                          height: 240 * _glowAnimation.value,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                const Color(
                                  0xFFC026D3,
                                ).withOpacity(0.25 * _glowAnimation.value),
                                const Color(
                                  0xFF7C3AED,
                                ).withOpacity(0.15 * _glowAnimation.value),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                        // Inner glow
                        Container(
                          width: 200,
                          height: 200,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                const Color(0xFFC026D3).withAlpha(89),
                                const Color(0xFF00D2FF).withAlpha(51),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                        // Logo image
                        Image.asset(
                          'assets/images/logo-sem-fundo.png',
                          width: 170,
                          height: 125,
                          fit: BoxFit.contain,
                          semanticLabel:
                              'SintonIA logo com balões de conversa sobrepostos em gradiente roxo e azul neon',
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [
                          Color(0xFFC026D3),
                          Color(0xFF7C3AED),
                          Color(0xFF00D2FF),
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ).createShader(bounds),
                      child: Text(
                        'SintonIA',
                        style: GoogleFonts.nunitoSans(
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Seu espaço seguro de conexões',
                      style: GoogleFonts.nunitoSans(
                        fontSize: 14,
                        color: const Color(0xFFA1A1AA),
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
