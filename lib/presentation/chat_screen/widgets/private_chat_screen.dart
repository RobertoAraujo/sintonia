import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/app_export.dart';
import '../../../services/supabase_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/report_content_dialog.dart';
import '../../user_profile_screen/user_profile_screen.dart';
import '../../../widgets/user_avatar_widget.dart';

/// Full-screen real-time private chat using Supabase Realtime stream.
/// Uses StreamBuilder so messages appear instantly without manual polling.
class PrivateChatScreen extends StatefulWidget {
  final String chatId;
  final String otherUserId;
  final String otherUserName;
  final String otherUserAvatar;
  final String otherUserAvatarSemantic;

  const PrivateChatScreen({
    super.key,
    required this.chatId,
    required this.otherUserId,
    required this.otherUserName,
    required this.otherUserAvatar,
    required this.otherUserAvatarSemantic,
  });

  @override
  State<PrivateChatScreen> createState() => _PrivateChatScreenState();
}

class _PrivateChatScreenState extends State<PrivateChatScreen> {
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  late final Stream<List<Map<String, dynamic>>> _messagesStream;

  bool _isSending = false;
  int _previousMessageCount = 0;

  // Recipient enriched data
  String _recipientName = '';
  String _recipientAvatar = '';
  String? _recipientPetPhotoUrl;
  bool _isLoadingRecipient = false;

  // Online presence & typing
  bool _isRecipientOnline = false;
  bool _isRecipientTyping = false;
  RealtimeChannel? _presenceChannel;
  RealtimeChannel? _profileChannel;

  // Typing debounce
  Timer? _typingTimer;
  bool _iAmTyping = false;

  String get _myId => SupabaseService.instance.currentUserId ?? '';

  @override
  void initState() {
    super.initState();
    _recipientName = widget.otherUserName;
    _recipientAvatar = widget.otherUserAvatar;

    _messagesStream = SupabaseService.instance.client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', widget.chatId)
        .order('created_at', ascending: true)
        .map((rows) => rows.cast<Map<String, dynamic>>());

    _markAsRead();

    // Always fetch the recipient profile to ensure avatar_url and name are
    // up-to-date. This fixes the missing avatar bug when the caller passes
    // an empty string for otherUserAvatar.
    _fetchRecipientProfile();

    _subscribePresence();
    _subscribeProfileChanges();
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _presenceChannel?.unsubscribe();
    _profileChannel?.unsubscribe();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Presence & Typing ─────────────────────────────────────────────────────

  void _subscribePresence() {
    final channelName = 'chat_presence_${widget.chatId}';
    _presenceChannel = SupabaseService.instance.client.channel(channelName);

    _presenceChannel!
        .onPresenceSync((payload) {
          _updatePresenceState();
        })
        .onPresenceJoin((payload) {
          _updatePresenceState();
        })
        .onPresenceLeave((payload) {
          _updatePresenceState();
        })
        .onBroadcast(
          event: 'typing',
          callback: (payload) {
            final senderId = payload['user_id'] as String?;
            if (senderId != null && senderId != _myId) {
              final isTyping = payload['is_typing'] as bool? ?? false;
              if (mounted) {
                setState(() => _isRecipientTyping = isTyping);
              }
              // Auto-clear typing after 4 seconds if no update
              if (isTyping) {
                Future.delayed(const Duration(seconds: 4), () {
                  if (mounted) setState(() => _isRecipientTyping = false);
                });
              }
            }
          },
        )
        .subscribe((status, [error]) async {
          if (status == RealtimeSubscribeStatus.subscribed) {
            await _presenceChannel!.track({
              'user_id': _myId,
              'online_at': DateTime.now().toIso8601String(),
            });
          }
        });
  }

  void _updatePresenceState() {
    final presenceState = _presenceChannel?.presenceState() ?? {};
    bool recipientOnline = false;
    for (final entry in (presenceState as Map).entries) {
      final presences = entry.value;
      if (presences is List) {
        for (final p in presences) {
          if (p is Map) {
            final userId = p['user_id'] as String?;
            if (userId == widget.otherUserId) {
              recipientOnline = true;
              break;
            }
          }
        }
      }
      if (recipientOnline) break;
    }
    if (mounted) setState(() => _isRecipientOnline = recipientOnline);
  }

  /// Subscribe to user_profiles Realtime changes for the recipient.
  /// When they update their avatar, refresh it instantly.
  void _subscribeProfileChanges() {
    _profileChannel = SupabaseService.instance.client
        .channel('profile_changes_${widget.otherUserId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'user_profiles',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.otherUserId,
          ),
          callback: (payload) {
            final record = payload.newRecord;
            if (record.isEmpty || !mounted) return;
            final newAvatar = record['avatar_url'] as String? ?? '';
            final newName = (record['full_name'] as String?)?.isNotEmpty == true
                ? record['full_name'] as String
                : (record['username'] as String? ?? _recipientName);
            debugPrint(
              'Realtime profile update -> $newName | avatar: $newAvatar',
            );
            setState(() {
              _recipientAvatar = newAvatar;
              _recipientName = newName;
            });
          },
        )
        .subscribe();
  }

  void _onInputChanged(String value) {
    setState(() {});
    final isTyping = value.trim().isNotEmpty;
    if (isTyping != _iAmTyping) {
      _iAmTyping = isTyping;
      _broadcastTyping(isTyping);
    }
    if (isTyping) {
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 3), () {
        _iAmTyping = false;
        _broadcastTyping(false);
      });
    }
  }

  void _broadcastTyping(bool isTyping) {
    _presenceChannel?.sendBroadcastMessage(
      event: 'typing',
      payload: {'user_id': _myId, 'is_typing': isTyping},
    );
  }

  // ── Profile loading ───────────────────────────────────────────────────────

  Future<void> _fetchRecipientProfile() async {
    setState(() => _isLoadingRecipient = true);
    try {
      final profile = await SupabaseService.instance.client
          .from('user_profiles')
          .select('id, full_name, username, avatar_url, active_pet_id')
          .eq('id', widget.otherUserId)
          .maybeSingle();
      if (profile != null && mounted) {
        final name = (profile['full_name'] as String?)?.isNotEmpty == true
            ? profile['full_name'] as String
            : (profile['username'] as String? ?? 'Usuário');
        final avatarUrl = profile['avatar_url'] as String? ?? '';
        debugPrint('DEBUG CHAT -> Usuário: $name | AvatarURL: $avatarUrl');
        setState(() {
          _recipientName = name;
          _recipientAvatar = avatarUrl;
          _isLoadingRecipient = false;
        });
        final activePetId = profile['active_pet_id'] as String?;
        if (activePetId != null) _fetchPetPhoto(activePetId);
      } else {
        if (mounted) setState(() => _isLoadingRecipient = false);
      }
    } catch (e) {
      debugPrint('_fetchRecipientProfile error: $e');
      if (mounted) setState(() => _isLoadingRecipient = false);
    }
  }

  Future<void> _fetchRecipientPet() async {
    try {
      final profile = await SupabaseService.instance.client
          .from('profiles')
          .select('active_pet_id')
          .eq('id', widget.otherUserId)
          .maybeSingle();
      if (profile != null) {
        final activePetId = profile['active_pet_id'] as String?;
        if (activePetId != null) _fetchPetPhoto(activePetId);
      }
    } catch (_) {}
  }

  Future<void> _fetchPetPhoto(String petId) async {
    try {
      final pet = await SupabaseService.instance.client
          .from('pets')
          .select('photo_url')
          .eq('id', petId)
          .maybeSingle();
      if (pet != null && mounted) {
        final photoUrl = pet['photo_url'] as String?;
        if (photoUrl != null && photoUrl.isNotEmpty) {
          setState(() => _recipientPetPhotoUrl = photoUrl);
        }
      }
    } catch (_) {}
  }

  void _navigateToRecipientProfile() {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, animation, __) => UserProfileScreen(
          userData: {
            'id': widget.otherUserId,
            'name': _recipientName,
            'avatarUrl': _recipientAvatar,
            'avatarSemantic': 'Foto de $_recipientName',
            'username': '',
            'bio': '',
            'neurodivType': '',
            'hyperfocuses': [],
            'interests': [],
            'friendsCount': 0,
            'postsCount': 0,
            'compatScore': 0,
            'isMe': false,
          },
        ),
        transitionsBuilder: (_, animation, __, child) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
              .animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  // ── Send message ─────────────────────────────────────────────────────────

  Future<void> _sendMessage() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _isSending) return;

    // Session guard — ensure user is authenticated before sending
    final currentUser = SupabaseService.instance.currentUser;
    if (currentUser == null || currentUser.id.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sessão expirada. Faça login novamente.'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final senderId = currentUser.id;

    // Stop typing indicator
    _typingTimer?.cancel();
    _iAmTyping = false;
    _broadcastTyping(false);

    setState(() {
      _inputCtrl.clear();
      _isSending = true;
    });

    try {
      await SupabaseService.instance.client.from('messages').insert({
        'conversation_id': widget.chatId,
        'sender_id': senderId,
        'receiver_id': widget.otherUserId,
        'content': text,
        'is_read': false,
      });
    } catch (e) {
      debugPrint('_sendMessage error: $e');
      if (mounted) {
        // Restore the text so user can retry
        _inputCtrl.text = text;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Falha ao enviar mensagem. Tente novamente.'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade600,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  // ── Mark messages as read ─────────────────────────────────────────────────

  Future<void> _markAsRead() async {
    try {
      await SupabaseService.instance.client
          .from('messages')
          .update({'is_read': true})
          .eq('conversation_id', widget.chatId)
          .eq('receiver_id', _myId)
          .eq('is_read', false);
    } catch (_) {}
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _formatTime(String? createdAt) {
    if (createdAt == null) return '';
    try {
      final dt = DateTime.parse(createdAt).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 18,
            color: theme.colorScheme.onSurface,
          ),
        ),
        title: GestureDetector(
          onTap: _navigateToRecipientProfile,
          child: Row(
            children: [
              // Avatar with online dot + pet badge
              Stack(
                clipBehavior: Clip.none,
                children: [
                  UserAvatar(
                    avatarUrl: _recipientAvatar.isNotEmpty
                        ? _recipientAvatar
                        : null,
                    displayName: _recipientName,
                    radius: 18,
                  ),
                  // Online presence dot
                  if (_isRecipientOnline)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          color: AppTheme.success,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.colorScheme.surface,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  // Pet badge
                  if (_recipientPetPhotoUrl != null)
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.colorScheme.surface,
                            width: 1.5,
                          ),
                        ),
                        child: ClipOval(
                          child: Image.network(
                            _recipientPetPhotoUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.pets_rounded,
                              size: 10,
                              color: Colors.brown,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _isLoadingRecipient
                        ? Container(
                            width: 100,
                            height: 14,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.outlineVariant.withAlpha(
                                80,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          )
                        : Text(
                            _recipientName,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                    // Typing or online status
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: _isRecipientTyping
                          ? _TypingIndicator(key: const ValueKey('typing'))
                          : Text(
                              key: const ValueKey('status'),
                              _isRecipientOnline ? 'Online' : 'Offline',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: _isRecipientOnline
                                    ? AppTheme.success
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: theme.colorScheme.outlineVariant),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert_rounded,
              color: theme.colorScheme.onSurface,
              size: 22,
            ),
            onSelected: (value) {
              if (value == 'report') {
                showReportDialog(
                  context,
                  contentType: 'profile',
                  reportedUserId: widget.otherUserId,
                );
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem<String>(
                value: 'report',
                child: Row(
                  children: [
                    Icon(Icons.flag_outlined, color: Colors.red),
                    SizedBox(width: 12),
                    Text(
                      'Denunciar usuário',
                      style: TextStyle(color: Colors.red),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Messages list via StreamBuilder ───────────────────────────────
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _messagesStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data ?? [];

                if (messages.length > _previousMessageCount) {
                  _previousMessageCount = messages.length;
                  _scrollToBottom();
                  if (messages.isNotEmpty) _markAsRead();
                }

                if (messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 48,
                          color: theme.colorScheme.outlineVariant,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Nenhuma mensagem ainda.\nDiga olá! 👋',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  itemCount: messages.length,
                  itemBuilder: (_, i) => _buildBubble(theme, messages[i]),
                );
              },
            ),
          ),

          // ── Input bar ─────────────────────────────────────────────────────
          _buildInputBar(theme),
        ],
      ),
    );
  }

  Widget _buildBubble(ThemeData theme, Map<String, dynamic> row) {
    final senderId = row['sender_id'] as String?;
    final isMe = senderId == _myId;
    final text = row['content'] as String? ?? '';
    final time = _formatTime(row['created_at']?.toString());
    final isRead = row['is_read'] as bool? ?? false;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Small avatar for received messages (left side)
          if (!isMe) ...[
            UserAvatar(
              avatarUrl: _recipientAvatar.isNotEmpty ? _recipientAvatar : null,
              displayName: _recipientName,
              radius: 12,
            ),
            const SizedBox(width: 6),
          ],
          Align(
            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMe
                    ? AppTheme.primary
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isMe ? 18 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 18),
                ),
              ),
              child: Column(
                crossAxisAlignment: isMe
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isMe ? Colors.white : theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        time,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: isMe
                              ? Colors.white.withAlpha(180)
                              : theme.colorScheme.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 4),
                        Icon(
                          isRead ? Icons.done_all_rounded : Icons.done_rounded,
                          size: 12,
                          color: isRead
                              ? Colors.lightBlueAccent
                              : Colors.white.withAlpha(180),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Spacer for sent messages (right side alignment)
          if (isMe) const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildInputBar(ThemeData theme) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputCtrl,
                onChanged: _onInputChanged,
                onSubmitted: (_) => _sendMessage(),
                textInputAction: TextInputAction.send,
                maxLines: 4,
                minLines: 1,
                decoration: InputDecoration(
                  hintText: 'Escreva uma mensagem...',
                  hintStyle: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              child: _inputCtrl.text.trim().isNotEmpty
                  ? FilledButton(
                      onPressed: _isSending ? null : _sendMessage,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        shape: const CircleBorder(),
                        padding: const EdgeInsets.all(12),
                        minimumSize: const Size(48, 48),
                      ),
                      child: _isSending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.send_rounded,
                              size: 20,
                              color: Colors.white,
                            ),
                    )
                  : const SizedBox(width: 48),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Typing indicator widget ───────────────────────────────────────────────────

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator({super.key});

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Digitando',
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppTheme.success,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(width: 3),
        ...List.generate(3, (i) {
          final start = i / 3;
          final end = (i + 1) / 3;
          final anim = CurvedAnimation(
            parent: _ctrl,
            curve: Interval(start, end, curve: Curves.easeInOut),
          );
          return AnimatedBuilder(
            animation: anim,
            builder: (_, __) => Container(
              width: 4,
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: AppTheme.success.withAlpha(
                  (100 + (anim.value * 155)).toInt(),
                ),
                shape: BoxShape.circle,
              ),
              transform: Matrix4.translationValues(0, -2 * anim.value, 0),
            ),
          );
        }),
      ],
    );
  }
}
