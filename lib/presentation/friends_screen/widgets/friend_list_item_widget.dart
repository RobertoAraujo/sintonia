import 'package:flutter/material.dart';

import '../../../core/app_export.dart';
import '../../../widgets/status_badge_widget.dart';
import '../../chat_screen/widgets/chat_detail_view.dart';

class FriendListItemWidget extends StatelessWidget {
  final Map<String, dynamic> friend;

  const FriendListItemWidget({super.key, required this.friend});

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
    final isOnline = friend['isOnline'] as bool;
    final ndType = friend['neurodivType'] as String;
    final tags = (friend['sharedHyperfocuses'] as List).cast<String>();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              ClipOval(
                child: CustomImageWidget(
                  imageUrl: friend['imageUrl'] as String,
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                  semanticLabel: friend['imageSemantic'] as String,
                ),
              ),
              if (isOnline)
                Positioned(
                  right: 2,
                  bottom: 2,
                  child: Container(
                    width: 12,
                    height: 12,
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
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        friend['name'] as String,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    StatusBadgeWidget(
                      label: ndType,
                      color: _neurodivColor(ndType),
                      style: BadgeStyle.subtle,
                      fontSize: 10,
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  friend['lastSeen'] as String,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: isOnline
                        ? AppTheme.success
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: isOnline ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  children: tags
                      .map(
                        (t) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withAlpha(20),
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text(
                            t,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () {
              final conv = {
                'id': 'chat_${friend['id'] ?? friend['name']}',
                'userId': friend['id'],
                'name': friend['name'] as String? ?? 'Usuário',
                'imageUrl': friend['imageUrl'] as String? ?? '',
                'imageSemantic':
                    friend['imageSemantic'] as String? ?? 'Foto de perfil',
                'lastMessage': '',
                'timestamp': 'Agora',
                'unreadCount': 0,
                'isOnline': friend['isOnline'] as bool? ?? false,
                'isGroup': false,
                'isNewRequest': false,
                'neurodivType': friend['neurodivType'],
              };
              Navigator.of(context).push(
                PageRouteBuilder(
                  pageBuilder: (_, animation, __) => ChatDetailView(
                    conversation: conv,
                    onBack: () => Navigator.pop(context),
                    onAvatarTap: null,
                  ),
                  transitionsBuilder: (_, animation, __, child) =>
                      SlideTransition(
                        position:
                            Tween<Offset>(
                              begin: const Offset(1, 0),
                              end: Offset.zero,
                            ).animate(
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
            },
            icon: CustomIconWidget(
              iconName: 'chat_bubble_outline_rounded',
              color: AppTheme.primary,
              size: 22,
            ),
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.primary.withAlpha(26),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
