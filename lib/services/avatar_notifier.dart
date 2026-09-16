import 'package:flutter/foundation.dart';

/// Global notifier for the current user's avatar URL.
/// When the user updates their profile picture, update this notifier
/// so all screens that display the avatar can react immediately.
class AvatarNotifier extends ValueNotifier<String> {
  static final AvatarNotifier instance = AvatarNotifier._('');

  AvatarNotifier._(super.value);

  void updateAvatar(String newUrl) {
    value = newUrl;
  }
}
