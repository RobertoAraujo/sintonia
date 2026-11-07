import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';

import '../../../core/app_export.dart';
import '../../../widgets/status_badge_widget.dart';

class FriendRequestCardWidget extends StatelessWidget {
  final Map<String, dynamic> request;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback? onTap;

  const FriendRequestCardWidget({
    super.key,
    required this.request,
    required this.onAccept,
    required this.onDecline,
    this.onTap,
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
    final compat = request['compatibilityPct'] as int? ?? 0;
    final timeAgo = request['timeAgo'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18.0),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withAlpha(50),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(22),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18.0),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18.0),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: avatar + info
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Avatar
                    GestureDetector(
                      onTap: onTap,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppTheme.primary.withAlpha(60),
                            width: 2,
                          ),
                        ),
                        child: ClipOval(
                          child: CustomImageWidget(
                            imageUrl: request['imageUrl'] as String,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            semanticLabel: request['imageSemantic'] as String,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    // Name + badge + meta
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  request['name'] as String,
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14.sp,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              StatusBadgeWidget(
                                label: ndType,
                                color: _neurodivColor(ndType),
                                style: BadgeStyle.subtle,
                                fontSize: 10,
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withAlpha(22),
                                  borderRadius: BorderRadius.circular(20.0),
                                ),
                                child: Text(
                                  '$compat% compatível',
                                  style: GoogleFonts.inter(
                                    fontSize: 10.sp,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.primary,
                                  ),
                                ),
                              ),
                              if (timeAgo.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Text(
                                  timeAgo,
                                  style: GoogleFonts.inter(
                                    fontSize: 10.sp,
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Divider
                Divider(
                  height: 1,
                  thickness: 1,
                  color: theme.colorScheme.outlineVariant.withAlpha(40),
                ),
                const SizedBox(height: 14),
                // Action buttons — full width, side by side
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: onAccept,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          minimumSize: const Size(0, 40),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.0),
                          ),
                          elevation: 0,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.check_rounded,
                              size: 16,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Aceitar',
                              style: GoogleFonts.inter(
                                fontSize: 13.sp,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onDecline,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.colorScheme.onSurfaceVariant,
                          side: BorderSide(
                            color: theme.colorScheme.outlineVariant.withAlpha(
                              120,
                            ),
                          ),
                          minimumSize: const Size(0, 40),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.0),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.close_rounded,
                              size: 16,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Recusar',
                              style: GoogleFonts.inter(
                                fontSize: 13.sp,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
