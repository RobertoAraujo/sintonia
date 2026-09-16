import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import './supabase_service.dart';

// ─── Notification Model ───────────────────────────────────────────────────────

enum NotificationType {
  like,
  comment,
  friendRequest,
  friendAccepted,
  message;

  static NotificationType fromString(String value) {
    switch (value) {
      case 'like':
        return NotificationType.like;
      case 'comment':
        return NotificationType.comment;
      case 'friend_request':
        return NotificationType.friendRequest;
      case 'friend_accepted':
        return NotificationType.friendAccepted;
      case 'message':
        return NotificationType.message;
      default:
        return NotificationType.like;
    }
  }
}

class AppNotification {
  final String id;
  final String recipientId;
  final String actorId;
  final NotificationType type;
  final String title;
  final String body;
  final String? referenceId;
  final bool isRead;
  final DateTime createdAt;

  // Joined actor profile fields
  final String? actorName;
  final String? actorAvatarUrl;

  const AppNotification({
    required this.id,
    required this.recipientId,
    required this.actorId,
    required this.type,
    required this.title,
    required this.body,
    this.referenceId,
    required this.isRead,
    required this.createdAt,
    this.actorName,
    this.actorAvatarUrl,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final actor = json['actor'] as Map<String, dynamic>?;
    return AppNotification(
      id: json['id'] as String,
      recipientId: json['recipient_id'] as String,
      actorId: json['actor_id'] as String,
      type: NotificationType.fromString(json['type'] as String? ?? 'like'),
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      referenceId: json['reference_id'] as String?,
      isRead: json['is_read'] as bool? ?? false,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      actorName:
          actor?['full_name'] as String? ?? actor?['username'] as String?,
      actorAvatarUrl: actor?['avatar_url'] as String?,
    );
  }

  AppNotification copyWith({bool? isRead}) {
    return AppNotification(
      id: id,
      recipientId: recipientId,
      actorId: actorId,
      type: type,
      title: title,
      body: body,
      referenceId: referenceId,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
      actorName: actorName,
      actorAvatarUrl: actorAvatarUrl,
    );
  }
}

// ─── Notification Service ─────────────────────────────────────────────────────

class NotificationService extends ChangeNotifier {
  static NotificationService? _instance;
  static NotificationService get instance =>
      _instance ??= NotificationService._();

  NotificationService._();

  final List<AppNotification> _notifications = [];
  RealtimeChannel? _channel;
  bool _isLoading = false;
  String? _error;

  List<AppNotification> get notifications => List.unmodifiable(_notifications);

  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  bool get isLoading => _isLoading;
  String? get error => _error;

  SupabaseClient get _client => SupabaseService.instance.client;
  String? get _userId => SupabaseService.instance.currentUserId;

  // ─── Fetch ──────────────────────────────────────────────────────────────────

  Future<void> fetchNotifications() async {
    final uid = _userId;
    if (uid == null) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final data = await _client
          .from('notifications')
          .select(
            '*, actor:user_profiles!actor_id(full_name, username, avatar_url)',
          )
          .eq('recipient_id', uid)
          .order('created_at', ascending: false)
          .limit(50);

      _notifications
        ..clear()
        ..addAll(
          (data as List<dynamic>)
              .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
              .toList(),
        );
    } catch (e) {
      _error = e.toString();
      debugPrint('NotificationService.fetchNotifications error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ─── Realtime ───────────────────────────────────────────────────────────────

  void subscribeRealtime() {
    final uid = _userId;
    if (uid == null) return;

    _channel?.unsubscribe();

    _channel = _client
        .channel('notifications:$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'recipient_id',
            value: uid,
          ),
          callback: (payload) async {
            // Fetch the full notification with actor join
            try {
              final row = await _client
                  .from('notifications')
                  .select(
                    '*, actor:user_profiles!actor_id(full_name, username, avatar_url)',
                  )
                  .eq('id', payload.newRecord['id'] as String)
                  .maybeSingle();
              if (row != null) {
                _notifications.insert(
                  0,
                  AppNotification.fromJson(row),
                );
                notifyListeners();
              }
            } catch (e) {
              debugPrint('NotificationService realtime fetch error: $e');
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'recipient_id',
            value: uid,
          ),
          callback: (payload) {
            final id = payload.newRecord['id'] as String?;
            if (id == null) return;
            final idx = _notifications.indexWhere((n) => n.id == id);
            if (idx != -1) {
              final isRead = payload.newRecord['is_read'] as bool? ?? false;
              _notifications[idx] = _notifications[idx].copyWith(
                isRead: isRead,
              );
              notifyListeners();
            }
          },
        )
        .subscribe();
  }

  void unsubscribeRealtime() {
    _channel?.unsubscribe();
    _channel = null;
  }

  // ─── Mark as read ────────────────────────────────────────────────────────────

  Future<void> markAsRead(String notificationId) async {
    final uid = _userId;
    if (uid == null) return;

    // Optimistic update
    final idx = _notifications.indexWhere((n) => n.id == notificationId);
    if (idx != -1 && !_notifications[idx].isRead) {
      _notifications[idx] = _notifications[idx].copyWith(isRead: true);
      notifyListeners();
    }

    try {
      await _client
          .from('notifications')
          .update({'is_read': true})
          .eq('id', notificationId)
          .eq('recipient_id', uid);
    } catch (e) {
      debugPrint('NotificationService.markAsRead error: $e');
      // Revert optimistic update on error
      if (idx != -1) {
        _notifications[idx] = _notifications[idx].copyWith(isRead: false);
        notifyListeners();
      }
    }
  }

  Future<void> markAllAsRead() async {
    final uid = _userId;
    if (uid == null) return;

    // Optimistic update
    for (int i = 0; i < _notifications.length; i++) {
      if (!_notifications[i].isRead) {
        _notifications[i] = _notifications[i].copyWith(isRead: true);
      }
    }
    notifyListeners();

    try {
      await _client
          .from('notifications')
          .update({'is_read': true})
          .eq('recipient_id', uid)
          .eq('is_read', false);
    } catch (e) {
      debugPrint('NotificationService.markAllAsRead error: $e');
      // Refetch on error
      await fetchNotifications();
    }
  }

  // ─── Cleanup ─────────────────────────────────────────────────────────────────

  void reset() {
    unsubscribeRealtime();
    _notifications.clear();
    _error = null;
    _isLoading = false;
    notifyListeners();
  }
}
