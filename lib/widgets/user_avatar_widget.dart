import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Resolves an avatar path/URL to a full public Supabase Storage URL.
/// If [raw] is already a full URL (starts with http), it is returned as-is.
/// If [raw] is a storage path (e.g. "userId/avatar.png"), it is converted.
String resolveAvatarUrl(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '';
  final trimmed = raw.trim();
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }
  // Treat as a storage path — convert to public URL
  try {
    return Supabase.instance.client.storage
        .from('avatars')
        .getPublicUrl(trimmed);
  } catch (_) {
    return trimmed;
  }
}

/// A reusable circular avatar widget that shows the user's photo when available,
/// or a coloured initial letter (pastel background) as a fallback.
/// Handles null URLs, network errors, and loading states gracefully.
class UserAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String displayName;
  final double radius;

  const UserAvatar({
    super.key,
    this.avatarUrl,
    required this.displayName,
    this.radius = 24.0,
  });

  // Accessible pastel colours for the fallback avatar background
  static const List<Color> _pastelColors = [
    Color(0xFFC8E6C9), // Soft green
    Color(0xFFBBDEFB), // Soft blue
    Color(0xFFE1BEE7), // Soft purple
    Color(0xFFFFCCBC), // Soft coral/orange
    Color(0xFFFFF9C4), // Soft yellow
    Color(0xFFB2EBF2), // Soft cyan
    Color(0xFFF8BBD0), // Soft pink
    Color(0xFFD7CCC8), // Soft brown
  ];

  Widget _buildFallback(String initial, Color bgColor) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: bgColor,
      child: Text(
        initial,
        style: TextStyle(
          color: const Color(0xFF2C3E50),
          fontWeight: FontWeight.bold,
          fontSize: (radius * 0.8).clamp(10.0, 22.0),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = displayName.trim().isNotEmpty ? displayName.trim() : 'U';
    final initial = name[0].toUpperCase();
    final colorIndex = name.codeUnitAt(0) % _pastelColors.length;
    final bgColor = _pastelColors[colorIndex];

    // Resolve partial storage paths to full public URLs
    final resolvedUrl = resolveAvatarUrl(avatarUrl);
    final hasAvatar = resolvedUrl.isNotEmpty;

    if (!hasAvatar) {
      return _buildFallback(initial, bgColor);
    }

    final double size = radius * 2;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        resolvedUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          debugPrint('UserAvatar: failed to load ($resolvedUrl): $error');
          return _buildFallback(initial, bgColor);
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(radius),
            ),
            child: Center(
              child: SizedBox(
                width: (radius * 0.6).clamp(8.0, 16.0),
                height: (radius * 0.6).clamp(8.0, 16.0),
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: const Color(0xFF2C3E50).withAlpha(120),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Convenience function — prefer using [UserAvatar] widget directly.
Widget buildUserAvatar(
  String? avatarUrl,
  String? displayName, {
  double radius = 24,
}) {
  return UserAvatar(
    avatarUrl: avatarUrl,
    displayName: displayName ?? 'U',
    radius: radius,
  );
}
