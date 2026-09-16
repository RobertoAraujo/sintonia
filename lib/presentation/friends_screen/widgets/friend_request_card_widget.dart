import 'package:flutter/material.dart';

import '../../../core/app_export.dart';
import '../../../widgets/status_badge_widget.dart';

class FriendRequestCardWidget extends StatelessWidget {
  final Map<String, dynamic> request;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const FriendRequestCardWidget({
    super.key,
    required this.request,
    required this.onAccept,
    required this.onDecline,
  });

  Color _neurodivColor(String type) {
    switch (type) {
      case 'TEA':
        return AppTheme.teaColor;
      case 'TDAH':
        return AppTheme.tdahColor;
      default:
        return AppTheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ndType = request['neurodivType'] as String;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          ClipOval(
            child: CustomImageWidget(
              imageUrl: request['imageUrl'] as String,
              width: 52,
              height: 52,
              fit: BoxFit.cover,
              semanticLabel: request['imageSemantic'] as String,
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
                        request['name'] as String,
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
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      '${request['compatibilityPct']}% compatível',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      ' · ${request['timeAgo']}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              FilledButton(
                onPressed: onAccept,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  minimumSize: const Size(0, 36),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Aceitar',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              OutlinedButton(
                onPressed: onDecline,
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.onSurfaceVariant,
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  minimumSize: const Size(0, 36),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Recusar', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
