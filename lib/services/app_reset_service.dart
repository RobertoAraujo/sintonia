import 'package:flutter/painting.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// AppResetService — clears all local state, caches, and signs out.
/// Call [clearAppData] before starting a new test session.
class AppResetService {
  AppResetService._();

  /// Clears SharedPreferences, image cache, and signs out from Supabase.
  static Future<void> clearAppData() async {
    // 1. Clear SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (e) {
      // ignore
    }

    // 2. Clear Flutter image cache (memory + disk via PaintingBinding)
    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (e) {
      // ignore
    }

    // 3. Sign out from Supabase (invalidates session token)
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      // ignore — may already be signed out
    }
  }
}
