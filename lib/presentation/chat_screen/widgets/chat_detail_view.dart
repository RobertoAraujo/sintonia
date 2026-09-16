import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/app_export.dart';
import '../../../services/offline_message_queue.dart';
import '../../../services/supabase_service.dart';
import '../../user_profile_screen/user_profile_screen.dart';

class ChatDetailView extends StatefulWidget {
  final Map<String, dynamic> conversation;
  final VoidCallback onBack;
  final VoidCallback? onAvatarTap;

  const ChatDetailView({
    super.key,
    required this.conversation,
    required this.onBack,
    this.onAvatarTap,
  });

  @override
  State<ChatDetailView> createState() => _ChatDetailViewState();
}

class _ChatDetailViewState extends State<ChatDetailView> {
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final GlobalKey _menuButtonKey = GlobalKey();
  bool _isTyping = false;
  bool _isLoading = true;
  bool _isSending = false;
  bool _isOffline = false;
  bool _isFriend = true;
  bool _isCheckingFriendship = false;

  // Recipient profile data (may be enriched after fetch)
  String _recipientName = '';
  String _recipientAvatar = '';
  String? _recipientPetPhotoUrl;
  bool _isLoadingRecipient = false;

  final List<Map<String, dynamic>> _messages = [];
  RealtimeChannel? _realtimeChannel;

  String get _conversationId => widget.conversation['id'] as String? ?? '';

  @override
  void initState() {
    super.initState();
    _recipientName = widget.conversation['name'] as String? ?? 'Conversa';
    _recipientAvatar = widget.conversation['imageUrl'] as String? ?? '';
    _loadMessages();
    _subscribeToMessages();
    _loadPendingOfflineMessages();
    _checkFriendship();
    // Always fetch the recipient profile to ensure avatar_url and name are
    // up-to-date. This fixes the missing avatar bug.
    _fetchRecipientProfile();
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// Fetch the recipient's full profile from Supabase if name is generic/missing.
  Future<void> _fetchRecipientProfile() async {
    final otherUserId = widget.conversation['userId'] as String?;
    if (otherUserId == null) return;
    setState(() => _isLoadingRecipient = true);
    try {
      final profile = await SupabaseService.instance.client
          .from('profiles')
          .select('id, name, username, avatar_url, active_pet_id')
          .eq('id', otherUserId)
          .maybeSingle();
      if (profile != null && mounted) {
        final name =
            profile['name'] as String? ??
            profile['username'] as String? ??
            'Usuário';
        final avatarUrl = profile['avatar_url'] as String? ?? '';
        setState(() {
          _recipientName = name;
          _recipientAvatar = avatarUrl;
          _isLoadingRecipient = false;
        });
        // Fetch pet badge
        final activePetId = profile['active_pet_id'] as String?;
        if (activePetId != null) {
          _fetchPetPhoto(activePetId);
        }
      } else {
        if (mounted) setState(() => _isLoadingRecipient = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingRecipient = false);
    }
  }

  /// Fetch pet photo for badge when profile name is already known.
  Future<void> _fetchRecipientPet() async {
    final otherUserId = widget.conversation['userId'] as String?;
    if (otherUserId == null) return;
    try {
      final profile = await SupabaseService.instance.client
          .from('profiles')
          .select('active_pet_id')
          .eq('id', otherUserId)
          .maybeSingle();
      if (profile != null) {
        final activePetId = profile['active_pet_id'] as String?;
        if (activePetId != null) {
          _fetchPetPhoto(activePetId);
        }
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
    final otherUserId = widget.conversation['userId'] as String?;
    if (otherUserId == null) {
      widget.onAvatarTap?.call();
      return;
    }
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, animation, __) => UserProfileScreen(
          userData: {
            'id': otherUserId,
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

  /// Check if the other user in this conversation is a friend.
  Future<void> _checkFriendship() async {
    final otherUserId = widget.conversation['userId'] as String?;
    final myId = SupabaseService.instance.currentUserId;
    // Groups or self-chats are always allowed
    if (otherUserId == null ||
        otherUserId == myId ||
        widget.conversation['isGroup'] == true) {
      return;
    }
    setState(() => _isCheckingFriendship = true);
    try {
      final friends = await SupabaseService.instance.areFriends(otherUserId);
      if (mounted) {
        setState(() {
          _isFriend = friends;
          _isCheckingFriendship = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isCheckingFriendship = false);
    }
  }

  /// Load any messages that were queued while offline and show them in the UI.
  Future<void> _loadPendingOfflineMessages() async {
    if (_conversationId.isEmpty) return;
    final pending = await OfflineMessageQueue.instance
        .getPendingForConversation(_conversationId);
    if (!mounted || pending.isEmpty) return;
    final uid = SupabaseService.instance.currentUserId;
    final now = DateTime.now();
    setState(() {
      for (final msg in pending) {
        // Avoid duplicates if already shown
        if (_messages.any((m) => m['id'] == msg.localId)) continue;
        _messages.add({
          'id': msg.localId,
          'isMe': true,
          'text': msg.content,
          'time':
              '${msg.createdAt.hour.toString().padLeft(2, '0')}:${msg.createdAt.minute.toString().padLeft(2, '0')}',
          'status': 'pending',
        });
      }
    });
    if (pending.isNotEmpty) _scrollToBottom();
  }

  Future<void> _loadMessages() async {
    if (_conversationId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final rows = await SupabaseService.instance.fetchMessages(
        _conversationId,
      );
      if (!mounted) return;
      final uid = SupabaseService.instance.currentUserId;
      final mapped = rows.map((row) => _mapRow(row, uid)).toList();
      setState(() {
        _messages
          ..clear()
          ..addAll(mapped);
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _subscribeToMessages() {
    if (_conversationId.isEmpty) return;
    final uid = SupabaseService.instance.currentUserId;

    _realtimeChannel = SupabaseService.instance.client
        .channel('messages:$_conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: _conversationId,
          ),
          callback: (payload) async {
            final newRecord = payload.newRecord;
            if (newRecord.isEmpty) return;

            final senderId = newRecord['sender_id'] as String?;

            if (senderId == uid) {
              // This is our own message arriving via realtime — it was synced
              // from the offline queue by ConnectivitySyncService.
              // Replace any matching 'pending' message in the list, or add if new.
              final content = newRecord['content'] as String?;
              if (!mounted) return;
              setState(() {
                // Find a pending message with the same content to replace
                final idx = _messages.lastIndexWhere(
                  (m) => m['status'] == 'pending' && m['text'] == content,
                );
                if (idx != -1) {
                  final uid2 = SupabaseService.instance.currentUserId;
                  final realMsg = _mapRow(newRecord, uid2);
                  realMsg['status'] = 'read';
                  _messages[idx] = realMsg;
                }
                // If not found as pending, it was already handled optimistically — skip
              });
              return;
            }

            // Incoming message from another user
            Map<String, dynamic>? senderProfile;
            try {
              senderProfile = await SupabaseService.instance.fetchUserProfile(
                senderId ?? '',
              );
            } catch (_) {}

            final enriched = Map<String, dynamic>.from(newRecord);
            if (senderProfile != null) enriched['sender'] = senderProfile;

            if (!mounted) return;
            setState(() => _messages.add(_mapRow(enriched, uid)));
            _scrollToBottom();
          },
        )
        .subscribe();
  }

  Map<String, dynamic> _mapRow(Map<String, dynamic> row, String? uid) {
    final sender = row['sender'] as Map<String, dynamic>?;
    final senderId = row['sender_id'] as String? ?? sender?['id'] as String?;
    final isMe = senderId == uid;
    final createdAt = row['created_at'];
    String time = '';
    if (createdAt != null) {
      try {
        final dt = DateTime.parse(createdAt.toString()).toLocal();
        time =
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {}
    }
    return {
      'id': row['id'] ?? '',
      'isMe': isMe,
      'text': row['content'] ?? '',
      'time': time,
      'status': 'read',
    };
  }

  Future<void> _sendMessage() async {
    if (!_isFriend) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Você só pode enviar mensagens para amigos. Envie uma solicitação de amizade primeiro! 💜',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _isSending) return;

    final now = DateTime.now();
    final optimisticId = 'optimistic_${now.millisecondsSinceEpoch}';
    final optimisticMsg = {
      'id': optimisticId,
      'isMe': true,
      'text': text,
      'time':
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
      'status': 'sent',
    };

    setState(() {
      _messages.add(optimisticMsg);
      _inputCtrl.clear();
      _isTyping = false;
      _isSending = true;
    });
    _scrollToBottom();

    // Check connectivity before attempting to send
    final connectivityResults = await Connectivity().checkConnectivity();
    final hasConnection = connectivityResults.any(
      (r) =>
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.ethernet,
    );

    if (!hasConnection) {
      // Queue for later and mark message as pending
      final pending = PendingMessage(
        localId: optimisticId,
        conversationId: _conversationId,
        content: text,
        messageType: 'text',
        createdAt: now,
      );
      await OfflineMessageQueue.instance.enqueue(pending);
      if (mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => m['id'] == optimisticId);
          if (idx != -1) _messages[idx]['status'] = 'pending';
          _isSending = false;
          _isOffline = true;
        });
      }
      return;
    }

    try {
      final result = await SupabaseService.instance.sendMessage(
        conversationId: _conversationId,
        content: text,
      );
      if (!mounted) return;
      if (result != null) {
        // Replace optimistic message with real one
        final uid = SupabaseService.instance.currentUserId;
        final realMsg = _mapRow(result, uid);
        realMsg['status'] = 'read';
        setState(() {
          final idx = _messages.indexWhere((m) => m['id'] == optimisticId);
          if (idx != -1) _messages[idx] = realMsg;
          _isOffline = false;
        });
      }
    } catch (_) {
      // Network error — queue the message for later
      final pending = PendingMessage(
        localId: optimisticId,
        conversationId: _conversationId,
        content: text,
        messageType: 'text',
        createdAt: now,
      );
      await OfflineMessageQueue.instance.enqueue(pending);
      if (mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => m['id'] == optimisticId);
          if (idx != -1) _messages[idx]['status'] = 'pending';
          _isOffline = true;
        });
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final conv = widget.conversation;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    // With extendBody: true, padding.bottom already equals the full floating
    // nav bar height (content + inner padding + bottom margin + system safe area).
    // Just add a small extra gap (8px) so the input sits flush above the nav bar.
    final navBarOffset = safeBottom + 8.0;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(8, 12, 16, 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  bottom: BorderSide(
                    color: theme.colorScheme.outlineVariant,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: widget.onBack,
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 18,
                    ),
                  ),
                  GestureDetector(
                    onTap: _navigateToRecipientProfile,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundImage: _recipientAvatar.isNotEmpty
                              ? NetworkImage(_recipientAvatar)
                              : null,
                          child: _recipientAvatar.isEmpty
                              ? const Icon(Icons.person_rounded, size: 20)
                              : null,
                        ),
                        // Pet badge in bottom-right corner
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
                          )
                        else if (conv['isOnline'] == true)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 10,
                              height: 10,
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
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: _navigateToRecipientProfile,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _isLoadingRecipient
                              ? Container(
                                  width: 100,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.outlineVariant
                                        .withAlpha(80),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                )
                              : Text(
                                  _recipientName,
                                  style: theme.textTheme.titleSmall,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          Text(
                            conv['isOnline'] == true
                                ? 'Online agora'
                                : 'Offline',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: conv['isOnline'] == true
                                  ? AppTheme.success
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    key: _menuButtonKey,
                    onPressed: () {
                      final RenderBox button =
                          _menuButtonKey.currentContext!.findRenderObject()
                              as RenderBox;
                      final RenderBox overlay =
                          Navigator.of(
                                context,
                              ).overlay!.context.findRenderObject()
                              as RenderBox;
                      final Offset buttonOffset = button.localToGlobal(
                        Offset.zero,
                        ancestor: overlay,
                      );
                      showMenu(
                        context: context,
                        position: RelativeRect.fromLTRB(
                          buttonOffset.dx - 160,
                          buttonOffset.dy + button.size.height,
                          buttonOffset.dx + button.size.width,
                          buttonOffset.dy + button.size.height + 150,
                        ),
                        items: [
                          PopupMenuItem(
                            onTap: () {},
                            child: Row(
                              children: const [
                                Icon(Icons.volume_off_outlined),
                                SizedBox(width: 12),
                                Text('Silenciar'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            onTap: () {},
                            child: Row(
                              children: const [
                                Icon(Icons.block_rounded),
                                SizedBox(width: 12),
                                Text('Bloquear'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            onTap: () {},
                            child: Row(
                              children: const [
                                Icon(Icons.flag_outlined),
                                SizedBox(width: 12),
                                Text('Denunciar'),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                    icon: const Icon(Icons.more_vert_rounded),
                  ),
                ],
              ),
            ),

            // Messages
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      children: [
                        // Offline banner
                        if (_isOffline)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              vertical: 6,
                              horizontal: 12,
                            ),
                            color: Colors.orange.shade700,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(
                                  Icons.wifi_off_rounded,
                                  size: 14,
                                  color: Colors.white,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Sem conexão — mensagens serão enviadas automaticamente',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        Expanded(
                          child: _messages.isEmpty
                              ? Center(
                                  child: Text(
                                    'Nenhuma mensagem ainda.\nDiga olá! 👋',
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  controller: _scrollCtrl,
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    12,
                                    16,
                                    12,
                                  ),
                                  itemCount: _messages.length,
                                  itemBuilder: (_, i) {
                                    final msg = _messages[i];
                                    final isMe = msg['isMe'] as bool? ?? false;
                                    return _MessageBubble(
                                      message: msg,
                                      isMe: isMe,
                                      theme: theme,
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
            ),

            // Not-friends banner
            if (!_isFriend && !_isCheckingFriendship)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 16,
                ),
                color: AppTheme.primary.withAlpha(20),
                child: Row(
                  children: [
                    Icon(Icons.lock_rounded, size: 16, color: AppTheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Vocês precisam ser amigos para trocar mensagens.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Input — sits flush above the floating nav bar
            Container(
              padding: EdgeInsets.only(
                left: 12,
                right: 12,
                top: 8,
                bottom: bottomInset > 0 ? bottomInset + 8 : navBarOffset,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  top: BorderSide(
                    color: theme.colorScheme.outlineVariant,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: _isTyping
                              ? AppTheme.primary.withAlpha(100)
                              : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: TextField(
                        controller: _inputCtrl,
                        onChanged: (v) =>
                            setState(() => _isTyping = v.isNotEmpty),
                        onSubmitted: (_) => _sendMessage(),
                        decoration: const InputDecoration(
                          hintText: 'Mensagem...',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                        maxLines: null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedScale(
                    scale: _isTyping ? 1.0 : 0.85,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.elasticOut,
                    child: _isSending
                        ? Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withAlpha(80),
                              shape: BoxShape.circle,
                            ),
                            child: const Padding(
                              padding: EdgeInsets.all(10),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                          )
                        : IconButton(
                            onPressed: _sendMessage,
                            icon: const Icon(Icons.send_rounded),
                            style: IconButton.styleFrom(
                              backgroundColor: _isTyping
                                  ? AppTheme.primary
                                  : AppTheme.primary.withAlpha(80),
                              foregroundColor: Colors.white,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool isMe;
  final ThemeData theme;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? AppTheme.primary : theme.colorScheme.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMe ? 18 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 18),
          ),
          border: isMe
              ? null
              : Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(
              message['text'] as String? ?? '',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isMe ? Colors.white : theme.colorScheme.onSurface,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message['time'] as String? ?? '',
                  style: TextStyle(
                    fontSize: 10,
                    color: isMe
                        ? Colors.white70
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    message['status'] == 'pending'
                        ? Icons.schedule_rounded
                        : message['status'] == 'read'
                        ? Icons.done_all_rounded
                        : Icons.done_rounded,
                    size: 14,
                    color: message['status'] == 'pending'
                        ? Colors.white54
                        : message['status'] == 'read'
                        ? Colors.lightBlueAccent
                        : Colors.white70,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
