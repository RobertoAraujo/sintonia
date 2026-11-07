import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/supabase_service.dart';
import '../widgets/user_avatar_widget.dart';

class ShareHelper {
  /// Shows a bottom sheet with options to share to friends (in-app) or external networks.
  static Future<void> showShareBottomSheet(
    BuildContext context, {
    required String postId,
    required String authorName,
    String? postContentText,
    String? postImageUrl,
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ShareBottomSheet(
        postId: postId,
        authorName: authorName,
        postContentText: postContentText,
        postImageUrl: postImageUrl,
      ),
    );
  }

  /// Direct external share (OS share sheet).
  static Future<void> sharePost({
    required String postId,
    required String authorName,
    String? postContentText,
  }) async {
    final String postUrl = 'https://sintonia.app/post/$postId';

    String previewText = '';
    if (postContentText != null && postContentText.isNotEmpty) {
      previewText = postContentText.length > 80
          ? ' "${postContentText.substring(0, 80)}..."'
          : ' "$postContentText"';
    }

    final String shareMessage =
        'Veja esta publicação de $authorName no SintonIA:$previewText\n\n'
        'Acesse pelo link: $postUrl';

    await Share.share(
      shareMessage,
      subject: 'Publicação de $authorName no SintonIA',
    );
  }
}

class _ShareBottomSheet extends StatefulWidget {
  final String postId;
  final String authorName;
  final String? postContentText;
  final String? postImageUrl;

  const _ShareBottomSheet({
    required this.postId,
    required this.authorName,
    this.postContentText,
    this.postImageUrl,
  });

  @override
  State<_ShareBottomSheet> createState() => _ShareBottomSheetState();
}

class _ShareBottomSheetState extends State<_ShareBottomSheet> {
  final SupabaseService _service = SupabaseService.instance;
  List<Map<String, dynamic>> _friends = [];
  bool _loading = true;
  final Set<String> _sentTo = {};
  final Set<String> _sending = {};
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    final friends = await _service.fetchFriends();
    if (mounted) {
      setState(() {
        _friends = friends;
        _loading = false;
      });
    }
  }

  Map<String, dynamic> _friendProfile(Map<String, dynamic> friendship) {
    final uid = _service.currentUserId;
    final requester = friendship['requester'] as Map<String, dynamic>?;
    final addressee = friendship['addressee'] as Map<String, dynamic>?;
    if (requester != null && requester['id'] != uid) return requester;
    if (addressee != null && addressee['id'] != uid) return addressee;
    return requester ?? addressee ?? {};
  }

  Future<void> _sendToFriend(Map<String, dynamic> profile) async {
    final friendId = profile['id'] as String?;
    if (friendId == null) return;

    setState(() => _sending.add(friendId));

    final convId = await _service.createOrGetDirectConversation(friendId);
    if (convId != null) {
      final postUrl = 'https://sintonia.app/post/${widget.postId}';
      String message =
          '📌 Veja esta publicação de ${widget.authorName} no SintonIA:\n$postUrl';
      if (widget.postContentText != null &&
          widget.postContentText!.isNotEmpty) {
        final preview = widget.postContentText!.length > 60
            ? '${widget.postContentText!.substring(0, 60)}...'
            : widget.postContentText!;
        message = '📌 "$preview"\n— ${widget.authorName}\n\n$postUrl';
      }
      await _service.sendMessage(conversationId: convId, content: message);
      if (mounted) {
        setState(() {
          _sentTo.add(friendId);
          _sending.remove(friendId);
        });
      }
    } else {
      if (mounted) setState(() => _sending.remove(friendId));
    }
  }

  Future<void> _shareExternal() async {
    Navigator.pop(context);
    await ShareHelper.sharePost(
      postId: widget.postId,
      authorName: widget.authorName,
      postContentText: widget.postContentText,
    );
  }

  List<Map<String, dynamic>> get _filteredFriends {
    if (_searchQuery.isEmpty) return _friends;
    final q = _searchQuery.toLowerCase();
    return _friends.where((f) {
      final profile = _friendProfile(f);
      final name = (profile['display_name'] as String? ?? '').toLowerCase();
      final username = (profile['username'] as String? ?? '').toLowerCase();
      return name.contains(q) || username.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filteredFriends;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (_, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Title
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Text(
                      'Compartilhar',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),

              // External share row
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: InkWell(
                  onTap: _shareExternal,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withAlpha(60),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: theme.colorScheme.primary.withAlpha(60),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.share_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Compartilhar externamente',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                'WhatsApp, Instagram, Twitter e mais',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: theme.colorScheme.outlineVariant,
              ),

              // Friends section header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                child: Row(
                  children: [
                    Icon(
                      Icons.people_outline_rounded,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Enviar para amigos',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              // Search bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    hintText: 'Buscar amigo...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest
                        .withAlpha(80),
                  ),
                ),
              ),

              // Friends list
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.people_outline_rounded,
                              size: 40,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'Nenhum amigo encontrado'
                                  : 'Nenhum resultado',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final friendship = filtered[i];
                          final profile = _friendProfile(friendship);
                          final friendId = profile['id'] as String? ?? '';
                          final name =
                              profile['display_name'] as String? ??
                              profile['username'] as String? ??
                              'Usuário';
                          final avatarUrl = profile['avatar_url'] as String?;
                          final sent = _sentTo.contains(friendId);
                          final sending = _sending.contains(friendId);

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            leading: UserAvatar(
                              avatarUrl: avatarUrl,
                              displayName: name,
                              radius: 22,
                            ),
                            title: Text(
                              name,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: profile['username'] != null
                                ? Text(
                                    '@${profile['username']}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  )
                                : null,
                            trailing: sending
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : sent
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.check_circle_rounded,
                                        color: Colors.green,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Enviado',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: Colors.green,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ],
                                  )
                                : FilledButton.tonal(
                                    onPressed: () => _sendToFriend(profile),
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 6,
                                      ),
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: const Text('Enviar'),
                                  ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
