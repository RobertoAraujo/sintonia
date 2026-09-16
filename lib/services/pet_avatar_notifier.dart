import 'package:flutter/foundation.dart';


/// Global notifier for the current user's primary pet avatar URL.
/// When the user updates their pet photo in EditPetModal, update this notifier
/// so the profile screen overlay reacts immediately.
class PetAvatarNotifier extends ValueNotifier<String> {
  static final PetAvatarNotifier instance = PetAvatarNotifier._('');

  PetAvatarNotifier._(super.value);

  void updatePetAvatar(String newUrl) {
    value = newUrl;
  }
}
