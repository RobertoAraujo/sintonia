import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import './offline_message_queue.dart';

/// Monitors network connectivity and automatically triggers
/// [OfflineMessageQueue.syncPending] when the device comes back online.
/// Call [init] once at app startup (e.g. in main.dart after Supabase init).
class ConnectivitySyncService {
  static ConnectivitySyncService? _instance;
  static ConnectivitySyncService get instance =>
      _instance ??= ConnectivitySyncService._();
  ConnectivitySyncService._();

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _wasOffline = false;
  bool _isSyncing = false;

  /// Start listening for connectivity changes.
  Future<void> init() async {
    // Check current state immediately on startup
    final results = await Connectivity().checkConnectivity();
    final isOnline = _isOnline(results);
    _wasOffline = !isOnline;

    // If we start online, attempt a sync in case messages were queued
    // during a previous offline session.
    if (isOnline) {
      await _trySyncOnce();
    }

    _subscription = Connectivity().onConnectivityChanged.listen(
      _onConnectivityChanged,
    );
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) async {
    final isOnline = _isOnline(results);

    if (!isOnline) {
      _wasOffline = true;
      debugPrint('ConnectivitySyncService: device went offline');
      return;
    }

    // Device just came back online
    if (_wasOffline) {
      _wasOffline = false;
      debugPrint('ConnectivitySyncService: device back online — syncing queue');
      await _trySyncOnce();
    }
  }

  Future<void> _trySyncOnce() async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      final synced = await OfflineMessageQueue.instance.syncPending();
      if (synced.isNotEmpty) {
        debugPrint(
          'ConnectivitySyncService: synced ${synced.length} message(s)',
        );
      }
    } catch (e) {
      debugPrint('ConnectivitySyncService: sync error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  bool _isOnline(List<ConnectivityResult> results) {
    return results.any(
      (r) =>
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.ethernet,
    );
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}
