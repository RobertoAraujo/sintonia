import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_export.dart';
import '../widgets/custom_error_widget.dart';
import './services/connectivity_sync_service.dart';
import './services/global_presence_service.dart';
import './services/notification_service.dart';
import './services/security_service.dart';
import './services/supabase_service.dart';
import './services/theme_notifier.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Security: Environment integrity check (root/jailbreak detection) ──────
  // Runs before any initialization to block compromised devices.
  // On web this always returns true (browser sandbox).
  if (!kIsWeb) {
    final isSecure = await SecurityService.isEnvironmentSecure();
    if (!isSecure) {
      // Device is rooted/jailbroken — show blocking screen
      runApp(const _BlockedDeviceApp());
      return;
    }
  }

  // Initialize Supabase
  try {
    await SupabaseService.initialize();
  } catch (e) {
    debugPrint('Failed to initialize Supabase: $e');
  }

  // Start connectivity monitor — auto-syncs offline message queue
  try {
    await ConnectivitySyncService.instance.init();
  } catch (e) {
    debugPrint('Failed to initialize ConnectivitySyncService: $e');
  }

  // Initialize theme preference
  await ThemeNotifier.instance.init();

  // Initialize notifications if user is already authenticated
  if (SupabaseService.instance.isAuthenticated) {
    NotificationService.instance.fetchNotifications();
    NotificationService.instance.subscribeRealtime();
    GlobalPresenceService.instance.init();
  }

  // Listen for auth state changes to start/stop notification service
  SupabaseService.instance.authStateChanges.listen((state) {
    if (state.event == AuthChangeEvent.signedIn) {
      NotificationService.instance.fetchNotifications();
      NotificationService.instance.subscribeRealtime();
      GlobalPresenceService.instance.init();
    } else if (state.event == AuthChangeEvent.signedOut) {
      NotificationService.instance.reset();
      GlobalPresenceService.instance.dispose();
    }
  });

  bool hasShownError = false;

  // 🚨 CRITICAL: Custom error handling - DO NOT REMOVE
  ErrorWidget.builder = (FlutterErrorDetails details) {
    if (!hasShownError) {
      hasShownError = true;

      // Reset flag after 3 seconds to allow error widget on new screens
      Future.delayed(Duration(seconds: 5), () {
        hasShownError = false;
      });

      return CustomErrorWidget(errorDetails: details);
    }
    return SizedBox.shrink();
  };

  // 🚨 CRITICAL: Device orientation lock - DO NOT REMOVE
  if (kIsWeb) {
    GoRouter.optionURLReflectsImperativeAPIs = true;
    runApp(const ProviderScope(child: MyApp()));
  } else {
    Future.wait([
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
    ]).then((value) {
      GoRouter.optionURLReflectsImperativeAPIs = true;
      runApp(const ProviderScope(child: MyApp()));
    });
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    ThemeNotifier.instance.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    ThemeNotifier.instance.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Sizer(
      builder: (context, orientation, screenType) {
        return MaterialApp.router(
          title: 'sintonia',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeNotifier.instance.themeMode,
          // 🚨 CRITICAL: NEVER REMOVE OR MODIFY
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(1.0)),
              child: child!,
            );
          },
          // 🚨 END CRITICAL SECTION
          debugShowCheckedModeBanner: false,
          routerConfig: appRouter,
        );
      },
    );
  }
}

/// Shown when the app detects a rooted/jailbroken device.
/// Blocks all app functionality to protect user data.
class _BlockedDeviceApp extends StatelessWidget {
  const _BlockedDeviceApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF0A0A0E),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.security_rounded,
                  color: Color(0xFFC026D3),
                  size: 72,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Dispositivo Não Autorizado',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Por segurança, o SintonIA não pode ser executado em dispositivos com root ou jailbreak ativo. '
                  'Restaure o dispositivo para as configurações de fábrica para continuar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFA1A1AA),
                    fontSize: 14,
                    height: 1.5,
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
