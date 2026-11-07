import 'dart:async';

import 'package:flutter/foundation.dart';

import './supabase_service.dart';

/// Manages online/offline presence using a `last_seen` timestamp column
/// in the `user_profiles` table.
///
/// Heartbeat strategy:
/// - Every 15 seconds, the current user's `last_seen` is updated via RPC.
/// - A user is considered Online if their `last_seen` is within the last 35 seconds.
/// - [onlineUsers] is a reactive set updated by a periodic poll every 20 seconds.
class GlobalPresenceService {
  static GlobalPresenceService? _instance;
  static GlobalPresenceService get instance =>
      _instance ??= GlobalPresenceService._();
  GlobalPresenceService._();

  /// Notifier containing the set of user IDs considered online.
  final ValueNotifier<Set<String>> onlineUsers = ValueNotifier({});

  Timer? _heartbeatTimer;
  Timer? _pollTimer;

  bool _initialized = false;

  /// How long (seconds) without a heartbeat before a user is considered offline.
  static const int _onlineThresholdSeconds = 35;

  /// Start broadcasting this user's presence and polling others.
  /// Safe to call multiple times — subsequent calls are no-ops.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    final myId = SupabaseService.instance.currentUserId;
    if (myId == null || myId.isEmpty) return;

    // Immediately mark self as online
    await _updateLastSeen();

    // Heartbeat: update last_seen every 15 seconds
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      await _updateLastSeen();
    });

    // Poll online users every 20 seconds
    await _pollOnlineUsers();
    _pollTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      await _pollOnlineUsers();
    });
  }

  Future<void> _updateLastSeen() async {
    try {
      await SupabaseService.instance.client.rpc('update_last_seen');
      debugPrint('GlobalPresenceService: last_seen updated');
    } catch (e) {
      debugPrint('GlobalPresenceService: update_last_seen error: $e');
    }
  }

  Future<void> _pollOnlineUsers() async {
    try {
      final cutoff = DateTime.now().subtract(
        Duration(seconds: _onlineThresholdSeconds),
      );
      final rows = await SupabaseService.instance.client
          .from('user_profiles')
          .select('id')
          .gte('last_seen', cutoff.toIso8601String());

      final ids = <String>{};
      for (final row in rows as List) {
        final id = row['id'] as String?;
        if (id != null && id.isNotEmpty) ids.add(id);
      }
      debugPrint('GlobalPresenceService: online users = $ids');
      onlineUsers.value = ids;
    } catch (e) {
      debugPrint('GlobalPresenceService: poll error: $e');
    }
  }

  /// Returns true if [userId]'s last_seen was within the last 35 seconds.
  bool isUserOnline(String userId) => onlineUsers.value.contains(userId);

  /// Fetch a single user's online status directly from DB (for immediate check).
  Future<bool> fetchIsUserOnline(String userId) async {
    try {
      final cutoff = DateTime.now().subtract(
        Duration(seconds: _onlineThresholdSeconds),
      );
      final rows = await SupabaseService.instance.client
          .from('user_profiles')
          .select('id')
          .eq('id', userId)
          .gte('last_seen', cutoff.toIso8601String());
      return (rows as List).isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Stop broadcasting and clean up. Call on sign-out.
  Future<void> dispose() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    onlineUsers.value = {};
    _initialized = false;
    _instance = null;
  }
}
