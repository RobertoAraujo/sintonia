import 'dart:io' if (dart.library.io) 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../presentation/home_feed_screen/home_feed_screen.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import './user_avatar_widget.dart';

// Global callback so HomeFeedScreen can register its "open post modal" function
typedef OpenPostModalCallback = void Function();

/// A global notifier that any screen can set to `true` to signal that the
/// unread-message badge in the bottom nav should be cleared immediately.
/// ChatScreen calls `messageBadgeResetNotifier.value = true` whenever a
/// conversation is opened so the badge disappears without waiting for the
/// user to tap the Chat tab.
final ValueNotifier<bool> messageBadgeResetNotifier = ValueNotifier(false);

/// Global notifier for pending friend requests count.
/// FriendsScreen updates this whenever the pending requests list changes.
final ValueNotifier<int> pendingFriendRequestsNotifier = ValueNotifier(0);

/// Global notifier for unread messages count.
/// Used by HomeFeedScreen to show the badge on the bell icon.
final ValueNotifier<int> unreadMessagesNotifier = ValueNotifier(0);

class AppNavigation extends StatefulWidget {
  final StatefulNavigationShell navigationShell;
  final OpenPostModalCallback? onCreatePost;

  const AppNavigation({
    required this.navigationShell,
    this.onCreatePost,
    super.key,
  });

  @override
  State<AppNavigation> createState() => _AppNavigationState();
}

class _AppNavigationState extends State<AppNavigation> {
  // Branches: 0=Feed, 1=Chat, 2=Amigos, 3=SintonIA, 4=Perfil
  static const List<_TabSpec> _tabs = [
    _TabSpec(
      label: 'Início',
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      branchIndex: 0,
    ),
    _TabSpec(
      label: 'Chat',
      icon: Icons.chat_bubble_outline_rounded,
      activeIcon: Icons.chat_bubble_rounded,
      branchIndex: 1,
    ),
    _TabSpec(
      label: 'Amigos',
      icon: Icons.people_outline_rounded,
      activeIcon: Icons.people_rounded,
      branchIndex: 2,
    ),
    _TabSpec(
      label: 'SintonIA',
      icon: Icons.auto_awesome_outlined,
      activeIcon: Icons.auto_awesome_rounded,
      branchIndex: 3,
    ),
    _TabSpec(
      label: 'Perfil',
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      branchIndex: 4,
    ),
  ];

  int _unreadMessageCount = 0;
  RealtimeChannel? _unreadChannel;
  RealtimeChannel? _notificationChannel;
  RealtimeChannel? _friendshipsChannel;

  int get _selectedIndex => widget.navigationShell.currentIndex;

  @override
  void initState() {
    super.initState();
    _loadUnreadCount();
    _subscribeToUnread();
    _initMessageNotifications();
    _loadPendingFriendRequests();
    _subscribeFriendships();
    // Listen for badge-reset signals from ChatScreen (e.g. when a conversation is opened)
    messageBadgeResetNotifier.addListener(_onBadgeResetRequested);
  }

  @override
  void dispose() {
    messageBadgeResetNotifier.removeListener(_onBadgeResetRequested);
    _unreadChannel?.unsubscribe();
    _notificationChannel?.unsubscribe();
    _friendshipsChannel?.unsubscribe();
    super.dispose();
  }

  void _onBadgeResetRequested() {
    if (messageBadgeResetNotifier.value && mounted) {
      setState(() => _unreadMessageCount = 0);
      unreadMessagesNotifier.value = 0;
      // Reset the notifier so future signals are detected
      messageBadgeResetNotifier.value = false;
    }
  }

  Future<void> _loadUnreadCount() async {
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) return;
    try {
      // Get conversation IDs the user participates in
      final participantRows = await SupabaseService.instance.client
          .from('conversation_participants')
          .select('conversation_id')
          .eq('user_id', uid);
      final convIds = (participantRows as List)
          .map((r) => r['conversation_id'] as String?)
          .whereType<String>()
          .toList();
      if (convIds.isEmpty) {
        if (mounted) setState(() => _unreadMessageCount = 0);
        return;
      }
      // Count unread messages sent by others in those conversations
      final data = await SupabaseService.instance.client
          .from('messages')
          .select('id')
          .inFilter('conversation_id', convIds)
          .neq('sender_id', uid)
          .eq('is_read', false);
      if (mounted) {
        final count = (data as List).length;
        setState(() => _unreadMessageCount = count);
        unreadMessagesNotifier.value = count;
      }
    } catch (_) {}
  }

  void _subscribeToUnread() {
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) return;

    _unreadChannel = SupabaseService.instance.client
        .channel('nav_unread_messages_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            final record = payload.newRecord;
            final senderId = record['sender_id'] as String?;
            final isRead = record['is_read'] as bool? ?? false;
            // Only count messages from others AND only when NOT on Chat tab
            if (senderId != null &&
                senderId != uid &&
                !isRead &&
                mounted &&
                _selectedIndex != 1) {
              setState(() => _unreadMessageCount++);
              unreadMessagesNotifier.value = _unreadMessageCount;
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            // When messages are marked as read, refresh the count
            // BUT only if the user is NOT already on the Chat tab —
            // if they are on Chat tab the count was already reset to 0
            // and we don't want a stale DB re-fetch to bring it back.
            final isRead = payload.newRecord['is_read'] as bool? ?? false;
            if (isRead && _selectedIndex != 1) {
              _loadUnreadCount();
            }
          },
        )
        .subscribe();
  }

  void _initMessageNotifications() {
    final myUserId = SupabaseService.instance.currentUserId;
    if (myUserId == null) return;

    _notificationChannel = SupabaseService.instance.client
        .channel('global_msg_notifications_$myUserId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            final newMsg = payload.newRecord;
            final senderId = newMsg['sender_id'] as String?;
            // Only show banner for messages from others, when NOT on Chat tab
            if (senderId != null &&
                senderId != myUserId &&
                _selectedIndex != 1 &&
                mounted) {
              _showMessageNotificationBanner(
                senderId: senderId,
                text: newMsg['content'] as String? ?? 'Nova mensagem recebida',
              );
            }
          },
        )
        .subscribe();
  }

  Future<void> _loadPendingFriendRequests() async {
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) return;
    try {
      final data = await SupabaseService.instance.client
          .from('friendships')
          .select('id')
          .eq('addressee_id', uid)
          .eq('status', 'pending');
      final count = (data as List).length;
      if (mounted) {
        pendingFriendRequestsNotifier.value = count;
      }
    } catch (_) {}
  }

  void _subscribeFriendships() {
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) return;

    _friendshipsChannel = SupabaseService.instance.client
        .channel('nav_friendships_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'friendships',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'addressee_id',
            value: uid,
          ),
          callback: (payload) {
            final status = payload.newRecord['status'] as String?;
            if (status == 'pending') {
              pendingFriendRequestsNotifier.value++;
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'friendships',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'addressee_id',
            value: uid,
          ),
          callback: (payload) {
            final newStatus = payload.newRecord['status'] as String?;
            // When accepted/rejected, refresh the count from DB
            if (newStatus == 'accepted' || newStatus == 'rejected') {
              _loadPendingFriendRequests();
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'friendships',
          callback: (payload) {
            // Refresh count on delete (decline)
            _loadPendingFriendRequests();
          },
        )
        .subscribe();
  }

  Future<void> _showMessageNotificationBanner({
    required String senderId,
    required String text,
  }) async {
    if (senderId.isEmpty) return;
    try {
      Map<String, dynamic>? profile;
      try {
        profile = await SupabaseService.instance.client
            .from('user_profiles')
            .select('full_name, avatar_url')
            .eq('id', senderId)
            .maybeSingle();
      } catch (_) {}

      final senderName =
          ((profile?['full_name'] as String?)?.split(' ').first) ?? 'Alguém';
      final avatarUrl = profile?['avatar_url'] as String?;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              UserAvatar(
                avatarUrl: avatarUrl,
                displayName: senderName,
                radius: 16,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      senderName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white70),
            ],
          ),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppTheme.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          action: SnackBarAction(
            label: 'Ver',
            textColor: Colors.white,
            onPressed: () => _onTabTap(1),
          ),
        ),
      );
    } catch (e) {
      debugPrint('_showMessageNotificationBanner error: $e');
    }
  }

  void _onTabTap(int branchIndex) {
    // When switching to Chat tab, reset unread count immediately
    if (branchIndex == 1) {
      setState(() => _unreadMessageCount = 0);
      unreadMessagesNotifier.value = 0;
    }
    // When switching to Friends tab, clear pending friend requests badge
    if (branchIndex == 2) {
      pendingFriendRequestsNotifier.value = 0;
    }
    widget.navigationShell.goBranch(
      branchIndex,
      initialLocation: branchIndex == widget.navigationShell.currentIndex,
    );
  }

  void _onCreatePostTap() {
    // Show the post modal directly from navigation context — avoids black screen
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreatePostBottomSheet(
        onPost: (newPost) {
          // Try to add post to feed via global callback
          globalAddPostCallback?.call(newPost);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      margin: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding + 14),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(235),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(20),
            blurRadius: 24,
            spreadRadius: 2,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // Tab 0: Início
                _NavTabItem(
                  tab: _tabs[0],
                  isActive: _selectedIndex == 0,
                  onTap: () => _onTabTap(0),
                ),
                // Tab 1: Chat (with unread badge)
                _NavTabItem(
                  tab: _tabs[1],
                  isActive: _selectedIndex == 1,
                  onTap: () => _onTabTap(1),
                ),
                // Center: Criar Post
                _CenterPostButton(onTap: _onCreatePostTap),
                // Tab 2: Amigos (with pending requests badge)
                ValueListenableBuilder<int>(
                  valueListenable: pendingFriendRequestsNotifier,
                  builder: (context, pendingCount, _) => _NavTabItemWithBadge(
                    tab: _tabs[2],
                    isActive: _selectedIndex == 2,
                    onTap: () => _onTabTap(2),
                    badgeCount: pendingCount,
                  ),
                ),
                // Tab 3: SintonIA
                _NavTabItem(
                  tab: _tabs[3],
                  isActive: _selectedIndex == 3,
                  onTap: () => _onTabTap(3),
                ),
                // Tab 4: Perfil
                _NavTabItem(
                  tab: _tabs[4],
                  isActive: _selectedIndex == 4,
                  onTap: () => _onTabTap(4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Create Post Bottom Sheet ─────────────────────────────────────────────────
class _CreatePostBottomSheet extends StatefulWidget {
  final void Function(Map<String, dynamic>) onPost;
  const _CreatePostBottomSheet({required this.onPost});

  @override
  State<_CreatePostBottomSheet> createState() => _CreatePostBottomSheetState();
}

class _CreatePostBottomSheetState extends State<_CreatePostBottomSheet> {
  final TextEditingController _textCtrl = TextEditingController();
  String _visibility = 'Todos';
  bool _isPosting = false;
  XFile? _pickedFile;

  // ── Author profile (loaded on init) ──────────────────────────────────────
  String _authorName = 'Usuário';
  String? _authorAvatarUrl;
  bool _isLoadingProfile = true;

  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadAuthorProfile();
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAuthorProfile() async {
    try {
      final profile = await SupabaseService.instance.fetchCurrentUserProfile();
      if (mounted && profile != null) {
        setState(() {
          _authorName = (profile['full_name'] as String?)?.isNotEmpty == true
              ? profile['full_name'] as String
              : 'Usuário';
          _authorAvatarUrl = profile['avatar_url'] as String?;
          _isLoadingProfile = false;
        });
      } else if (mounted) {
        setState(() => _isLoadingProfile = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingProfile = false);
    }
  }

  Future<void> _pickImage() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1080,
        maxHeight: 1080,
      );
      if (file != null) {
        setState(() => _pickedFile = file);
      }
    } catch (_) {}
  }

  Future<void> _publish() async {
    if (_textCtrl.text.trim().isEmpty && _pickedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Escreva algo ou selecione uma foto. 📸'),
          backgroundColor: AppTheme.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }
    setState(() => _isPosting = true);

    try {
      String? uploadedImageUrl;

      // Upload image if selected
      if (_pickedFile != null) {
        final bytes = await _pickedFile!.readAsBytes();
        final ext = _pickedFile!.name.split('.').last.toLowerCase();
        final safeExt = ['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(ext)
            ? ext
            : 'jpg';
        uploadedImageUrl = await SupabaseService.instance.uploadPostImage(
          bytes,
          safeExt,
        );
      }

      // Save post to Supabase DB
      final savedPost = await SupabaseService.instance.createPost(
        content: _textCtrl.text.trim(),
        imageUrl: uploadedImageUrl,
        imageSemantic: uploadedImageUrl != null
            ? 'Imagem publicada pelo usuário: ${_textCtrl.text.trim()}'
            : null,
      );

      if (!mounted) return;

      if (savedPost != null) {
        // Sync image to user_photos gallery
        if (uploadedImageUrl != null && uploadedImageUrl.isNotEmpty) {
          await SupabaseService.instance.syncPostToUserPhotos(
            postId: savedPost['id'] as String,
            photoUrl: uploadedImageUrl,
            caption: _textCtrl.text.trim(),
          );
        }

        final newPost = {
          'id': savedPost['id'] ?? '',
          'authorId': SupabaseService.instance.currentUserId ?? '',
          'authorName': _authorName,
          'authorImage': _authorAvatarUrl ?? '',
          'authorImageSemantic': 'Foto de perfil de $_authorName',
          'neurodivType': '',
          'hyperfocusTags': <String>[],
          'content': _textCtrl.text.trim(),
          'imageUrl': uploadedImageUrl,
          'imageSemantic': uploadedImageUrl != null
              ? 'Imagem publicada pelo usuário'
              : null,
          'likes': 0,
          'comments': 0,
          'saves': 0,
          'timeAgo': 'agora',
          'isLiked': false,
          'isSaved': false,
        };

        widget.onPost(newPost);
        if (mounted) {
          setState(() => _isPosting = false);
          Navigator.of(context).pop();
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                uploadedImageUrl != null
                    ? 'Publicado no Feed e salvo na galeria do perfil! 🎉'
                    : 'Post publicado com sucesso! 🎉',
              ),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      } else {
        if (mounted) {
          setState(() => _isPosting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Não foi possível publicar. Tente novamente.',
              ),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.red.shade400,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isPosting = false);
      debugPrint('_publish error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao publicar: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade400,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppTheme.primary, AppTheme.secondary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.edit_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Criar Post', style: theme.textTheme.titleLarge),
                        Text(
                          'Compartilhe um momento com sua comunidade',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Author row — now uses real profile data
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _isLoadingProfile
                      ? CircleAvatar(
                          radius: 20,
                          backgroundColor: AppTheme.primary.withAlpha(40),
                          child: const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : UserAvatar(
                          avatarUrl: _authorAvatarUrl,
                          displayName: _authorName,
                          radius: 20,
                        ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_authorName, style: theme.textTheme.titleSmall),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withAlpha(20),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.public_rounded,
                              size: 12,
                              color: AppTheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _visibility,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: AppTheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // Text field
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _textCtrl,
                maxLines: 5,
                minLines: 3,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'O que você quer compartilhar hoje? ✨',
                  hintStyle: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Image picker row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _pickedFile != null
                            ? AppTheme.primary.withAlpha(20)
                            : Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _pickedFile != null
                              ? AppTheme.primary.withAlpha(80)
                              : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _pickedFile != null
                                ? Icons.check_circle_rounded
                                : Icons.add_photo_alternate_outlined,
                            size: 18,
                            color: _pickedFile != null
                                ? AppTheme.primary
                                : Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _pickedFile != null
                                ? 'Foto selecionada'
                                : 'Adicionar foto',
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: _pickedFile != null
                                      ? AppTheme.primary
                                      : Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_pickedFile != null) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => setState(() => _pickedFile = null),
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: Colors.red.shade400,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Image preview
            if (_pickedFile != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: kIsWeb
                      ? Image.network(
                          _pickedFile!.path,
                          height: 120,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        )
                      : Image.file(
                          File(_pickedFile!.path),
                          height: 120,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                ),
              ),
            const SizedBox(height: 12),
            // Visibility selector
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    'Visibilidade:',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 10),
                  ...['Todos', 'Amigos', 'Somente eu'].map((v) {
                    final isSelected = _visibility == v;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setState(() => _visibility = v),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.primary
                                : theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text(
                            v,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: isSelected
                                  ? Colors.white
                                  : theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Publish button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isPosting ? null : _publish,
                  icon: _isPosting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded),
                  label: Text(_isPosting ? 'Publicando...' : 'Publicar Post'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabSpec {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final int branchIndex;
  const _TabSpec({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.branchIndex,
  });
}

// ─── Center Post Button ───────────────────────────────────────────────────────
class _CenterPostButton extends StatefulWidget {
  final VoidCallback onTap;
  const _CenterPostButton({required this.onTap});
  @override
  State<_CenterPostButton> createState() => _CenterPostButtonState();
}

class _CenterPostButtonState extends State<_CenterPostButton>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.88 : 1.0,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOutCubic,
        child: AnimatedBuilder(
          animation: _pulseAnim,
          builder: (context, child) {
            return Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2E7D32), Color(0xFF42A5F5)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(
                      0xFF2E7D32,
                    ).withOpacity(0.25 + (_pulseAnim.value * 0.2)),
                    blurRadius: 14 + (_pulseAnim.value * 8),
                    spreadRadius: _pulseAnim.value * 2,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: child,
            );
          },
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}

// ─── Nav Tab Item ─────────────────────────────────────────────────────────────
class _NavTabItem extends StatefulWidget {
  final _TabSpec tab;
  final bool isActive;
  final VoidCallback onTap;
  const _NavTabItem({
    required this.tab,
    required this.isActive,
    required this.onTap,
  });
  @override
  State<_NavTabItem> createState() => _NavTabItemState();
}

class _NavTabItemState extends State<_NavTabItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _scaleAnim = Tween<double>(
      begin: 1.0,
      end: 0.88,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const activeColor = Color(0xFF1B4D3E);
    const inactiveColor = Color(0xFF757575);
    final color = widget.isActive ? activeColor : inactiveColor;

    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scaleAnim,
        child: SizedBox(
          width: 52,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: widget.isActive
                      ? const Color(0xFFE8F5E9)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, anim) =>
                      ScaleTransition(scale: anim, child: child),
                  child: Icon(
                    widget.isActive ? widget.tab.activeIcon : widget.tab.icon,
                    key: ValueKey(widget.isActive),
                    color: color,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: widget.isActive
                      ? FontWeight.w700
                      : FontWeight.w400,
                  color: color,
                  letterSpacing: 0,
                ),
                child: Text(
                  widget.tab.label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Nav Tab Item With Badge ─────────────────────────────────────────────────────────────
class _NavTabItemWithBadge extends StatefulWidget {
  final _TabSpec tab;
  final bool isActive;
  final VoidCallback onTap;
  final int badgeCount;
  const _NavTabItemWithBadge({
    required this.tab,
    required this.isActive,
    required this.onTap,
    required this.badgeCount,
  });
  @override
  State<_NavTabItemWithBadge> createState() => _NavTabItemWithBadgeState();
}

class _NavTabItemWithBadgeState extends State<_NavTabItemWithBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _scaleAnim = Tween<double>(
      begin: 1.0,
      end: 0.88,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const activeColor = Color(0xFF1B4D3E);
    const inactiveColor = Color(0xFF757575);
    final color = widget.isActive ? activeColor : inactiveColor;

    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scaleAnim,
        child: SizedBox(
          width: 52,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: widget.isActive
                      ? const Color(0xFFE8F5E9)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, anim) =>
                          ScaleTransition(scale: anim, child: child),
                      child: Icon(
                        widget.isActive
                            ? widget.tab.activeIcon
                            : widget.tab.icon,
                        key: ValueKey(widget.isActive),
                        color: color,
                        size: 22,
                      ),
                    ),
                    if (widget.badgeCount > 0)
                      Positioned(
                        top: -5,
                        right: -8,
                        child: AnimatedScale(
                          scale: widget.badgeCount > 0 ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.elasticOut,
                          child: Container(
                            constraints: const BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF3B30),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.white,
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.red.withAlpha(102),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              widget.badgeCount > 99
                                  ? '99+'
                                  : '${widget.badgeCount}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: widget.isActive
                      ? FontWeight.w700
                      : FontWeight.w400,
                  color: color,
                  letterSpacing: 0,
                ),
                child: Text(
                  widget.tab.label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
