import 'package:flutter/material.dart';

import '../../../core/app_export.dart';

class PetDiaryEntryWidget extends StatelessWidget {
  final Map<String, dynamic> entry;
  final VoidCallback onLike;

  const PetDiaryEntryWidget({
    super.key,
    required this.entry,
    required this.onLike,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imageUrl = entry['imageUrl'] as String?;
    final isLiked = entry['isLiked'] as bool;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                ClipOval(
                  child: CustomImageWidget(
                    imageUrl: entry['ownerImage'] as String,
                    width: 36,
                    height: 36,
                    fit: BoxFit.cover,
                    semanticLabel: entry['ownerImageSemantic'] as String,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            entry['ownerName'] as String,
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withAlpha(26),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.pets_rounded,
                                  size: 10,
                                  color: AppTheme.primary,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  entry['petName'] as String,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: AppTheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${entry['petSpecies']} · ${entry['timeAgo']}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (imageUrl != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: CustomImageWidget(
                  imageUrl: imageUrl,
                  width: double.infinity,
                  height: 180,
                  fit: BoxFit.cover,
                  semanticLabel:
                      entry['imageSemantic'] as String? ?? 'Foto do pet',
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(14, imageUrl != null ? 10 : 0, 14, 0),
            child: Text(
              entry['entryText'] as String,
              style: theme.textTheme.bodyMedium,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: onLike,
                  icon: Icon(
                    isLiked
                        ? Icons.favorite_rounded
                        : Icons.favorite_outline_rounded,
                    size: 18,
                    color: isLiked
                        ? AppTheme.error
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  label: Text(
                    (entry['likes'] as int).toString(),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: isLiked
                          ? AppTheme.error
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                TextButton.icon(
                  onPressed: () {},
                  icon: Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  label: Text(
                    (entry['comments'] as int).toString(),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
