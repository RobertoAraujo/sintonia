import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../presentation/admin_dashboard_screen/admin_dashboard_screen.dart';
import '../presentation/chat_screen/chat_screen.dart';
import '../presentation/first_time_setup_screen/first_time_setup_screen.dart';
import '../presentation/friends_screen/friends_screen.dart';
import '../presentation/home_feed_screen/home_feed_screen.dart';
import '../presentation/login_screen/login_screen.dart';
import '../presentation/notification_inbox_screen/notification_inbox_screen.dart';
import '../presentation/notification_inbox_screen/notification_archive_screen.dart';
import '../presentation/onboarding_screen/onboarding_screen.dart';
import '../presentation/profile_screen/profile_screen.dart';
import '../presentation/sintonia_screen/sintonia_screen.dart';
import '../presentation/splash_screen/animated_splash_screen.dart';
import '../presentation/two_factor_verify_screen/two_factor_verify_screen.dart';
import '../services/supabase_service.dart';
import '../widgets/app_scaffold.dart';

class AppRoutes {
  static const String splash = '/splash';
  static const String initial = '/';
  static const String loginScreen = '/login';
  static const String onboardingScreen = '/onboarding';
  static const String firstTimeSetup = '/first-time-setup';
  static const String homeFeedScreen = '/home-feed-screen';
  static const String profileScreen = '/profile-screen';
  static const String chatScreen = '/chat-screen';
  static const String sintoniaScreen = '/sintonia-screen';
  static const String friendsScreen = '/friends-screen';
  static const String adminDashboardScreen = '/admin-dashboard-screen';
  static const String notificationInboxScreen = '/notifications';
  static const String notificationArchiveScreen = '/notification-archive';
  static const String twoFactorVerify = '/verify-2fa';
}

final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.initial,
  redirect: (context, state) {
    final isAuthenticated = SupabaseService.instance.isAuthenticated;
    final isSplash = state.matchedLocation == AppRoutes.initial;
    final isAuthRoute =
        isSplash ||
        state.matchedLocation == AppRoutes.loginScreen ||
        state.matchedLocation == AppRoutes.onboardingScreen ||
        state.matchedLocation == AppRoutes.firstTimeSetup;

    // Splash screen handles its own navigation — never redirect away from it
    if (isSplash) return null;

    // If authenticated and trying to access auth routes, redirect to feed
    if (isAuthenticated &&
        isAuthRoute &&
        state.matchedLocation != AppRoutes.firstTimeSetup) {
      return AppRoutes.homeFeedScreen;
    }
    // If not authenticated and trying to access protected routes, redirect to login
    if (!isAuthenticated && !isAuthRoute) {
      return AppRoutes.loginScreen;
    }
    return null;
  },
  routes: [
    GoRoute(
      path: AppRoutes.initial,
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const AnimatedSplashScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ),
              child: child,
            ),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    ),
    GoRoute(
      path: AppRoutes.loginScreen,
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const LoginScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ),
              child: child,
            ),
        transitionDuration: const Duration(milliseconds: 280),
      ),
    ),
    GoRoute(
      path: AppRoutes.onboardingScreen,
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const OnboardingScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(1, 0),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: child,
            ),
        transitionDuration: const Duration(milliseconds: 320),
      ),
    ),
    GoRoute(
      path: AppRoutes.firstTimeSetup,
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const FirstTimeSetupScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0, 1),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: child,
            ),
        transitionDuration: const Duration(milliseconds: 350),
      ),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppScaffold(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.homeFeedScreen,
              builder: (context, state) => const HomeFeedScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.chatScreen,
              builder: (context, state) => const ChatScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.friendsScreen,
              builder: (context, state) => const FriendsScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.sintoniaScreen,
              builder: (context, state) => const SintoniaScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.profileScreen,
              builder: (context, state) => const ProfileScreen(),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.adminDashboardScreen,
      redirect: (context, state) {
        // Must be authenticated to even attempt admin access
        if (!SupabaseService.instance.isAuthenticated) {
          return AppRoutes.loginScreen;
        }
        return null;
      },
      builder: (context, state) => const AdminDashboardScreen(),
    ),
    GoRoute(
      path: AppRoutes.notificationInboxScreen,
      builder: (context, state) => const NotificationInboxScreen(),
    ),
    GoRoute(
      path: AppRoutes.notificationArchiveScreen,
      builder: (context, state) => const NotificationArchiveScreen(),
    ),
    GoRoute(
      path: AppRoutes.twoFactorVerify,
      pageBuilder: (context, state) {
        final email = state.extra as String? ?? '';
        return CustomTransitionPage(
          key: state.pageKey,
          child: TwoFactorVerifyScreen(email: email),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FadeTransition(
                opacity: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                ),
                child: child,
              ),
          transitionDuration: const Duration(milliseconds: 280),
        );
      },
    ),
  ],
);
