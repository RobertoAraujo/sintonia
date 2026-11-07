import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:sizer/sizer.dart';

import '../../services/notification_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';

// ─── Filter Enum ─────────────────────────────────────────────────────────────

enum NotificationFilter { all, friendRequests, messages, reports }

extension NotificationFilterLabel on NotificationFilter {
  String get label {
    switch (this) {
      case NotificationFilter.all:
        return 'Todas';
      case NotificationFilter.friendRequests:
        return 'Amizades';
      case NotificationFilter.messages:
        return 'Mensagens';
      case NotificationFilter.reports:
        return 'Atividades';
    }
  }

  IconData get icon {
    switch (this) {
      case NotificationFilter.all:
        return Icons.notifications_rounded;
      case NotificationFilter.friendRequests:
        return Icons.people_rounded;
      case NotificationFilter.messages:
        return Icons.message_rounded;
      case NotificationFilter.reports:
        return Icons.favorite_rounded;
    }
  }
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class NotificationArchiveScreen extends StatefulWidget {
  const NotificationArchiveScreen({super.key});

  @override
  State<NotificationArchiveScreen> createState() =>
      _NotificationArchiveScreenState();
}

class _NotificationArchiveScreenState extends State<NotificationArchiveScreen> {
  final NotificationService _service = NotificationService.instance;
  NotificationFilter _activeFilter = NotificationFilter.all;
  final Set<String> _selectedIds = {};
  bool _isSelectionMode = false;
  bool _isDeleting = false;
  bool _isMarkingRead = false;
  final Set<String> _processingIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _service.fetchNotifications();
    });
  }

  List<AppNotification> get _filteredNotifications {
    final all = _service.notifications;
    switch (_activeFilter) {
      case NotificationFilter.all:
        return all;
      case NotificationFilter.friendRequests:
        return all
            .where(
              (n) =>
                  n.type == NotificationType.friendRequest ||
                  n.type == NotificationType.friendAccepted,
            )
            .toList();
      case NotificationFilter.messages:
        return all.where((n) => n.type == NotificationType.message).toList();
      case NotificationFilter.reports:
        return all
            .where(
              (n) =>
                  n.type == NotificationType.like ||
                  n.type == NotificationType.comment,
            )
            .toList();
    }
  }

  // Group notifications by date label
  Map<String, List<AppNotification>> get _groupedNotifications {
    final result = <String, List<AppNotification>>{};
    for (final notif in _filteredNotifications) {
      final label = _dateGroupLabel(notif.createdAt);
      result.putIfAbsent(label, () => []).add(notif);
    }
    return result;
  }

  String _dateGroupLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final date = DateTime(dt.year, dt.month, dt.day);

    if (date == today) return 'Hoje';
    if (date == yesterday) return 'Ontem';
    final diff = today.difference(date).inDays;
    if (diff < 7) return 'Esta semana';
    if (diff < 30) return 'Este mês';
    return 'Mais antigo';
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Agora';
    if (diff.inMinutes < 60) return '${diff.inMinutes}min';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${(diff.inDays / 7).floor()}sem';
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
        return const Color(0xFF9C27B0);
    }
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _enterSelectionMode(String id) {
    setState(() {
      _isSelectionMode = true;
      _selectedIds.add(id);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedIds.clear();
    });
  }

  void _selectAll() {
    setState(() {
      _selectedIds.addAll(_filteredNotifications.map((n) => n.id));
    });
  }

  Future<void> _bulkMarkAsRead() async {
    if (_selectedIds.isEmpty || _isMarkingRead) return;
    setState(() => _isMarkingRead = true);
    try {
      final client = SupabaseService.instance.client;
      final uid = SupabaseService.instance.currentUserId;
      if (uid == null) return;
      await client
          .from('notifications')
          .update({'is_read': true})
          .inFilter('id', _selectedIds.toList())
          .eq('recipient_id', uid);
      await _service.fetchNotifications();
      if (mounted) {
        _exitSelectionMode();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Notificações marcadas como lidas'),
            backgroundColor: const Color(0xFF4CAF50),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.0),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('bulkMarkAsRead error: $e');
    } finally {
      if (mounted) setState(() => _isMarkingRead = false);
    }
  }

  Future<void> _bulkDelete() async {
    if (_selectedIds.isEmpty || _isDeleting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.0),
        ),
        title: Text(
          'Excluir notificações',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            fontSize: 15.sp,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        content: Text(
          'Excluir ${_selectedIds.length} notificação(ões) selecionada(s)? Esta ação não pode ser desfeita.',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12.sp,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancelar',
              style: GoogleFonts.plusJakartaSans(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10.0),
              ),
            ),
            child: Text(
              'Excluir',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _isDeleting = true);
    try {
      final client = SupabaseService.instance.client;
      final uid = SupabaseService.instance.currentUserId;
      if (uid == null) return;
      await client
          .from('notifications')
          .delete()
          .inFilter('id', _selectedIds.toList())
          .eq('recipient_id', uid);
      await _service.fetchNotifications();
      if (mounted) {
        _exitSelectionMode();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Notificações excluídas'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.0),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('bulkDelete error: $e');
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  Future<void> _acceptFriendRequest(AppNotification notif) async {
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
        ok = await SupabaseService.instance.acceptFriendRequest(
          match['id'] as String,
        );
      } else {
        ok = await SupabaseService.instance.acceptFriendRequest(
          notif.referenceId ?? notif.actorId,
        );
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
      appBar: _buildAppBar(theme),
      body: Column(
        children: [
          _buildFilterChips(theme),
          Expanded(
            child: ListenableBuilder(
              listenable: _service,
              builder: (context, _) {
                if (_service.isLoading && _service.notifications.isEmpty) {
                  return Center(
                    child: CircularProgressIndicator(color: AppTheme.primary),
                  );
                }

                if (_service.error != null && _service.notifications.isEmpty) {
                  return _buildErrorState(theme);
                }

                final grouped = _groupedNotifications;
                if (grouped.isEmpty) {
                  return _buildEmptyState(theme);
                }

                final groups = grouped.entries.toList();
                return RefreshIndicator(
                  onRefresh: _service.fetchNotifications,
                  color: AppTheme.primary,
                  child: ListView.builder(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPadding + 24),
                    itemCount: groups.length,
                    itemBuilder: (context, groupIndex) {
                      final group = groups[groupIndex];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildDateHeader(group.key, theme),
                          ...group.value.map(
                            (notif) => _ArchiveNotificationTile(
                              notification: notif,
                              icon: _iconForType(notif.type),
                              iconColor: _colorForType(notif.type),
                              timeAgo: _timeAgo(notif.createdAt),
                              isSelected: _selectedIds.contains(notif.id),
                              isSelectionMode: _isSelectionMode,
                              isProcessing: _processingIds.contains(notif.id),
                              onTap: () {
                                if (_isSelectionMode) {
                                  _toggleSelection(notif.id);
                                } else {
                                  if (!notif.isRead) {
                                    _service.markAsRead(notif.id);
                                  }
                                }
                              },
                              onLongPress: () {
                                if (!_isSelectionMode) {
                                  _enterSelectionMode(notif.id);
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
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: _isSelectionMode
          ? _buildBulkActionsBar(theme, bottomPadding)
          : null,
    );
  }

  PreferredSizeWidget _buildAppBar(ThemeData theme) {
    if (_isSelectionMode) {
      return AppBar(
        backgroundColor: AppTheme.primary.withAlpha(20),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: AppTheme.primary),
          onPressed: _exitSelectionMode,
        ),
        title: Text(
          '${_selectedIds.length} selecionada(s)',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            fontSize: 16.sp,
            color: AppTheme.primary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _selectAll,
            child: Text(
              'Selecionar tudo',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11.sp,
                color: AppTheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            thickness: 1,
            color: AppTheme.primary.withAlpha(40),
          ),
        ),
      );
    }

    return AppBar(
      backgroundColor: theme.colorScheme.surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      titleSpacing: 4,
      leading: IconButton(
        icon: Icon(
          Icons.arrow_back_ios_new_rounded,
          color: theme.colorScheme.onSurface,
          size: 20,
        ),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Arquivo de Notificações',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              fontSize: 15.sp,
              color: theme.colorScheme.onSurface,
            ),
          ),
          ListenableBuilder(
            listenable: _service,
            builder: (context, _) {
              final total = _filteredNotifications.length;
              return Text(
                '$total notificação(ões)',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10.sp,
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              );
            },
          ),
        ],
      ),
      actions: [
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
                    horizontal: 10,
                    vertical: 6,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20.0),
                  ),
                  backgroundColor: AppTheme.primary.withAlpha(20),
                ),
                child: Text(
                  'Ler todas',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10.sp,
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
    );
  }

  Widget _buildFilterChips(ThemeData theme) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: NotificationFilter.values.map((filter) {
          final isActive = _activeFilter == filter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _activeFilter = filter;
                  _exitSelectionMode();
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppTheme.primary
                      : theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(20.0),
                  border: Border.all(
                    color: isActive
                        ? AppTheme.primary
                        : theme.colorScheme.outlineVariant.withAlpha(80),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      filter.icon,
                      size: 14,
                      color: isActive
                          ? Colors.white
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      filter.label,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11.sp,
                        fontWeight: isActive
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: isActive
                            ? Colors.white
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDateHeader(String label, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.circular(2.0),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              fontSize: 12.sp,
              color: theme.colorScheme.onSurface,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Divider(
              color: theme.colorScheme.outlineVariant.withAlpha(60),
              thickness: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
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
            child: Icon(Icons.inbox_rounded, size: 44, color: AppTheme.primary),
          ),
          const SizedBox(height: 20),
          Text(
            'Nenhuma notificação',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              fontSize: 15.sp,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Não há notificações nesta categoria.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12.sp,
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(ThemeData theme) {
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
            style: GoogleFonts.plusJakartaSans(
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
            ),
            child: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }

  Widget _buildBulkActionsBar(ThemeData theme, double bottomPadding) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding + 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(60),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(30),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _isMarkingRead ? null : _bulkMarkAsRead,
              icon: _isMarkingRead
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.primary,
                      ),
                    )
                  : Icon(
                      Icons.done_all_rounded,
                      size: 16,
                      color: AppTheme.primary,
                    ),
              label: Text(
                'Marcar lidas',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppTheme.primary.withAlpha(120)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.0),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: _isDeleting ? null : _bulkDelete,
              icon: _isDeleting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.delete_rounded, size: 16),
              label: Text(
                'Excluir',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.0),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Archive Notification Tile ────────────────────────────────────────────────

class _ArchiveNotificationTile extends StatelessWidget {
  final AppNotification notification;
  final IconData icon;
  final Color iconColor;
  final String timeAgo;
  final bool isSelected;
  final bool isSelectionMode;
  final bool isProcessing;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onAcceptFriendRequest;
  final VoidCallback? onDeclineFriendRequest;

  const _ArchiveNotificationTile({
    required this.notification,
    required this.icon,
    required this.iconColor,
    required this.timeAgo,
    required this.isSelected,
    required this.isSelectionMode,
    required this.isProcessing,
    required this.onTap,
    required this.onLongPress,
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
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary.withAlpha(28)
              : isUnread
              ? AppTheme.primary.withAlpha(14)
              : theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16.0),
          border: Border.all(
            color: isSelected
                ? AppTheme.primary.withAlpha(100)
                : isUnread
                ? AppTheme.primary.withAlpha(40)
                : theme.colorScheme.outlineVariant.withAlpha(50),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(isSelected ? 30 : 18),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Selection checkbox or avatar
            if (isSelectionMode)
              Padding(
                padding: const EdgeInsets.only(right: 12, top: 4),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: isSelected ? AppTheme.primary : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.primary
                          : theme.colorScheme.outlineVariant,
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: Colors.white,
                        )
                      : null,
                ),
              ),
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
                          size: 22,
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
                        color: isSelected
                            ? AppTheme.primary.withAlpha(28)
                            : isUnread
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
                    child: Icon(icon, size: 10, color: Colors.white),
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: isUnread
                                ? FontWeight.w700
                                : FontWeight.w600,
                            fontSize: 12.sp,
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
                              width: 6,
                              height: 6,
                              margin: const EdgeInsets.only(right: 4, top: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          Text(
                            timeAgo,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10.sp,
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    notification.body,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.sp,
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
                      onDeclineFriendRequest != null &&
                      !isSelectionMode) ...[
                    const SizedBox(height: 10),
                    isProcessing
                        ? SizedBox(
                            height: 28,
                            width: 28,
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
                                    minimumSize: const Size(0, 32),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10.0),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: Text(
                                    'Aceitar',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11.sp,
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
                                    minimumSize: const Size(0, 32),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10.0),
                                    ),
                                  ),
                                  child: Text(
                                    'Recusar',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11.sp,
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
