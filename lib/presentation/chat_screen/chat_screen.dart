import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_export.dart';
import '../../services/supabase_service.dart';
import '../user_profile_screen/user_profile_screen.dart';
import './widgets/chat_detail_view.dart';
import './widgets/conversation_card_widget.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _openConversationId;
  bool _isLoadingConversations = true;
  bool _isLoadingGroups = true;

  final List<Map<String, dynamic>> _conversationsMaps = [];
  final List<Map<String, dynamic>> _groups = [];

  RealtimeChannel? _messagesChannel;
  RealtimeChannel? _profilesChannel;
  OverlayEntry? _notificationOverlay;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadConversations();
    _loadGroups();
    _subscribeToMessages();
    _subscribeToProfileChanges();
  }

  @override
  void dispose() {
    _notificationOverlay?.remove();
    _notificationOverlay = null;
    _messagesChannel?.unsubscribe();
    _profilesChannel?.unsubscribe();
    _tabController.dispose();
    super.dispose();
  }

  /// Subscribe to new messages in realtime so the conversation list
  /// updates its last-message preview and unread count instantly.
  void _subscribeToMessages() {
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) return;

    _messagesChannel = SupabaseService.instance.client
        .channel('chat_list_messages_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            final record = payload.newRecord;
            if (record.isEmpty || !mounted) return;

            final convId = record['conversation_id'] as String?;
            final senderId = record['sender_id'] as String?;
            final content = record['content'] as String? ?? '';
            final createdAt = record['created_at'];

            if (convId == null) return;

            // Show in-app notification if message is from another user
            // and this conversation is not currently open
            if (senderId != null &&
                senderId != uid &&
                _openConversationId != convId) {
              final idx = _conversationsMaps.indexWhere(
                (c) => c['id'] == convId,
              );
              final senderName = idx != -1
                  ? (_conversationsMaps[idx]['name'] as String? ?? 'Usuário')
                  : 'Usuário';
              _showInAppNotification(senderName, content, convId);
            }

            setState(() {
              final idx = _conversationsMaps.indexWhere(
                (c) => c['id'] == convId,
              );
              if (idx != -1) {
                _conversationsMaps[idx]['lastMessage'] = content;
                _conversationsMaps[idx]['timestamp'] = _timeAgo(
                  createdAt?.toString(),
                );

                // Increment unread count only if the message is from the
                // other user AND this conversation is not currently open.
                if (senderId != uid && _openConversationId != convId) {
                  final current =
                      _conversationsMaps[idx]['unreadCount'] as int? ?? 0;
                  _conversationsMaps[idx]['unreadCount'] = current + 1;
                }

                // Bubble the updated conversation to the top of the list
                final updated = _conversationsMaps.removeAt(idx);
                _conversationsMaps.insert(0, updated);
              } else {
                // Unknown conversation — reload the full list
                _loadConversations();
              }
            });
          },
        )
        .subscribe();
  }

  /// Shows a floating notification banner at the top of the screen
  /// when a new message arrives from another user.
  void _showInAppNotification(
    String senderName,
    String content,
    String convId,
  ) {
    if (!mounted) return;

    // Dismiss any existing notification
    _notificationOverlay?.remove();
    _notificationOverlay = null;

    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (ctx) => _InAppNotificationBanner(
        senderName: senderName,
        message: content,
        onTap: () {
          entry.remove();
          _notificationOverlay = null;
          // Open the conversation
          final conv = _conversationsMaps.firstWhere(
            (c) => c['id'] == convId,
            orElse: () => {'id': convId, 'name': senderName},
          );
          if (mounted) _openConversation(conv);
        },
        onDismiss: () {
          entry.remove();
          _notificationOverlay = null;
        },
      ),
    );

    _notificationOverlay = entry;
    overlay.insert(entry);

    // Auto-dismiss after 4 seconds
    Future.delayed(const Duration(seconds: 4), () {
      if (_notificationOverlay == entry) {
        try {
          entry.remove();
        } catch (_) {}
        _notificationOverlay = null;
      }
    });
  }

  /// Subscribe to user_profiles Realtime changes.
  /// When a contact updates their avatar, refresh it instantly in the list.
  void _subscribeToProfileChanges() {
    _profilesChannel = SupabaseService.instance.client
        .channel('chat_list_profiles')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'user_profiles',
          callback: (payload) {
            final record = payload.newRecord;
            if (record.isEmpty || !mounted) return;
            final updatedId = record['id'] as String?;
            if (updatedId == null) return;
            final newAvatar = record['avatar_url'] as String? ?? '';
            final newName = (record['full_name'] as String?)?.isNotEmpty == true
                ? record['full_name'] as String
                : (record['username'] as String? ?? '');
            setState(() {
              for (int i = 0; i < _conversationsMaps.length; i++) {
                if (_conversationsMaps[i]['userId'] == updatedId) {
                  _conversationsMaps[i]['imageUrl'] = newAvatar;
                  if (newName.isNotEmpty) {
                    _conversationsMaps[i]['name'] = newName;
                  }
                }
              }
            });
          },
        )
        .subscribe();
  }

  Future<void> _loadConversations() async {
    try {
      final rows = await SupabaseService.instance.fetchConversations();
      if (!mounted) return;
      final mapped = <Map<String, dynamic>>[];
      for (final row in rows) {
        final conv = row['conversation'] as Map<String, dynamic>? ?? {};
        final isGroup = conv['is_group'] as bool? ?? false;
        final convId = conv['id'] ?? row['conversation_id'] ?? '';

        // Use pre-fetched profile data from the enriched row
        final otherUserId = row['_otherUserId'] as String?;
        final otherName = row['_otherName'] as String? ?? 'Conversa';
        final otherImageUrl = row['_otherAvatarUrl'] as String? ?? '';

        debugPrint(
          'DEBUG CHAT -> Usuário: $otherName | AvatarURL: $otherImageUrl',
        );

        mapped.add({
          'id': convId,
          'userId': otherUserId,
          'name': otherName,
          'imageUrl': otherImageUrl,
          'imageSemantic': 'Foto de $otherName',
          'lastMessage': conv['last_message'] ?? '',
          'timestamp': _timeAgo(conv['last_message_at']),
          'unreadCount': row['unread_count'] ?? 0,
          'isOnline': false,
          'isGroup': isGroup,
          'isNewRequest': false,
          'neurodivType': null,
        });
      }
      setState(() {
        _conversationsMaps
          ..clear()
          ..addAll(mapped);
        _isLoadingConversations = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingConversations = false);
    }
  }

  Future<void> _loadGroups() async {
    try {
      final rows = await SupabaseService.instance.fetchGroups();
      if (!mounted) return;
      final mapped = rows
          .map(
            (g) => {
              'id': g['id'] ?? '',
              'name': g['name'] ?? '',
              'description': g['description'] ?? '',
              'members': g['members_count'] ?? 0,
              'imageUrl': g['avatar_url'] ?? '',
              'imageSemantic': 'Imagem do grupo ${g['name'] ?? ''}',
            },
          )
          .toList();
      setState(() {
        _groups
          ..clear()
          ..addAll(mapped);
        _isLoadingGroups = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingGroups = false);
    }
  }

  String _timeAgo(dynamic ts) {
    if (ts == null) return '';
    try {
      final dt = DateTime.parse(ts.toString()).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 60) return '${diff.inMinutes}min';
      if (diff.inHours < 24) return '${diff.inHours}h';
      return '${diff.inDays}d';
    } catch (_) {
      return '';
    }
  }

  List<Map<String, dynamic>> get _allConversations =>
      _conversationsMaps.where((c) => c['isGroup'] != true).toList();

  List<Map<String, dynamic>> get _newRequests => _conversationsMaps
      .where((c) => c['isNewRequest'] == true && c['isGroup'] != true)
      .toList();

  int get _totalUnread =>
      _conversationsMaps.fold(0, (sum, c) => sum + (c['unreadCount'] as int));

  void _openConversation(Map<String, dynamic> conv) {
    setState(() {
      _openConversationId = conv['id'] as String;
      final idx = _conversationsMaps.indexWhere((c) => c['id'] == conv['id']);
      if (idx != -1) _conversationsMaps[idx]['unreadCount'] = 0;
    });
  }

  void _openUserProfile(String? userId) {
    if (userId == null) return;
    SupabaseService.instance.fetchUserProfile(userId).then((profile) {
      if (!mounted) return;
      final userData = profile != null
          ? {
              'id': profile['id'] ?? userId,
              'name': profile['full_name'] ?? 'Usuário',
              'username': '@${profile['username'] ?? ''}',
              'bio': profile['bio'] ?? '',
              'neurodivType': profile['neurodiv_type'] ?? '',
              'avatarUrl': profile['avatar_url'] ?? '',
              'avatarSemantic': 'Foto de ${profile['full_name'] ?? 'Usuário'}',
              'hyperfocuses': [],
              'interests': [],
              'friendsCount': 0,
              'postsCount': 0,
              'compatScore': 0,
              'isMe': false,
            }
          : {
              'id': userId,
              'name': 'Usuário',
              'avatarUrl': '',
              'avatarSemantic': '',
            };
      Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (_, animation, __) =>
              UserProfileScreen(userData: userData),
          transitionsBuilder: (_, animation, __, child) => SlideTransition(
            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                .animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
            child: child,
          ),
          transitionDuration: const Duration(milliseconds: 300),
        ),
      );
    });
  }

  void _acceptRequest(String convId) {
    setState(() {
      final idx = _conversationsMaps.indexWhere((c) => c['id'] == convId);
      if (idx != -1) _conversationsMaps[idx]['isNewRequest'] = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Solicitação aceita! 🎉'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppTheme.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _declineRequest(String convId) {
    setState(() => _conversationsMaps.removeWhere((c) => c['id'] == convId));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    // With extendBody: true, padding.bottom already includes the full nav bar height.
    final listBottomPadding = bottomPadding + 16.0;

    if (_openConversationId != null) {
      final conv = _conversationsMaps.firstWhere(
        (c) => c['id'] == _openConversationId,
        orElse: () => {'id': _openConversationId, 'name': 'Conversa'},
      );
      return ChatDetailView(
        conversation: conv,
        onBack: () => setState(() => _openConversationId = null),
        onAvatarTap: () => _openUserProfile(conv['userId'] as String?),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showNewConversationModal,
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.edit_rounded),
        label: const Text(
          'Nova Mensagem',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Mensagens', style: theme.textTheme.headlineSmall),
                        if (_totalUnread > 0)
                          Text(
                            '$_totalUnread não lidas',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.search_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.primary.withAlpha(20),
                      foregroundColor: AppTheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: _buildConversationsTab(theme, listBottomPadding)),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationsTab(ThemeData theme, double bottomPadding) {
    if (_isLoadingConversations) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }
    final requests = _newRequests;
    final all = _allConversations;

    if (all.isEmpty && requests.isEmpty) {
      return _buildEmptyState(
        theme,
        'Nenhuma conversa ainda',
        Icons.chat_bubble_outline_rounded,
      );
    }

    return ListView(
      padding: EdgeInsets.only(bottom: bottomPadding),
      children: [
        if (requests.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Row(
              children: [
                Text(
                  'Solicitações',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withAlpha(20),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    '${requests.length}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppTheme.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...requests.map(
            (conv) => _RequestConvCard(
              conv: conv,
              onAccept: () => _acceptRequest(conv['id'] as String),
              onDecline: () => _declineRequest(conv['id'] as String),
              onTap: () => _openConversation(conv),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              'Conversas',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
        ...all
            .where((c) => c['isNewRequest'] != true)
            .map(
              (conv) => ConversationCardWidget(
                conversation: conv,
                onTap: () => _openConversation(conv),
              ),
            ),
      ],
    );
  }

  Widget _buildGroupsTab(ThemeData theme, double bottomPadding) {
    if (_isLoadingGroups) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }
    if (_groups.isEmpty) {
      return _buildEmptyState(
        theme,
        'Nenhum grupo encontrado',
        Icons.group_outlined,
      );
    }
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding),
      itemCount: _groups.length,
      itemBuilder: (context, index) {
        final group = _groups[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading:
                group['imageUrl'] != null &&
                    (group['imageUrl'] as String).isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CustomImageWidget(
                      imageUrl: group['imageUrl'] as String,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      semanticLabel: group['imageSemantic'] as String,
                    ),
                  )
                : Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.group_rounded,
                      color: AppTheme.primary,
                    ),
                  ),
            title: Text(
              group['name'] as String,
              style: theme.textTheme.titleSmall,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((group['description'] as String).isNotEmpty)
                  Text(
                    group['description'] as String,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                Text(
                  '${group['members']} membros',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {},
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(ThemeData theme, String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 56, color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 12),
          Text(
            message,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  void _showNewConversationModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _NewConversationSheet(
        onUserSelected: (userId, name, avatarUrl) {
          Navigator.pop(ctx);
          SupabaseService.instance.createOrGetDirectConversation(userId).then((
            convId,
          ) {
            if (convId == null || !mounted) return;
            final existing = _conversationsMaps.firstWhere(
              (c) => c['id'] == convId,
              orElse: () => <String, dynamic>{},
            );
            if (existing.isNotEmpty) {
              _openConversation(existing);
            } else {
              final newConv = {
                'id': convId,
                'userId': userId,
                'name': name,
                'imageUrl': avatarUrl,
                'imageSemantic': 'Foto de $name',
                'lastMessage': 'Iniciar conversa...',
                'timestamp': 'Agora',
                'unreadCount': 0,
                'isOnline': false,
                'isGroup': false,
                'isNewRequest': false,
                'neurodivType': null,
              };
              setState(() => _conversationsMaps.insert(0, newConv));
              _openConversation(newConv);
            }
          });
        },
      ),
    );
  }
}

class _RequestConvCard extends StatelessWidget {
  final Map<String, dynamic> conv;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onTap;

  const _RequestConvCard({
    required this.conv,
    required this.onAccept,
    required this.onDecline,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.primary.withAlpha(8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withAlpha(40)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        onTap: onTap,
        leading: CircleAvatar(
          radius: 24,
          backgroundImage: (conv['imageUrl'] as String).isNotEmpty
              ? NetworkImage(conv['imageUrl'] as String)
              : null,
          backgroundColor: AppTheme.primaryContainer,
          child: (conv['imageUrl'] as String).isEmpty
              ? Text(
                  (conv['name'] as String).isNotEmpty
                      ? (conv['name'] as String)[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                )
              : null,
        ),
        title: Text(conv['name'] as String, style: theme.textTheme.titleSmall),
        subtitle: Text(
          conv['lastMessage'] as String,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: onDecline,
              icon: const Icon(Icons.close_rounded, size: 20),
              style: IconButton.styleFrom(
                backgroundColor: AppTheme.error.withAlpha(20),
                foregroundColor: AppTheme.error,
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              onPressed: onAccept,
              icon: const Icon(Icons.check_rounded, size: 20),
              style: IconButton.styleFrom(
                backgroundColor: AppTheme.primary.withAlpha(20),
                foregroundColor: AppTheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewConversationSheet extends StatefulWidget {
  final void Function(String userId, String name, String avatarUrl)
  onUserSelected;
  const _NewConversationSheet({required this.onUserSelected});

  @override
  State<_NewConversationSheet> createState() => _NewConversationSheetState();
}

class _NewConversationSheetState extends State<_NewConversationSheet> {
  final _ctrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _isSearching = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _isSearching = true);
    final users = await SupabaseService.instance.searchUsers(q.trim());
    if (mounted) {
      setState(() {
        _results = users;
        _isSearching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 400,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text('Nova Conversa', style: theme.textTheme.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              onChanged: _search,
              decoration: InputDecoration(
                hintText: 'Buscar usuário...',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _isSearching
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary),
                  )
                : _results.isEmpty
                ? Center(
                    child: Text(
                      _ctrl.text.isEmpty
                          ? 'Digite para buscar'
                          : 'Nenhum usuário encontrado',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _results.length,
                    itemBuilder: (_, i) {
                      final user = _results[i];
                      final uid = SupabaseService.instance.currentUserId;
                      if (user['id'] == uid) return const SizedBox.shrink();
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage:
                              (user['avatar_url'] as String? ?? '').isNotEmpty
                              ? NetworkImage(user['avatar_url'] as String)
                              : null,
                          backgroundColor: AppTheme.primaryContainer,
                          child: (user['avatar_url'] as String? ?? '').isEmpty
                              ? Text(
                                  (user['full_name'] as String? ?? '?')[0]
                                      .toUpperCase(),
                                  style: const TextStyle(
                                    color: AppTheme.primary,
                                  ),
                                )
                              : null,
                        ),
                        title: Text(user['full_name'] as String? ?? 'Usuário'),
                        subtitle: Text('@${user['username'] as String? ?? ''}'),
                        onTap: () => widget.onUserSelected(
                          user['id'] as String,
                          user['full_name'] as String? ?? 'Usuário',
                          user['avatar_url'] as String? ?? '',
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Floating in-app notification banner widget
class _InAppNotificationBanner extends StatefulWidget {
  final String senderName;
  final String message;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _InAppNotificationBanner({
    required this.senderName,
    required this.message,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  State<_InAppNotificationBanner> createState() =>
      _InAppNotificationBannerState();
}

class _InAppNotificationBannerState extends State<_InAppNotificationBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<Offset> _slideAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fadeAnim = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slideAnim,
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: widget.onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.inverseSurface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(40),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          widget.senderName.isNotEmpty
                              ? widget.senderName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.senderName,
                            style: TextStyle(
                              color: theme.colorScheme.onInverseSurface,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.message.isEmpty
                                ? 'Nova mensagem'
                                : widget.message,
                            style: TextStyle(
                              color: theme.colorScheme.onInverseSurface
                                  .withAlpha(200),
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: widget.onDismiss,
                      icon: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: theme.colorScheme.onInverseSurface.withAlpha(
                          180,
                        ),
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
