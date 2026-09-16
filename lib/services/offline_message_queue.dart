import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import './supabase_service.dart';

/// A single pending message waiting to be synced.
class PendingMessage {
  final String localId;
  final String conversationId;
  final String content;
  final String messageType;
  final DateTime createdAt;

  PendingMessage({
    required this.localId,
    required this.conversationId,
    required this.content,
    required this.messageType,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'localId': localId,
    'conversationId': conversationId,
    'content': content,
    'messageType': messageType,
    'createdAt': createdAt.toIso8601String(),
  };

  factory PendingMessage.fromJson(Map<String, dynamic> json) => PendingMessage(
    localId: json['localId'] as String,
    conversationId: json['conversationId'] as String,
    content: json['content'] as String,
    messageType: json['messageType'] as String? ?? 'text',
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}

/// Manages a persistent queue of outgoing messages that failed to send
/// due to being offline. Call [syncPending] when connectivity returns.
class OfflineMessageQueue {
  static OfflineMessageQueue? _instance;
  static OfflineMessageQueue get instance =>
      _instance ??= OfflineMessageQueue._();
  OfflineMessageQueue._();

  static const String _prefsKey = 'offline_message_queue';

  // Notifies listeners when the queue changes (e.g. to update UI badges).
  final ValueNotifier<int> pendingCount = ValueNotifier(0);

  // ── Persistence ──────────────────────────────────────────────────────────

  Future<List<PendingMessage>> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => PendingMessage.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('OfflineMessageQueue._load error: $e');
      return [];
    }
  }

  Future<void> _save(List<PendingMessage> queue) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(queue.map((m) => m.toJson()).toList());
      await prefs.setString(_prefsKey, encoded);
      pendingCount.value = queue.length;
    } catch (e) {
      debugPrint('OfflineMessageQueue._save error: $e');
    }
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Enqueue a message that could not be sent while offline.
  Future<void> enqueue(PendingMessage message) async {
    final queue = await _load();
    queue.add(message);
    await _save(queue);
    debugPrint(
      'OfflineMessageQueue: enqueued ${message.localId} (total: ${queue.length})',
    );
  }

  /// Returns all pending messages for a specific conversation (for UI display).
  Future<List<PendingMessage>> getPendingForConversation(
    String conversationId,
  ) async {
    final queue = await _load();
    return queue.where((m) => m.conversationId == conversationId).toList();
  }

  /// Attempt to send all queued messages to Supabase.
  /// Successfully sent messages are removed from the queue.
  /// Returns the list of [localId]s that were successfully synced.
  Future<List<String>> syncPending() async {
    final queue = await _load();
    if (queue.isEmpty) return [];

    debugPrint(
      'OfflineMessageQueue: syncing ${queue.length} pending message(s)',
    );

    final synced = <String>[];
    final remaining = <PendingMessage>[];

    for (final msg in queue) {
      try {
        final result = await SupabaseService.instance.sendMessage(
          conversationId: msg.conversationId,
          content: msg.content,
          messageType: msg.messageType,
        );
        if (result != null) {
          synced.add(msg.localId);
          debugPrint('OfflineMessageQueue: synced ${msg.localId}');
        } else {
          remaining.add(msg);
        }
      } catch (e) {
        debugPrint('OfflineMessageQueue: failed to sync ${msg.localId}: $e');
        remaining.add(msg);
      }
    }

    await _save(remaining);
    return synced;
  }

  /// Remove a specific message from the queue (e.g. user cancelled it).
  Future<void> remove(String localId) async {
    final queue = await _load();
    queue.removeWhere((m) => m.localId == localId);
    await _save(queue);
  }

  /// Refresh the [pendingCount] notifier from persisted storage.
  Future<void> refreshCount() async {
    final queue = await _load();
    pendingCount.value = queue.length;
  }
}
