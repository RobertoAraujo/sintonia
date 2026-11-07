import 'package:flutter/foundation.dart';

import './supabase_service.dart';

class UserSettingsService {
  static UserSettingsService? _instance;
  static UserSettingsService get instance =>
      _instance ??= UserSettingsService._();
  UserSettingsService._();

  final _client = SupabaseService.instance.client;

  // Default settings
  static const Map<String, dynamic> _defaults = {
    'dark_mode': false,
    'notify_messages': true,
    'notify_friendships': true,
    'notify_feed': true,
    'notify_ai_suggestions': false,
    'is_public_profile': true,
    'show_hyperfocus': true,
    'show_interests': true,
    'show_pets': true,
    'allow_direct_messages': true,
    'reduce_animations': false,
  };

  /// Fetch settings for the current user. Creates a row with defaults if none exists.
  Future<Map<String, dynamic>> fetchSettings() async {
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) return Map<String, dynamic>.from(_defaults);

    try {
      final data = await _client
          .from('user_settings')
          .select()
          .eq('user_id', uid)
          .maybeSingle();

      if (data == null) {
        // Insert defaults
        final newRow = {'user_id': uid, ..._defaults};
        await _client.from('user_settings').insert(newRow);
        return Map<String, dynamic>.from(_defaults);
      }
      return Map<String, dynamic>.from(data);
    } catch (e) {
      debugPrint('UserSettingsService.fetchSettings error: $e');
      return Map<String, dynamic>.from(_defaults);
    }
  }

  /// Fetch settings for any user by ID (used to enforce privacy on their profile).
  Future<Map<String, dynamic>> fetchSettingsForUser(String userId) async {
    try {
      final data = await _client
          .from('user_settings')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (data == null) return Map<String, dynamic>.from(_defaults);
      return Map<String, dynamic>.from(data);
    } catch (e) {
      debugPrint('UserSettingsService.fetchSettingsForUser error: $e');
      return Map<String, dynamic>.from(_defaults);
    }
  }

  /// Update a single boolean setting field.
  Future<void> updateSetting(String field, bool value) async {
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) return;

    try {
      await _client.from('user_settings').upsert({
        'user_id': uid,
        field: value,
      }, onConflict: 'user_id');
    } catch (e) {
      debugPrint('UserSettingsService.updateSetting error: $e');
    }
  }

  /// Fetch blocked users with their profile info.
  Future<List<Map<String, dynamic>>> fetchBlockedUsers() async {
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) return [];

    try {
      // Fetch blocked_users rows first
      final data = await _client
          .from('blocked_users')
          .select('id, blocked_user_id, created_at')
          .eq('blocker_id', uid)
          .order('created_at', ascending: false);

      final rows = List<Map<String, dynamic>>.from(data);
      if (rows.isEmpty) return [];

      // Collect all blocked user IDs
      final blockedIds = rows
          .map((r) => r['blocked_user_id'] as String)
          .toList();

      // Fetch profiles for those IDs
      final profiles = await _client
          .from('user_profiles')
          .select('id, full_name, username, avatar_url')
          .inFilter('id', blockedIds);

      final profileMap = <String, Map<String, dynamic>>{};
      for (final p in profiles as List) {
        profileMap[p['id'] as String] = Map<String, dynamic>.from(p);
      }

      // Merge profile data into each row
      return rows.map((r) {
        final blockedId = r['blocked_user_id'] as String;
        return {...r, 'user_profiles': profileMap[blockedId]};
      }).toList();
    } catch (e) {
      debugPrint('UserSettingsService.fetchBlockedUsers error: $e');
      return [];
    }
  }

  /// Unblock a user by their blocked_user_id.
  Future<bool> unblockUser(String blockedUserId) async {
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) return false;

    try {
      await _client
          .from('blocked_users')
          .delete()
          .eq('blocker_id', uid)
          .eq('blocked_user_id', blockedUserId);
      return true;
    } catch (e) {
      debugPrint('UserSettingsService.unblockUser error: $e');
      return false;
    }
  }
}
