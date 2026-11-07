import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../services/supabase_service.dart';

class ActivityEvent {
  final String id;
  final ActivityEventType type;
  final String userName;
  final String description;
  final DateTime timestamp;

  const ActivityEvent({
    required this.id,
    required this.type,
    required this.userName,
    required this.description,
    required this.timestamp,
  });
}

enum ActivityEventType { login, message, friendRequest, post }

class AdminActivityTimelineWidget extends StatefulWidget {
  const AdminActivityTimelineWidget({super.key});

  @override
  State<AdminActivityTimelineWidget> createState() =>
      _AdminActivityTimelineWidgetState();
}

class _AdminActivityTimelineWidgetState
    extends State<AdminActivityTimelineWidget> {
  final List<ActivityEvent> _events = [];
  bool _isLoading = true;
  Timer? _pollTimer;

  // Realtime channels
  RealtimeChannel? _messagesChannel;
  RealtimeChannel? _friendshipsChannel;
  RealtimeChannel? _postsChannel;
  RealtimeChannel? _profilesChannel;

  final _client = SupabaseService.instance.client;

  @override
  void initState() {
    super.initState();
    _loadInitialEvents();
    _subscribeRealtime();
    // Poll every 10 seconds as fallback / refresh
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _loadInitialEvents(silent: true);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _messagesChannel?.unsubscribe();
    _friendshipsChannel?.unsubscribe();
    _postsChannel?.unsubscribe();
    _profilesChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadInitialEvents({bool silent = false}) async {
    if (!silent && mounted) setState(() => _isLoading = true);
    try {
      final since = DateTime.now().subtract(const Duration(hours: 24));
      final sinceStr = since.toUtc().toIso8601String();

      // Fetch recent logins (last_seen updated recently)
      final loginsRaw = await _client
          .from('user_profiles')
          .select('id, full_name, last_seen')
          .not('last_seen', 'is', null)
          .gte('last_seen', sinceStr)
          .order('last_seen', ascending: false)
          .limit(10);

      // Fetch recent messages
      final messagesRaw = await _client
          .from('messages')
          .select(
            'id, created_at, sender_id, user_profiles!messages_sender_id_fkey(full_name)',
          )
          .gte('created_at', sinceStr)
          .order('created_at', ascending: false)
          .limit(15);

      // Fetch recent friend requests
      final friendshipsRaw = await _client
          .from('friendships')
          .select(
            'id, created_at, status, requester_id, user_profiles!friendships_requester_id_fkey(full_name)',
          )
          .gte('created_at', sinceStr)
          .order('created_at', ascending: false)
          .limit(10);

      // Fetch recent posts
      final postsRaw = await _client
          .from('posts')
          .select(
            'id, created_at, author_id, content, user_profiles!posts_author_id_fkey(full_name)',
          )
          .gte('created_at', sinceStr)
          .order('created_at', ascending: false)
          .limit(10);

      final newEvents = <ActivityEvent>[];

      for (final row in loginsRaw as List) {
        final ts = row['last_seen'] != null
            ? DateTime.tryParse(row['last_seen'].toString())?.toLocal()
            : null;
        if (ts == null) continue;
        newEvents.add(
          ActivityEvent(
            id: 'login_${row['id']}',
            type: ActivityEventType.login,
            userName: row['full_name'] ?? 'Usuário',
            description: 'fez login',
            timestamp: ts,
          ),
        );
      }

      for (final row in messagesRaw as List) {
        final ts = row['created_at'] != null
            ? DateTime.tryParse(row['created_at'].toString())?.toLocal()
            : null;
        if (ts == null) continue;
        final profile = row['user_profiles'] as Map<String, dynamic>?;
        newEvents.add(
          ActivityEvent(
            id: 'msg_${row['id']}',
            type: ActivityEventType.message,
            userName: profile?['full_name'] ?? 'Usuário',
            description: 'enviou uma mensagem',
            timestamp: ts,
          ),
        );
      }

      for (final row in friendshipsRaw as List) {
        final ts = row['created_at'] != null
            ? DateTime.tryParse(row['created_at'].toString())?.toLocal()
            : null;
        if (ts == null) continue;
        final profile = row['user_profiles'] as Map<String, dynamic>?;
        final status = row['status'] as String? ?? 'pending';
        newEvents.add(
          ActivityEvent(
            id: 'friend_${row['id']}',
            type: ActivityEventType.friendRequest,
            userName: profile?['full_name'] ?? 'Usuário',
            description: status == 'accepted'
                ? 'aceitou pedido de amizade'
                : 'enviou pedido de amizade',
            timestamp: ts,
          ),
        );
      }

      for (final row in postsRaw as List) {
        final ts = row['created_at'] != null
            ? DateTime.tryParse(row['created_at'].toString())?.toLocal()
            : null;
        if (ts == null) continue;
        final profile = row['user_profiles'] as Map<String, dynamic>?;
        final content = row['content'] as String? ?? '';
        newEvents.add(
          ActivityEvent(
            id: 'post_${row['id']}',
            type: ActivityEventType.post,
            userName: profile?['full_name'] ?? 'Usuário',
            description:
                'publicou: ${content.length > 40 ? '${content.substring(0, 40)}…' : content}',
            timestamp: ts,
          ),
        );
      }

      // Sort by timestamp descending
      newEvents.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      if (mounted) {
        setState(() {
          _events
            ..clear()
            ..addAll(newEvents.take(50));
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _subscribeRealtime() {
    // Messages channel
    _messagesChannel = _client
        .channel('admin_timeline_messages')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) => _handleNewMessage(payload.newRecord),
        )
        .subscribe();

    // Friendships channel
    _friendshipsChannel = _client
        .channel('admin_timeline_friendships')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'friendships',
          callback: (payload) => _handleNewFriendship(payload.newRecord),
        )
        .subscribe();

    // Posts channel
    _postsChannel = _client
        .channel('admin_timeline_posts')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'posts',
          callback: (payload) => _handleNewPost(payload.newRecord),
        )
        .subscribe();

    // User profiles (last_seen updates = logins)
    _profilesChannel = _client
        .channel('admin_timeline_profiles')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'user_profiles',
          callback: (payload) => _handleProfileUpdate(payload.newRecord),
        )
        .subscribe();
  }

  void _handleNewMessage(Map<String, dynamic> record) {
    final senderId = record['sender_id'] as String?;
    if (senderId == null) return;
    _fetchUserName(senderId).then((name) {
      if (!mounted) return;
      _prependEvent(
        ActivityEvent(
          id: 'msg_${record['id']}',
          type: ActivityEventType.message,
          userName: name,
          description: 'enviou uma mensagem',
          timestamp: DateTime.now(),
        ),
      );
    });
  }

  void _handleNewFriendship(Map<String, dynamic> record) {
    final requesterId = record['requester_id'] as String?;
    if (requesterId == null) return;
    _fetchUserName(requesterId).then((name) {
      if (!mounted) return;
      _prependEvent(
        ActivityEvent(
          id: 'friend_${record['id']}',
          type: ActivityEventType.friendRequest,
          userName: name,
          description: 'enviou pedido de amizade',
          timestamp: DateTime.now(),
        ),
      );
    });
  }

  void _handleNewPost(Map<String, dynamic> record) {
    final authorId = record['author_id'] as String?;
    if (authorId == null) return;
    final content = record['content'] as String? ?? '';
    _fetchUserName(authorId).then((name) {
      if (!mounted) return;
      _prependEvent(
        ActivityEvent(
          id: 'post_${record['id']}',
          type: ActivityEventType.post,
          userName: name,
          description:
              'publicou: ${content.length > 40 ? '${content.substring(0, 40)}…' : content}',
          timestamp: DateTime.now(),
        ),
      );
    });
  }

  void _handleProfileUpdate(Map<String, dynamic> record) {
    final lastSeen = record['last_seen'];
    if (lastSeen == null) return;
    final ts = DateTime.tryParse(lastSeen.toString())?.toLocal();
    if (ts == null) return;
    // Only treat as login if last_seen was updated in the last 30 seconds
    if (DateTime.now().difference(ts).inSeconds > 30) return;
    final name = record['full_name'] as String? ?? 'Usuário';
    _prependEvent(
      ActivityEvent(
        id: 'login_${record['id']}_${ts.millisecondsSinceEpoch}',
        type: ActivityEventType.login,
        userName: name,
        description: 'fez login',
        timestamp: ts,
      ),
    );
  }

  Future<String> _fetchUserName(String userId) async {
    try {
      final data = await _client
          .from('user_profiles')
          .select('full_name')
          .eq('id', userId)
          .maybeSingle();
      return data?['full_name'] as String? ?? 'Usuário';
    } catch (_) {
      return 'Usuário';
    }
  }

  void _prependEvent(ActivityEvent event) {
    setState(() {
      // Avoid duplicates
      _events.removeWhere((e) => e.id == event.id);
      _events.insert(0, event);
      if (_events.length > 50) _events.removeLast();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF22C55E),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Atividade em Tempo Real',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E).withAlpha(26),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    'LIVE',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: const Color(0xFF22C55E),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Filter chips
          _FilterChipsRow(
            onFilterChanged: (filter) {
              // Handled internally in the list
            },
          ),
          const Divider(height: 1),
          // Timeline list
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_events.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.timeline_rounded,
                      size: 40,
                      color: theme.colorScheme.onSurfaceVariant.withAlpha(100),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Nenhuma atividade recente',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            _TimelineList(events: _events),
        ],
      ),
    );
  }
}

class _FilterChipsRow extends StatefulWidget {
  final ValueChanged<ActivityEventType?> onFilterChanged;
  const _FilterChipsRow({required this.onFilterChanged});

  @override
  State<_FilterChipsRow> createState() => _FilterChipsRowState();
}

class _FilterChipsRowState extends State<_FilterChipsRow> {
  ActivityEventType? _selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chips = [
      (null, 'Todos', Icons.all_inclusive_rounded),
      (ActivityEventType.login, 'Logins', Icons.login_rounded),
      (ActivityEventType.message, 'Mensagens', Icons.chat_bubble_rounded),
      (ActivityEventType.friendRequest, 'Amizades', Icons.people_rounded),
      (ActivityEventType.post, 'Posts', Icons.article_rounded),
    ];

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final (type, label, icon) = chips[i];
          final isSelected = _selected == type;
          return GestureDetector(
            onTap: () {
              setState(() => _selected = type);
              widget.onFilterChanged(type);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 12,
                    color: isSelected
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isSelected
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TimelineList extends StatefulWidget {
  final List<ActivityEvent> events;
  const _TimelineList({required this.events});

  @override
  State<_TimelineList> createState() => _TimelineListState();
}

class _TimelineListState extends State<_TimelineList> {
  ActivityEventType? _filter;

  List<ActivityEvent> get _filtered => _filter == null
      ? widget.events
      : widget.events.where((e) => e.type == _filter).toList();

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    if (filtered.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            'Nenhum evento nesta categoria',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: filtered.length > 30 ? 30 : filtered.length,
      itemBuilder: (context, index) {
        final event = filtered[index];
        final isLast =
            index == (filtered.length > 30 ? 29 : filtered.length - 1);
        return _TimelineItem(event: event, isLast: isLast);
      },
    );
  }
}

class _TimelineItem extends StatelessWidget {
  final ActivityEvent event;
  final bool isLast;

  const _TimelineItem({required this.event, required this.isLast});

  Color _typeColor(BuildContext context) {
    switch (event.type) {
      case ActivityEventType.login:
        return const Color(0xFF22C55E);
      case ActivityEventType.message:
        return const Color(0xFF3B82F6);
      case ActivityEventType.friendRequest:
        return const Color(0xFFA855F7);
      case ActivityEventType.post:
        return const Color(0xFFF59E0B);
    }
  }

  IconData _typeIcon() {
    switch (event.type) {
      case ActivityEventType.login:
        return Icons.login_rounded;
      case ActivityEventType.message:
        return Icons.chat_bubble_rounded;
      case ActivityEventType.friendRequest:
        return Icons.people_rounded;
      case ActivityEventType.post:
        return Icons.article_rounded;
    }
  }

  String _relativeTime() {
    final diff = DateTime.now().difference(event.timestamp);
    if (diff.inSeconds < 60) return 'agora';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m atrás';
    if (diff.inHours < 24) return '${diff.inHours}h atrás';
    return '${diff.inDays}d atrás';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _typeColor(context);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline line + dot
          SizedBox(
            width: 48,
            child: Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  margin: const EdgeInsets.only(top: 12, left: 10),
                  decoration: BoxDecoration(
                    color: color.withAlpha(31),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Icon(_typeIcon(), size: 14, color: color),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.only(left: 23),
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: event.userName,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                              TextSpan(
                                text: ' ${event.description}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _relativeTime(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant.withAlpha(
                            180,
                          ),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
