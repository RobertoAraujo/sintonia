import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../../widgets/custom_image_widget.dart';
import '../../services/profile_interaction_service.dart';
import '../../services/supabase_service.dart';

class PostDetailScreen extends StatefulWidget {
  final Map<String, dynamic> post;
  final Map<String, dynamic>? author;

  const PostDetailScreen({super.key, required this.post, this.author});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  bool _isLiked = false;
  bool _isSaved = false;
  int _likeCount = 0;
  bool _isSendingComment = false;
  bool _isLoadingComments = true;
  final TextEditingController _commentController = TextEditingController();
  final _interactionService = ProfileInteractionService();
  final List<Map<String, dynamic>> _comments = [];
  RealtimeChannel? _commentsSubscription;
  RealtimeChannel? _likesSubscription;

  @override
  void initState() {
    super.initState();
    _likeCount = (widget.post['likes'] as int?) ?? 0;
    _isLiked = (widget.post['isLiked'] as bool?) ?? false;
    _isSaved = (widget.post['isSaved'] as bool?) ?? false;
    _loadComments();
    _subscribeToComments();
    _subscribeToLikes();
  }

  @override
  void dispose() {
    _commentController.dispose();
    if (_commentsSubscription != null) {
      SupabaseService.instance.unsubscribe(_commentsSubscription!);
    }
    if (_likesSubscription != null) {
      SupabaseService.instance.unsubscribe(_likesSubscription!);
    }
    super.dispose();
  }

  Future<void> _loadComments() async {
    final postId = widget.post['id'] as String? ?? '';
    if (postId.isEmpty) {
      setState(() => _isLoadingComments = false);
      return;
    }
    try {
      final data = await SupabaseService.instance.fetchPostComments(postId);
      if (mounted) {
        setState(() {
          _comments.clear();
          for (final c in data) {
            final author = c['author'] as Map<String, dynamic>? ?? {};
            _comments.add({
              'id': c['id'] ?? '',
              'author': author['full_name'] ?? 'Usuário',
              'avatarUrl': author['avatar_url'] ?? '',
              'text': c['content'] ?? '',
              'time': _timeAgo(c['created_at']),
            });
          }
          _isLoadingComments = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingComments = false);
    }
  }

  void _subscribeToComments() {
    final postId = widget.post['id'] as String? ?? '';
    if (postId.isEmpty) return;
    _commentsSubscription = SupabaseService.instance.subscribeToPostComments(
      postId: postId,
      onNewComment: (newComment) async {
        if (!mounted) return;
        final newId = newComment['id'] as String? ?? '';
        // Deduplicate: skip if this comment was already added locally
        if (newId.isNotEmpty && _comments.any((c) => c['id'] == newId)) return;
        // Fetch author info
        final authorId = newComment['author_id'] as String? ?? '';
        String authorName = 'Usuário';
        String authorAvatar = '';
        if (authorId.isNotEmpty) {
          final profile = await SupabaseService.instance.fetchUserProfile(
            authorId,
          );
          authorName = profile?['full_name'] ?? 'Usuário';
          authorAvatar = profile?['avatar_url'] ?? '';
        }
        if (mounted) {
          setState(() {
            _comments.add({
              'id': newId,
              'author': authorName,
              'avatarUrl': authorAvatar,
              'text': newComment['content'] ?? '',
              'time': 'Agora',
            });
          });
        }
      },
    );
  }

  void _subscribeToLikes() {
    final postId = widget.post['id'] as String? ?? '';
    if (postId.isEmpty) return;
    _likesSubscription = SupabaseService.instance.subscribeToPostLikes(
      postId: postId,
      onLikeChange: (payload) {
        if (!mounted) return;
        setState(() {
          if (payload.eventType == PostgresChangeEvent.insert) {
            _likeCount++;
          } else if (payload.eventType == PostgresChangeEvent.delete) {
            _likeCount = (_likeCount - 1).clamp(0, 999999);
          }
        });
      },
    );
  }

  String _timeAgo(dynamic createdAt) {
    if (createdAt == null) return '';
    try {
      final dt = DateTime.parse(createdAt.toString()).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 60) return '${diff.inMinutes}min';
      if (diff.inHours < 24) return '${diff.inHours}h';
      return '${diff.inDays}d';
    } catch (_) {
      return '';
    }
  }

  void _toggleLike() {
    final postId = widget.post['id'] as String? ?? '';
    setState(() {
      _isLiked = !_isLiked;
      _likeCount += _isLiked ? 1 : -1;
    });
    if (_isLiked) {
      SupabaseService.instance.likePost(postId);
    } else {
      SupabaseService.instance.unlikePost(postId);
    }
  }

  void _toggleSave() {
    final postId = widget.post['id'] as String? ?? '';
    setState(() {
      _isSaved = !_isSaved;
    });
    if (_isSaved) {
      SupabaseService.instance.savePost(postId);
    } else {
      SupabaseService.instance.unsavePost(postId);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isSaved ? 'Post salvo!' : 'Post removido dos salvos'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _isSendingComment) return;

    // Session guard — redirect to login if session expired
    final currentUser = SupabaseService.instance.currentUser;
    if (currentUser == null) {
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

    setState(() => _isSendingComment = true);

    final postId =
        widget.post['id'] as String? ?? widget.post['postId'] as String? ?? '';

    if (postId.isEmpty) {
      if (mounted) setState(() => _isSendingComment = false);
      return;
    }

    try {
      // Clear the field immediately for better UX
      _commentController.clear();
      FocusScope.of(context).unfocus();

      final result = await SupabaseService.instance.addComment(
        postId: postId,
        content: text,
      );

      if (result != null && mounted) {
        // Add to local list immediately (Realtime will also fire but dedup is fine)
        final author = result['author'] as Map<String, dynamic>? ?? {};
        setState(() {
          _comments.add({
            'id': result['id'] ?? '',
            'author': author['full_name'] ?? 'Usuário',
            'avatarUrl': author['avatar_url'] ?? '',
            'text': result['content'] ?? text,
            'time': 'Agora',
          });
        });
      } else if (mounted) {
        // Insert failed — restore the text so user can retry
        _commentController.text = text;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Não foi possível enviar o comentário. Tente novamente.',
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade600,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('_sendComment error: $e');
      if (mounted) {
        // Restore text on error
        _commentController.text = text;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erro ao enviar comentário: ${e.toString().split(':').first}',
            ),
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
      if (mounted) setState(() => _isSendingComment = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final post = widget.post;
    final author = widget.author;
    // Only treat as image post when there is an actual non-empty image URL
    final imageUrl = post['imageUrl'] as String?;
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    final caption =
        post['caption'] as String? ??
        post['text'] as String? ??
        post['content'] as String? ??
        '';

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 16,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
        title: Text('Publicação', style: theme.textTheme.titleMedium),
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.more_vert_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Author header
                  if (author != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Row(
                        children: [
                          ClipOval(
                            child: CustomImageWidget(
                              imageUrl:
                                  author['avatarUrl'] as String? ??
                                  author['avatar_url'] as String? ??
                                  '',
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                              semanticLabel:
                                  author['avatarSemantic'] as String? ??
                                  'Foto de perfil',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  author['name'] as String? ??
                                      author['full_name'] as String? ??
                                      'Usuário',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  author['username'] as String? ?? '',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Post image — only shown when there is a real image URL
                  if (hasImage)
                    AspectRatio(
                      aspectRatio: 1,
                      child: CustomImageWidget(
                        imageUrl: imageUrl,
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                        semanticLabel:
                            post['semanticLabel'] as String? ??
                            post['image_semantic'] as String? ??
                            'Imagem do post',
                        errorWidget: const SizedBox.shrink(),
                      ),
                    ),

                  // Action buttons row
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: Row(
                      children: [
                        // Like button
                        GestureDetector(
                          onTap: _toggleLike,
                          child: Row(
                            children: [
                              Icon(
                                _isLiked
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                color: _isLiked
                                    ? Colors.red
                                    : theme.colorScheme.onSurfaceVariant,
                                size: 26,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$_likeCount',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Comment count
                        Row(
                          children: [
                            Icon(
                              Icons.chat_bubble_outline_rounded,
                              color: theme.colorScheme.onSurfaceVariant,
                              size: 24,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${_comments.length}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        // Save button
                        GestureDetector(
                          onTap: _toggleSave,
                          child: Icon(
                            _isSaved
                                ? Icons.bookmark_rounded
                                : Icons.bookmark_border_rounded,
                            color: _isSaved
                                ? AppTheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                            size: 26,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Caption
                  if (caption.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: RichText(
                        text: TextSpan(
                          style: theme.textTheme.bodyMedium,
                          children: [
                            TextSpan(
                              text:
                                  '${author?['name'] ?? author?['full_name'] ?? ''} ',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            TextSpan(text: caption),
                          ],
                        ),
                      ),
                    ),

                  const Divider(height: 1),

                  // Comments section
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      'Comentários',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),

                  if (_isLoadingComments)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_comments.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          'Seja o primeiro a comentar! 💬',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _comments.length,
                      itemBuilder: (context, index) {
                        final comment = _comments[index];
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipOval(
                                child: CustomImageWidget(
                                  imageUrl:
                                      comment['avatarUrl'] as String? ?? '',
                                  width: 32,
                                  height: 32,
                                  fit: BoxFit.cover,
                                  semanticLabel: 'Foto de ${comment['author']}',
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    RichText(
                                      text: TextSpan(
                                        style: theme.textTheme.bodyMedium,
                                        children: [
                                          TextSpan(
                                            text: '${comment['author']} ',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          TextSpan(
                                            text:
                                                comment['text'] as String? ??
                                                '',
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      comment['time'] as String? ?? '',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          // Comment input bar — anchored at the bottom above the keyboard
          Container(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
              bottom: MediaQuery.of(context).viewInsets.bottom > 0
                  ? 8
                  : MediaQuery.of(context).padding.bottom > 0
                  ? MediaQuery.of(context).padding.bottom
                  : 8,
            ),
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
                    controller: _commentController,
                    decoration: InputDecoration(
                      hintText: 'Adicione um comentário...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    maxLines: 1,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendComment(),
                  ),
                ),
                const SizedBox(width: 8),
                _isSendingComment
                    ? const SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : GestureDetector(
                        onTap: _sendComment,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.send_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
