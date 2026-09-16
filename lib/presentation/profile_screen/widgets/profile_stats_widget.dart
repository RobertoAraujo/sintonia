import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

class ProfileStatsWidget extends StatelessWidget {
  final int friendsCount;
  final int postsCount;
  final int compatScore;
  final VoidCallback? onFriendsTap;
  final VoidCallback? onPostsTap;

  const ProfileStatsWidget({
    super.key,
    required this.friendsCount,
    required this.postsCount,
    required this.compatScore,
    this.onFriendsTap,
    this.onPostsTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          _StatItem(
            value: friendsCount.toString(),
            label: 'Amigos',
            color: AppTheme.primary,
            onTap: onFriendsTap,
          ),
          _Divider(),
          _StatItem(
            value: postsCount.toString(),
            label: 'Posts',
            color: AppTheme.secondary,
            onTap: onPostsTap,
          ),
          _Divider(),
          _StatItem(
            value: '$compatScore%',
            label: 'Compatib.',
            color: AppTheme.success,
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _StatItem({
    required this.value,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          children: [
            Text(
              value,
              style: theme.textTheme.headlineMedium?.copyWith(color: color),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: onTap != null
                    ? color.withAlpha(51000)
                    : theme.colorScheme.onSurfaceVariant,
                decoration: onTap != null ? TextDecoration.underline : null,
                decorationColor: color.withAlpha(30600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 40,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}
