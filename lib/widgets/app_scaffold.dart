import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import './app_navigation.dart';

// Global notifier so HomeFeedScreen can register its post modal opener
OpenPostModalCallback? _globalPostModalCallback;

void registerGlobalPostModal(OpenPostModalCallback cb) {
  _globalPostModalCallback = cb;
}

class AppScaffold extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const AppScaffold({required this.navigationShell, super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: AppNavigation(
        navigationShell: navigationShell,
        onCreatePost: _globalPostModalCallback,
      ),
    );
  }
}
