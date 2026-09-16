import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_export.dart';
import '../widgets/custom_error_widget.dart';
import './services/connectivity_sync_service.dart';
import './services/notification_service.dart';
import './services/supabase_service.dart';
import './services/theme_notifier.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
  }

  // Listen for auth state changes to start/stop notification service
  SupabaseService.instance.authStateChanges.listen((state) {
    if (state.event == AuthChangeEvent.signedIn) {
      NotificationService.instance.fetchNotifications();
      NotificationService.instance.subscribeRealtime();
    } else if (state.event == AuthChangeEvent.signedOut) {
      NotificationService.instance.reset();
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
