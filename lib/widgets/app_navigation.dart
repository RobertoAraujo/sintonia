import 'dart:io' if (dart.library.io) 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../presentation/home_feed_screen/home_feed_screen.dart';
import '../services/media_permission_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import './user_avatar_widget.dart';

// Global callback so HomeFeedScreen can register its "open post modal" function
typedef OpenPostModalCallback = void Function();

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
  // Branches: 0=Feed, 1=Chat, 2=Grupos, 3=SintonIA, 4=Perfil
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
      label: 'Grupos',
      icon: Icons.group_outlined,
      activeIcon: Icons.group_rounded,
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

  int get _selectedIndex => widget.navigationShell.currentIndex;

  @override
  void initState() {
    super.initState();
    _loadUnreadCount();
    _subscribeToUnread();
    _initMessageNotifications();
  }

  @override
  void dispose() {
    _unreadChannel?.unsubscribe();
    _notificationChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadUnreadCount() async {
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) return;
    try {
      final data = await SupabaseService.instance.client
          .from('messages')
          .select('id')
          .eq('receiver_id', uid)
          .eq('is_read', false);
      if (mounted) {
        setState(() => _unreadMessageCount = (data as List).length);
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
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'receiver_id',
            value: uid,
          ),
          callback: (payload) {
            final record = payload.newRecord;
            final isRead = record['is_read'] as bool? ?? false;
            if (!isRead && mounted) {
              setState(() => _unreadMessageCount++);
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'receiver_id',
            value: uid,
          ),
          callback: (payload) {
            // When messages are marked as read, refresh the count
            final isRead = payload.newRecord['is_read'] as bool? ?? false;
            if (isRead) {
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
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'receiver_id',
            value: myUserId,
          ),
          callback: (payload) {
            final newMsg = payload.newRecord;
            // Only show banner when NOT on the Chat tab
            if (_selectedIndex != 1 && mounted) {
              _showMessageNotificationBanner(
                senderId: newMsg['sender_id'] as String? ?? '',
                text: newMsg['content'] as String? ?? 'Nova mensagem recebida',
              );
            }
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
      // Try user_profiles view first, fall back to profiles table
      Map<String, dynamic>? profile;
      try {
        profile = await SupabaseService.instance.client
            .from('user_profiles')
            .select('full_name, avatar_url')
            .eq('id', senderId)
            .maybeSingle();
      } catch (_) {}

      // Fallback: query profiles table if user_profiles returned nothing
      if (profile == null) {
        try {
          profile = await SupabaseService.instance.client
              .from('profiles')
              .select('name, avatar_url')
              .eq('id', senderId)
              .maybeSingle();
          // Normalise field name
          if (profile != null && profile['name'] != null) {
            profile = {
              'full_name': profile['name'],
              'avatar_url': profile['avatar_url'],
            };
          }
        } catch (_) {}
      }

      final senderName =
          ((profile?['full_name'] as String?)?.split(' ').first) ?? 'Alguém';
      final avatarUrl = profile?['avatar_url'] as String?;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              UserAvatar(avatarUrl: avatarUrl, displayName: senderName, radius: 16),
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
    // When switching to Chat tab, reset unread count optimistically
    if (branchIndex == 1) {
      setState(() => _unreadMessageCount = 0);
      // Re-fetch after a short delay to get accurate count
      Future.delayed(const Duration(seconds: 2), _loadUnreadCount);
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
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      margin: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding + 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(22),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: theme.colorScheme.outlineVariant, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
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
            _NavTabItemWithBadge(
              tab: _tabs[1],
              isActive: _selectedIndex == 1,
              onTap: () => _onTabTap(1),
              badgeCount: _unreadMessageCount,
            ),
            // Center: Criar Post
            _CenterPostButton(onTap: _onCreatePostTap),
            // Tab 2: Grupos
            _NavTabItem(
              tab: _tabs[2],
              isActive: _selectedIndex == 2,
              onTap: () => _onTabTap(2),
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
    if (!await MediaPermissionService.request(camera: false)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permissão para acessar fotos negada.')),
        );
      }
      return;
    }
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

class _CenterPostButtonState extends State<_CenterPostButton> {
  bool _pressed = false;
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
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppTheme.primary, AppTheme.secondary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withAlpha(90),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
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
    final theme = Theme.of(context);
    final color = widget.isActive
        ? AppTheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scaleAnim,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: widget.isActive
                ? AppTheme.primary.withAlpha(15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  widget.isActive ? widget.tab.activeIcon : widget.tab.icon,
                  key: ValueKey(widget.isActive),
                  color: color,
                  size: 24,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                widget.tab.label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: widget.isActive
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: color,
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
    final theme = Theme.of(context);
    final color = widget.isActive
        ? AppTheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scaleAnim,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: widget.isActive
                ? AppTheme.primary.withAlpha(15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      widget.isActive ? widget.tab.activeIcon : widget.tab.icon,
                      key: ValueKey(widget.isActive),
                      color: color,
                      size: 24,
                    ),
                  ),
                  if (widget.badgeCount > 0)
                    Positioned(
                      top: -4,
                      right: -6,
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
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: Text(
                          widget.badgeCount > 99
                              ? '99+'
                              : '${widget.badgeCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                widget.tab.label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: widget.isActive
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}