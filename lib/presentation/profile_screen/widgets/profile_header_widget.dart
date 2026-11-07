import 'package:flutter/material.dart';

import '../../../core/app_export.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/status_badge_widget.dart';
import '../../../widgets/user_avatar_widget.dart';

class ProfileHeaderWidget extends StatelessWidget {
  final Map<String, dynamic> profile;
  final VoidCallback? onPetBadgeTap;

  const ProfileHeaderWidget({
    super.key,
    required this.profile,
    this.onPetBadgeTap,
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
    final ndType = profile['neurodivType'] as String;
    final petImageUrl =
        profile['petAvatarUrl'] as String? ?? profile['petPhotoUrl'] as String?;
    final hasPetImage = petImageUrl != null && petImageUrl.isNotEmpty;

    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // Gradient ring around avatar
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [AppTheme.primary, AppTheme.secondary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              padding: const EdgeInsets.all(3),
              child: UserAvatar(
                avatarUrl: profile['avatarUrl'] as String?,
                displayName: profile['name'] as String? ?? 'U',
                radius: 41,
              ),
            ),

            // Pet badge — bottom-right of avatar
            Positioned(
              bottom: -2,
              right: -2,
              child: GestureDetector(
                onTap: hasPetImage ? onPetBadgeTap : null,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFD7E7E3),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(31),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: hasPetImage
                        ? Hero(
                            tag: 'pet_badge_photo',
                            child: Image.network(
                              petImageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.pets,
                                size: 18,
                                color: Color(0xFF1B4D3E),
                              ),
                            ),
                          )
                        : const Icon(
                            Icons.pets,
                            size: 18,
                            color: Color(0xFF1B4D3E),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(profile['name'] as String, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          profile['username'] as String,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        StatusBadgeWidget(
          label: ndType,
          color: _neurodivColor(ndType),
          style: BadgeStyle.subtle,
        ),
        const SizedBox(height: 10),
        Text(
          profile['bio'] as String,
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
