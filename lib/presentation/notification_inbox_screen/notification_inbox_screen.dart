import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:sizer/sizer.dart';
import 'package:go_router/go_router.dart';
import '../../routes/app_routes.dart';

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
  final Set<String> _processingIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _service.fetchNotifications().then((_) {
        // Mark all as read once notifications are loaded
        if (_service.socialUnreadCount > 0) {
          _service.markAllAsRead();
        }
      });
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
      case NotificationType.postEdit:
        return Icons.edit_rounded;
      case NotificationType.report:
        return Icons.flag_rounded;
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
      case NotificationType.postEdit:
        return const Color(0xFFFF9800);
      case NotificationType.report:
        return const Color(0xFFF44336);
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
      final friendshipId = notif.referenceId ?? notif.actorId;
      final requests = await SupabaseService.instance.fetchFriendRequests();
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
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.0),
            ),
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
      final requests = await SupabaseService.instance.fetchFriendRequests();
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
        titleSpacing: 20,
        title: Text(
          'Notificações',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 18.sp,
            color: theme.colorScheme.onSurface,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.history_rounded,
              color: theme.colorScheme.onSurfaceVariant,
              size: 22,
            ),
            tooltip: 'Arquivo',
            onPressed: () => context.push(AppRoutes.notificationArchiveScreen),
          ),
          ListenableBuilder(
            listenable: _service,
            builder: (context, _) {
              if (_service.unreadCount == 0) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(right: 12.0),
                child: TextButton(
                  onPressed: _service.markAllAsRead,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20.0),
                    ),
                    backgroundColor: AppTheme.primary.withAlpha(20),
                  ),
                  child: Text(
                    'Marcar todas',
                    style: GoogleFonts.inter(
                      fontSize: 11.sp,
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            thickness: 1,
            color: theme.colorScheme.outlineVariant.withAlpha(60),
          ),
        ),
      ),
      body: ListenableBuilder(
        listenable: _service,
        builder: (context, _) {
          if (_service.isLoading && _service.notifications.isEmpty) {
            return Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            );
          }

          if (_service.error != null && _service.notifications.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.error.withAlpha(20),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.error_outline_rounded,
                      size: 36,
                      color: theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Erro ao carregar notificações',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      fontSize: 14.sp,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _service.fetchNotifications,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
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
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withAlpha(18),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.notifications_none_rounded,
                      size: 44,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Nenhuma notificação',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 16.sp,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Quando alguém curtir, comentar ou\nenviou uma mensagem, você verá aqui.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 12.sp,
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.5,
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
              padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding + 90),
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
                    if (!notif.isRead) _service.markAsRead(notif.id);
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

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: isUnread
              ? AppTheme.primary.withAlpha(14)
              : theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16.0),
          border: Border.all(
            color: isUnread
                ? AppTheme.primary.withAlpha(40)
                : theme.colorScheme.outlineVariant.withAlpha(50),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(18),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar + type icon overlay
            Stack(
              children: [
                CircleAvatar(
                  radius: 26,
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
                          size: 26,
                        )
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: iconColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isUnread
                            ? AppTheme.primary.withAlpha(14)
                            : theme.colorScheme.surfaceContainerLow,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: iconColor.withAlpha(60),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(icon, size: 11, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 14),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                            height: 1.3,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isUnread && !isFriendRequest)
                            Container(
                              width: 7,
                              height: 7,
                              margin: const EdgeInsets.only(right: 5, top: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          Text(
                            timeAgo,
                            style: GoogleFonts.inter(
                              fontSize: 10.sp,
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification.body,
                    style: GoogleFonts.inter(
                      fontSize: 12.sp,
                      color: isUnread
                          ? theme.colorScheme.onSurface.withAlpha(200)
                          : theme.colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // Accept / Decline buttons for friend requests
                  if (isFriendRequest &&
                      onAcceptFriendRequest != null &&
                      onDeclineFriendRequest != null) ...[
                    const SizedBox(height: 12),
                    isProcessing
                        ? SizedBox(
                            height: 32,
                            width: 32,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: AppTheme.primary,
                            ),
                          )
                        : Row(
                            children: [
                              Expanded(
                                child: FilledButton(
                                  onPressed: onAcceptFriendRequest,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF4CAF50),
                                    minimumSize: const Size(0, 36),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10.0),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: Text(
                                    'Aceitar',
                                    style: GoogleFonts.inter(
                                      fontSize: 12.sp,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: onDeclineFriendRequest,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor:
                                        theme.colorScheme.onSurfaceVariant,
                                    side: BorderSide(
                                      color: theme.colorScheme.outlineVariant
                                          .withAlpha(120),
                                    ),
                                    minimumSize: const Size(0, 36),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10.0),
                                    ),
                                  ),
                                  child: Text(
                                    'Recusar',
                                    style: GoogleFonts.inter(
                                      fontSize: 12.sp,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
