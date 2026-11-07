import 'package:flutter/material.dart';

import '../../../core/app_export.dart';
import '../../../theme/app_theme.dart';

class PetCardWidget extends StatelessWidget {
  final Map<String, dynamic> pet;

  const PetCardWidget({super.key, required this.pet});

  void _showPetImageDialog(BuildContext context) {
    final imageUrl = pet['imageUrl'] as String? ?? '';
    final petName = pet['name'] as String? ?? 'Pet';
    if (imageUrl.isEmpty) return;

    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: Stack(
            alignment: Alignment.topRight,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      petName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1B4D3E),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: InteractiveViewer(
                        child: Image.network(
                          imageUrl,
                          fit: BoxFit.contain,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return const SizedBox(
                              height: 250,
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: Color(0xFF1B4D3E),
                                ),
                              ),
                            );
                          },
                          errorBuilder: (_, __, ___) => const SizedBox(
                            height: 200,
                            child: Center(
                              child: Icon(
                                Icons.pets,
                                size: 64,
                                color: Color(0xFF1B4D3E),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: IconButton(
                  icon: const CircleAvatar(
                    backgroundColor: Colors.black54,
                    radius: 14,
                    child: Icon(Icons.close, size: 16, color: Colors.white),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imageUrl = pet['imageUrl'] as String? ?? '';

    return GestureDetector(
      onTap: () => _showPetImageDialog(context),
      child: Container(
        width: 130,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              child: imageUrl.isNotEmpty
                  ? Image.network(
                      imageUrl,
                      width: 130,
                      height: 90,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 130,
                        height: 90,
                        color: const Color(0xFFD7E7E3),
                        child: const Icon(
                          Icons.pets,
                          size: 36,
                          color: Color(0xFF1B4D3E),
                        ),
                      ),
                    )
                  : Container(
                      width: 130,
                      height: 90,
                      color: const Color(0xFFD7E7E3),
                      child: const Icon(
                        Icons.pets,
                        size: 36,
                        color: Color(0xFF1B4D3E),
                      ),
                    ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pet['name'] as String? ?? '',
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${pet['species']} · ${pet['age']}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.book_outlined,
                          size: 11,
                          color: AppTheme.primary,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${pet['entriesCount']} entradas',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
