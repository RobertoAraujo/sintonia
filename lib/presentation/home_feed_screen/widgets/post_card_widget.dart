import 'package:flutter/material.dart';

import '../../../core/app_export.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/report_content_dialog.dart';
import '../../../widgets/user_avatar_widget.dart';

class PostCardWidget extends StatelessWidget {
  final Map<String, dynamic> post;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;
  final VoidCallback onSave;
  final VoidCallback onAuthorTap;
  final VoidCallback? onDelete;

  const PostCardWidget({
    super.key,
    required this.post,
    required this.onLike,
    required this.onComment,
    required this.onShare,
    required this.onSave,
    required this.onAuthorTap,
    this.onDelete,
  });

  Color _neurodivColor(String type) {
    switch (type) {
      case 'TEA':
        return AppTheme.teaColor;
      case 'TDAH':
        return AppTheme.tdahColor;
      case 'Dislexia':
        return AppTheme.dyslexiaColor;
      case 'Tourette':
        return AppTheme.touretteColor;
      default:
        return AppTheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLiked = post['isLiked'] as bool;
    final isSaved = post['isSaved'] as bool;
    final tags = (post['hyperfocusTags'] as List?)?.cast<String>() ?? [];
    final GlobalKey menuKey = GlobalKey();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Author row
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 8, 10),
            child: Row(
              children: [
                GestureDetector(
                  onTap: onAuthorTap,
                  child: Hero(
                    tag: 'avatar_${post['authorId']}',
                    child: UserAvatar(
                      avatarUrl: post['authorImage'] as String?,
                      displayName: post['authorName'] as String? ?? 'U',
                      radius: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: onAuthorTap,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                post['authorName'] as String,
                                style: theme.textTheme.titleSmall,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (post['neurodivType'] != null &&
                                (post['neurodivType'] as String).isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _neurodivColor(
                                    post['neurodivType'] as String,
                                  ).withAlpha(20),
                                  borderRadius: BorderRadius.circular(100),
                                  border: Border.all(
                                    color: _neurodivColor(
                                      post['neurodivType'] as String,
                                    ).withAlpha(80),
                                  ),
                                ),
                                child: Text(
                                  post['neurodivType'] as String,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: _neurodivColor(
                                      post['neurodivType'] as String,
                                    ),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          post['timeAgo'] as String,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  key: menuKey,
                  onPressed: () {
                    final RenderBox button =
                        menuKey.currentContext!.findRenderObject() as RenderBox;
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
                        if (onDelete != null)
                          PopupMenuItem(
                            onTap: () {
                              Future.delayed(Duration.zero, () {
                                showDialog(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Excluir publicação'),
                                    content: const Text(
                                      'Tem certeza que deseja excluir esta publicação? Esta ação não pode ser desfeita.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx),
                                        child: const Text('Cancelar'),
                                      ),
                                      FilledButton(
                                        onPressed: () {
                                          Navigator.pop(ctx);
                                          onDelete!();
                                        },
                                        style: FilledButton.styleFrom(
                                          backgroundColor: Colors.red,
                                        ),
                                        child: const Text('Excluir'),
                                      ),
                                    ],
                                  ),
                                );
                              });
                            },
                            child: Row(
                              children: const [
                                Icon(
                                  Icons.delete_outline_rounded,
                                  color: Colors.red,
                                ),
                                SizedBox(width: 12),
                                Text(
                                  'Excluir publicação',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ],
                            ),
                          ),
                        PopupMenuItem(
                          onTap: () {
                            Future.delayed(Duration.zero, () {
                              showReportDialog(
                                context,
                                contentType: 'post',
                                contentId: post['id']?.toString(),
                                reportedUserId: post['authorId']?.toString(),
                              );
                            });
                          },
                          child: Row(
                            children: const [
                              Icon(Icons.flag_outlined),
                              SizedBox(width: 12),
                              Text('Denunciar'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          onTap: () {},
                          child: Row(
                            children: const [
                              Icon(Icons.block_rounded),
                              SizedBox(width: 12),
                              Text('Bloquear usuário'),
                            ],
                          ),
                        ),
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
                      ],
                    );
                  },
                  icon: Icon(
                    Icons.more_horiz_rounded,
                    color: theme.colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
              ],
            ),
          ),

          // Tags
          if (tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: tags
                    .map(
                      (tag) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryContainer.withAlpha(80),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(
                          '# $tag',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),

          // Content
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Text(
              post['content'] as String,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
            ),
          ),

          // Sensory warning banner
          if (post['sensoryWarning'] == true)
            Container(
              margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.withAlpha(20),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withAlpha(80)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '⚠️ Aviso sensorial: este conteúdo pode conter elementos de alta estimulação.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Image
          if (post['imageUrl'] != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
              child: Container(
                constraints: const BoxConstraints(maxHeight: 500),
                width: double.infinity,
                decoration: BoxDecoration(color: Colors.black.withAlpha(8)),
                child: ClipRRect(
                  borderRadius: BorderRadius.zero,
                  child: Image.network(
                    post['imageUrl'] as String,
                    fit: BoxFit.contain,
                    semanticLabel:
                        post['imageSemantic'] as String? ?? 'Imagem do post',
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return const SizedBox(
                        height: 200,
                        child: Center(child: CircularProgressIndicator()),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return const SizedBox(
                        height: 150,
                        child: Center(
                          child: Icon(Icons.broken_image, color: Colors.grey),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),

          // Actions
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
            child: Row(
              children: [
                _ActionButton(
                  icon: isLiked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  label: '${post['likes']}',
                  color: isLiked
                      ? Colors.red
                      : theme.colorScheme.onSurfaceVariant,
                  onTap: onLike,
                ),
                _ActionButton(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: '${post['comments']}',
                  color: theme.colorScheme.onSurfaceVariant,
                  onTap: onComment,
                ),
                _ActionButton(
                  icon: Icons.share_outlined,
                  label: 'Compartilhar',
                  color: theme.colorScheme.onSurfaceVariant,
                  onTap: onShare,
                ),
                const Spacer(),
                _ActionButton(
                  icon: isSaved
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded,
                  label: '',
                  color: isSaved
                      ? AppTheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                  onTap: onSave,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
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
        scale: _pressed ? 0.85 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 20, color: widget.color),
              if (widget.label.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 12,
                    color: widget.color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
