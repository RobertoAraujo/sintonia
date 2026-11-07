import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import './app_navigation.dart';

// Global notifier so HomeFeedScreen can register its post modal opener
OpenPostModalCallback? _globalPostModalCallback;

void registerGlobalPostModal(OpenPostModalCallback cb) {
  _globalPostModalCallback = cb;
}

/// Global notifier: set to `true` when the user is inside a private chat screen
/// so the bottom nav bar hides automatically.
final ValueNotifier<bool> chatKeyboardVisibleNotifier = ValueNotifier(false);

/// Global notifier: set to `false` to hide the bottom nav bar (e.g. on scroll down)
/// and `true` to show it again (e.g. on scroll up).
final ValueNotifier<bool> navBarVisibleNotifier = ValueNotifier(true);

class AppScaffold extends StatefulWidget {
  final StatefulNavigationShell navigationShell;

  const AppScaffold({required this.navigationShell, super.key});

  @override
  State<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends State<AppScaffold>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      value: 1.0, // 1 = visible
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 1.5), end: Offset.zero).animate(
          CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
        );

    chatKeyboardVisibleNotifier.addListener(_onChatVisibilityChanged);
    navBarVisibleNotifier.addListener(_onNavBarVisibilityChanged);
  }

  @override
  void dispose() {
    chatKeyboardVisibleNotifier.removeListener(_onChatVisibilityChanged);
    navBarVisibleNotifier.removeListener(_onNavBarVisibilityChanged);
    _animController.dispose();
    super.dispose();
  }

  void _onChatVisibilityChanged() {
    if (mounted) setState(() {});
  }

  void _onNavBarVisibilityChanged() {
    if (!mounted) return;
    if (navBarVisibleNotifier.value) {
      _animController.forward();
    } else {
      _animController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hideNav = chatKeyboardVisibleNotifier.value;
    return Scaffold(
      extendBody: true,
      body: widget.navigationShell,
      bottomNavigationBar: hideNav
          ? null
          : SlideTransition(
              position: _slideAnimation,
              child: AppNavigation(
                navigationShell: widget.navigationShell,
                onCreatePost: _globalPostModalCallback,
              ),
            ),
    );
  }
}
