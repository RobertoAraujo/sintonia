import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:sizer/sizer.dart';

import '../../services/notification_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';

class NotificationInboxScreen extends StatefulWidget {
  const NotificationInboxScreen({super.key});

  @override
  State<NotificationInboxScreen> createState() =>
      _NotificationInboxScreenState();
}

class _NotificationInboxScreenState extends State<NotificationInboxScreen> {
  final NotificationService _service = NotificationService.instance;
  // Track which friend-request notifications are being processed
  final Set<String> _processingIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _service.fetchNotifications();
    });
  }

  IconData _iconForType(NotificationType type) {
    switch (type) {
      case NotificationType.like:
        return Icons.favorite_rounded;
      case NotificationType.comment:
        return Icons.chat_bubble_rounded;
      case NotificationType.friendRequest:
        return Icons.person_add_rounded;
      case NotificationType.friendAccepted:
        return Icons.people_rounded;
      case NotificationType.message:
        return Icons.message_rounded;
    }
  }

  Color _colorForType(NotificationType type) {
    switch (type) {
      case NotificationType.like:
        return const Color(0xFFE91E63);
      case NotificationType.comment:
        return AppTheme.primary;
      case NotificationType.friendRequest:
        return const Color(0xFF4CAF50);
      case NotificationType.friendAccepted:
        return const Color(0xFF2196F3);
      case NotificationType.message:
        return AppTheme.secondary;
    }
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Agora';
    if (diff.inMinutes < 60) return '${diff.inMinutes}min';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${(diff.inDays / 7).floor()}sem';
  }

  Future<void> _acceptFriendRequest(AppNotification notif) async {
    if (_processingIds.contains(notif.id)) return;
    setState(() => _processingIds.add(notif.id));

    try {
      // referenceId holds the friendship row id
      final friendshipId = notif.referenceId ?? notif.actorId;
      // Try to find the pending friendship by actor
      final requests = await SupabaseService.instance
          .fetchFriendRequests();
      final match = requests.firstWhere(
        (r) => r['requester_id'] == notif.actorId,
        orElse: () => <String, dynamic>{},
      );

      bool ok = false;
      if (match.isNotEmpty) {
        ok = await SupabaseService.instance.acceptFriendRequest(
          match['id'] as String,
        );
      } else {
        ok = await SupabaseService.instance.acceptFriendRequest(friendshipId);
      }
    

      if (ok && mounted) {
        _service.markAsRead(notif.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Você e ${notif.actorName ?? 'usuário'} agora são amigos 🎉',
            ),
            backgroundColor: const Color(0xFF4CAF50),
          ),
        );
        _service.fetchNotifications();
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _processingIds.remove(notif.id));
    }
  }

  Future<void> _declineFriendRequest(AppNotification notif) async {
    if (_processingIds.contains(notif.id)) return;
    setState(() => _processingIds.add(notif.id));

    try {
      final requests = await SupabaseService.instance
          .fetchFriendRequests();
      final match = requests.firstWhere(
        (r) => r['requester_id'] == notif.actorId,
        orElse: () => <String, dynamic>{},
      );

      bool ok = false;
      if (match.isNotEmpty) {
        ok = await SupabaseService.instance.declineFriendRequest(
          match['id'] as String,
        );
      } else if (notif.referenceId != null) {
        ok = await SupabaseService.instance.declineFriendRequest(
          notif.referenceId!,
        );
      }

      if (ok && mounted) {
        _service.markAsRead(notif.id);
        _service.fetchNotifications();
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _processingIds.remove(notif.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Notificações',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 18.sp,
            color: theme.colorScheme.onSurface,
          ),
        ),
        actions: [
          ListenableBuilder(
            listenable: _service,
            builder: (context, _) {
              if (_service.unreadCount == 0) return const SizedBox.shrink();
              return TextButton(
                onPressed: _service.markAllAsRead,
                child: Text(
                  'Marcar todas',
                  style: GoogleFonts.inter(
                    fontSize: 12.sp,
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListenableBuilder(
        listenable: _service,
        builder: (context, _) {
          if (_service.isLoading && _service.notifications.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (_service.error != null && _service.notifications.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 48,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Erro ao carregar notificações',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _service.fetchNotifications,
                    child: const Text('Tentar novamente'),
                  ),
                ],
              ),
            );
          }

          if (_service.notifications.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withAlpha(20),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.notifications_none_rounded,
                      size: 40,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Nenhuma notificação',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      fontSize: 16.sp,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Quando alguém curtir, comentar ou\nenviou uma mensagem, você verá aqui.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 12.sp,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _service.fetchNotifications,
            color: AppTheme.primary,
            child: ListView.builder(
              padding: EdgeInsets.only(top: 8, bottom: bottomPadding + 90),
              itemCount: _service.notifications.length,
              itemBuilder: (context, index) {
                final notif = _service.notifications[index];
                return _NotificationTile(
                  notification: notif,
                  iconColor: _colorForType(notif.type),
                  icon: _iconForType(notif.type),
                  timeAgo: _timeAgo(notif.createdAt),
                  isProcessing: _processingIds.contains(notif.id),
                  onTap: () {
                    if (!notif.isRead) {
                      _service.markAsRead(notif.id);
                    }
                  },
                  onAcceptFriendRequest:
                      notif.type == NotificationType.friendRequest
                      ? () => _acceptFriendRequest(notif)
                      : null,
                  onDeclineFriendRequest:
                      notif.type == NotificationType.friendRequest
                      ? () => _declineFriendRequest(notif)
                      : null,
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// ─── Notification Tile ────────────────────────────────────────────────────────

class _NotificationTile extends StatelessWidget {
  final AppNotification notification;
  final IconData icon;
  final Color iconColor;
  final String timeAgo;
  final bool isProcessing;
  final VoidCallback onTap;
  final VoidCallback? onAcceptFriendRequest;
  final VoidCallback? onDeclineFriendRequest;

  const _NotificationTile({
    required this.notification,
    required this.icon,
    required this.iconColor,
    required this.timeAgo,
    required this.isProcessing,
    required this.onTap,
    this.onAcceptFriendRequest,
    this.onDeclineFriendRequest,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUnread = !notification.isRead;
    final isFriendRequest = notification.type == NotificationType.friendRequest;

    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        color: isUnread ? AppTheme.primary.withAlpha(12) : Colors.transparent,
        padding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: isFriendRequest ? 10 : 12,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar + type icon overlay
            Stack(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  backgroundImage:
                      (notification.actorAvatarUrl != null &&
                          notification.actorAvatarUrl!.isNotEmpty)
                      ? CachedNetworkImageProvider(notification.actorAvatarUrl!)
                      : null,
                  child:
                      (notification.actorAvatarUrl == null ||
                          notification.actorAvatarUrl!.isEmpty)
                      ? Icon(
                          Icons.person_rounded,
                          color: theme.colorScheme.onSurfaceVariant,
                          size: 24,
                        )
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: iconColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: theme.colorScheme.surface,
                        width: 1.5,
                      ),
                    ),
                    child: Icon(icon, size: 11, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: GoogleFonts.inter(
                            fontWeight: isUnread
                                ? FontWeight.w700
                                : FontWeight.w600,
                            fontSize: 13.sp,
                            color: theme.colorScheme.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        timeAgo,
                        style: GoogleFonts.inter(
                          fontSize: 10.sp,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    notification.body,
                    style: GoogleFonts.inter(
                      fontSize: 12.sp,
                      color: isUnread
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // Accept / Decline buttons for friend requests
                  if (isFriendRequest &&
                      onAcceptFriendRequest != null &&
                      onDeclineFriendRequest != null) ...[
                    const SizedBox(height: 10),
                    isProcessing
                        ? const SizedBox(
                            height: 28,
                            width: 28,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Row(
                            children: [
                              FilledButton(
                                onPressed: onAcceptFriendRequest,
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF4CAF50),
                                  minimumSize: const Size(80, 30),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: Text(
                                  'Aceitar',
                                  style: GoogleFonts.inter(
                                    fontSize: 11.sp,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                onPressed: onDeclineFriendRequest,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor:
                                      theme.colorScheme.onSurfaceVariant,
                                  side: BorderSide(
                                    color: theme.colorScheme.outlineVariant,
                                  ),
                                  minimumSize: const Size(80, 30),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: Text(
                                  'Recusar',
                                  style: GoogleFonts.inter(
                                    fontSize: 11.sp,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ],
                ],
              ),
            ),
            // Unread dot (only for non-friend-request notifications)
            if (isUnread && !isFriendRequest) ...[
              const SizedBox(width: 8),
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}