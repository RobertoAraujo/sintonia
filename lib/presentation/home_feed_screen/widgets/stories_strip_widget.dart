import 'package:flutter/material.dart';

import '../../../core/app_export.dart';

class StoriesStripWidget extends StatelessWidget {
  final List<Map<String, dynamic>> stories;

  const StoriesStripWidget({super.key, required this.stories});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: stories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final story = stories[index];
          final isMe = story['isMe'] as bool;
          final hasStory = story['hasStory'] as bool;

          return GestureDetector(
            onTap: () {},
            child: Column(
              children: [
                Stack(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: hasStory
                            ? const LinearGradient(
                                colors: [AppTheme.primary, AppTheme.secondary],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        color: hasStory
                            ? null
                            : theme.colorScheme.outlineVariant,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.scaffoldBackgroundColor,
                            width: 2,
                          ),
                        ),
                        child: ClipOval(
                          child: CustomImageWidget(
                            imageUrl: story['imageUrl'] as String,
                            width: 52,
                            height: 52,
                            fit: BoxFit.cover,
                            semanticLabel: story['semanticLabel'] as String,
                          ),
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
                              color: theme.scaffoldBackgroundColor,
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
                const SizedBox(height: 6),
                SizedBox(
                  width: 60,
                  child: Text(
                    story['name'] as String,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: hasStory ? FontWeight.w700 : FontWeight.w400,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
