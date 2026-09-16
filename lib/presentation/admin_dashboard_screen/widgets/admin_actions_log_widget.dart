import 'package:flutter/material.dart';
import '../../../core/app_export.dart';
import '../../../theme/app_theme.dart';

class AdminActionsLogWidget extends StatelessWidget {
  final List<Map<String, dynamic>> actions;

  const AdminActionsLogWidget({super.key, required this.actions});

  IconData _actionIcon(String type) {
    switch (type) {
      case 'ban':
        return Icons.block_rounded;
      case 'remove':
        return Icons.delete_outline_rounded;
      case 'dismiss':
        return Icons.archive_outlined;
      case 'warn':
        return Icons.warning_amber_rounded;
      default:
        return Icons.check_circle_outline_rounded;
    }
  }

  Color _actionColor(String type) {
    switch (type) {
      case 'ban':
        return AppTheme.error;
      case 'remove':
        return AppTheme.warning;
      case 'dismiss':
        return AppTheme.primary;
      case 'warn':
        return AppTheme.warning;
      default:
        return AppTheme.success;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: List.generate(actions.length, (index) {
          final action = actions[index];
          final type = action['actionType'] as String;
          final color = _actionColor(type);
          final isLast = index == actions.length - 1;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: color.withAlpha(26),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(_actionIcon(type), color: color, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            action['action'] as String,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                Icons.alternate_email_rounded,
                                size: 11,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                action['target'] as String,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Text(
                      (action['timestamp'] as String).split(' ').last,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isLast)
                Divider(
                  height: 1,
                  indent: 62,
                  color: theme.colorScheme.outlineVariant,
                ),
            ],
          );
        }),
      ),
    );
  }
}
