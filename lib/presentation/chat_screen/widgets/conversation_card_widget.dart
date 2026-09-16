import 'package:flutter/material.dart';

import '../../../core/app_export.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/user_avatar_widget.dart';

class ConversationCardWidget extends StatelessWidget {
  final Map<String, dynamic> conversation;
  final VoidCallback onTap;
  final VoidCallback? onAvatarTap;

  const ConversationCardWidget({
    super.key,
    required this.conversation,
    required this.onTap,
    this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = conversation['unreadCount'] as int? ?? 0;
    final isOnline = conversation['isOnline'] as bool? ?? false;
    final imageUrl = conversation['imageUrl'] as String? ?? '';
    final name = conversation['name'] as String? ?? 'Conversa';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: unread > 0
              ? AppTheme.primary.withAlpha(8)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: onAvatarTap,
              child: Stack(
                children: [
                  UserAvatar(
                    avatarUrl: imageUrl.isNotEmpty ? imageUrl : null,
                    displayName: name,
                    radius: 26,
                  ),
                  if (isOnline)
                    Positioned(
                      right: 1,
                      bottom: 1,
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
                          name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: unread > 0
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        conversation['timestamp'] as String? ?? '',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: unread > 0
                              ? AppTheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                          fontWeight: unread > 0
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          conversation['lastMessage'] as String? ?? '',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: unread > 0
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.onSurfaceVariant,
                            fontWeight: unread > 0
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (unread > 0)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text(
                            '$unread',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
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
