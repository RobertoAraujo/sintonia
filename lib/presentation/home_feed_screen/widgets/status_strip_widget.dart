import 'package:flutter/material.dart';

import '../../../core/app_export.dart';

class StatusStripWidget extends StatelessWidget {
  final List<Map<String, dynamic>> statusList;
  final void Function(Map<String, dynamic>) onStatusTap;
  final VoidCallback? onPostStatus;

  const StatusStripWidget({
    super.key,
    required this.statusList,
    required this.onStatusTap,
    this.onPostStatus,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Only show the stories row when there are active stories (hasStory=true) from any user
    final hasVisibleStories = statusList.any(
      (s) => s['hasStory'] == true || s['hasStatus'] == true,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 16, 8),
          child: Row(
            children: [
              Text('Status', style: theme.textTheme.titleSmall),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withAlpha(20),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  '${statusList.where((s) => s['hasStatus'] == true).length} ativos',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (hasVisibleStories)
          SizedBox(
            height: 94,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: statusList.length,
              itemBuilder: (context, index) {
                final status = statusList[index];
                final hasStatus = (status['hasStatus'] as bool?) ?? false;
                final isMe = (status['isMe'] as bool?) ?? false;

                return GestureDetector(
                  onTap: () => onStatusTap(status),
                  child: Container(
                    margin: const EdgeInsets.only(right: 14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          children: [
                            Container(
                              width: 62,
                              height: 62,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: hasStatus
                                    ? const LinearGradient(
                                        colors: [
                                          AppTheme.primary,
                                          AppTheme.secondary,
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      )
                                    : null,
                                border: !hasStatus
                                    ? Border.all(
                                        color: theme.colorScheme.outlineVariant,
                                        width: 2,
                                      )
                                    : null,
                              ),
                              padding: const EdgeInsets.all(2.5),
                              child: ClipOval(
                                child: CustomImageWidget(
                                  imageUrl: status['imageUrl'] as String,
                                  width: 58,
                                  height: 58,
                                  fit: BoxFit.cover,
                                  semanticLabel:
                                      status['semanticLabel'] as String,
                                ),
                              ),
                            ),
                            if (isMe)
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: theme.colorScheme.surface,
                                      width: 2,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.add_rounded,
                                    size: 12,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        SizedBox(
                          width: 62,
                          child: Text(
                            status['name'] as String,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: hasStatus
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: hasStatus
                                  ? theme.colorScheme.onSurface
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        Divider(height: 1, color: theme.colorScheme.outlineVariant),
      ],
    );
  }
}
