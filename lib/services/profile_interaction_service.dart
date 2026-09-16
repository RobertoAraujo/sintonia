import 'dart:math';

/// Supported action types for the profile interaction engine.
enum ProfileInteractionAction {
  updateUserProfile,
  updatePetProfile,
  addFeedComment,
}

/// Result returned by [ProfileInteractionService] after processing any action.
class ProfileInteractionResult {
  final String status;
  final ProfileInteractionAction action;
  final Map<String, dynamic> updatedFields;
  final String message;

  const ProfileInteractionResult({
    required this.status,
    required this.action,
    required this.updatedFields,
    required this.message,
  });

  Map<String, dynamic> toJson() => {
    'status': status,
    'action': _actionLabel(action),
    'updated_fields': updatedFields,
    'message': message,
  };

  static String _actionLabel(ProfileInteractionAction a) {
    switch (a) {
      case ProfileInteractionAction.updateUserProfile:
        return 'UPDATE_USER_PROFILE';
      case ProfileInteractionAction.updatePetProfile:
        return 'UPDATE_PET_PROFILE';
      case ProfileInteractionAction.addFeedComment:
        return 'ADD_FEED_COMMENT';
    }
  }
}

/// Engine that handles profile updates, pet profile management and feed comments
/// for the neurodivergent social network.
class ProfileInteractionService {
  static final ProfileInteractionService _instance =
      ProfileInteractionService._internal();
  factory ProfileInteractionService() => _instance;
  ProfileInteractionService._internal();

  // ── Safety word-lists ──────────────────────────────────────────────────────

  /// Keywords that violate community guidelines (photos / text).
  static const List<String> _prohibitedKeywords = [
    'violência',
    'violencia',
    'nudez',
    'ódio',
    'odio',
    'gore',
    'explicit',
    'nsfw',
    'agressão',
    'agressao',
    'ameaça',
    'ameaca',
    'bullying',
    'assédio',
    'assedio',
    'racismo',
    'preconceito',
    'discriminação',
    'discriminacao',
    'morte',
    'suicídio',
    'suicidio',
    'automutilação',
    'automutilacao',
  ];

  /// Aggressive / hostile language patterns for comment moderation.
  static const List<String> _aggressivePatterns = [
    'idiota',
    'burro',
    'imbecil',
    'lixo',
    'inútil',
    'inutil',
    'cala a boca',
    'vai se',
    'sua mãe',
    'sua mae',
    'fdp',
    'vsf',
    'otário',
    'otario',
    'palhaço',
    'palhaco',
    'retardado',
    'louco',
    'doido',
    'psicopata',
    'feio',
    'gordo',
    'magro demais',
  ];

  // ── Public API ─────────────────────────────────────────────────────────────

  /// UPDATE_USER_PROFILE — validates avatar URL and saves personal data.
  Future<ProfileInteractionResult> updateUserProfile({
    required String userId,
    required Map<String, dynamic> userData,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));

    final name = (userData['name'] as String? ?? '').trim();
    final bio = (userData['bio'] as String? ?? '').trim();
    final avatarUrl = (userData['avatar_url'] as String? ?? '').trim();

    // Validate avatar URL against community guidelines.
    if (avatarUrl.isNotEmpty && _containsProhibited(avatarUrl)) {
      return ProfileInteractionResult(
        status: 'error',
        action: ProfileInteractionAction.updateUserProfile,
        updatedFields: {},
        message:
            'Ops! A foto enviada não pôde ser aceita pois viola as diretrizes '
            'da nossa comunidade. Por favor, escolha uma imagem adequada. 💙',
      );
    }

    // Validate bio text.
    if (bio.isNotEmpty && _containsProhibited(bio)) {
      return ProfileInteractionResult(
        status: 'error',
        action: ProfileInteractionAction.updateUserProfile,
        updatedFields: {},
        message:
            'Sua bio contém conteúdo que não é permitido em nossa comunidade. '
            'Por favor, revise o texto e tente novamente. 💙',
      );
    }

    final updated = <String, dynamic>{};
    if (name.isNotEmpty) updated['name'] = name;
    if (bio.isNotEmpty) updated['bio'] = bio;
    if (avatarUrl.isNotEmpty) updated['avatar_url'] = avatarUrl;

    return ProfileInteractionResult(
      status: 'success',
      action: ProfileInteractionAction.updateUserProfile,
      updatedFields: updated,
      message:
          'Perfil atualizado com sucesso! ✨ '
          'Suas informações já estão visíveis para a comunidade.',
    );
  }

  /// UPDATE_PET_PROFILE — validates pet photo and saves all pet details.
  Future<ProfileInteractionResult> updatePetProfile({
    required String userId,
    required Map<String, dynamic> petData,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));

    final petId = (petData['pet_id'] as String? ?? '').trim().isEmpty
        ? 'pet_${userId}_${Random().nextInt(99999)}'
        : (petData['pet_id'] as String).trim();

    final name = (petData['name'] as String? ?? '').trim();
    final species = (petData['species'] as String? ?? '').trim();
    final breed = (petData['breed'] as String? ?? '').trim();
    final age = (petData['age'] as String? ?? '').trim();
    final role = (petData['role'] as String? ?? '').trim();
    final photoUrl = (petData['photo_url'] as String? ?? '').trim();

    // Validate pet photo URL.
    if (photoUrl.isNotEmpty && _containsProhibited(photoUrl)) {
      return ProfileInteractionResult(
        status: 'error',
        action: ProfileInteractionAction.updatePetProfile,
        updatedFields: {},
        message:
            'A foto do pet não pôde ser aceita pois viola as diretrizes '
            'da comunidade. Por favor, escolha uma imagem adequada. 🐾',
      );
    }

    final updated = <String, dynamic>{'pet_id': petId, 'owner_id': userId};
    if (name.isNotEmpty) updated['name'] = name;
    if (species.isNotEmpty) updated['species'] = species;
    if (breed.isNotEmpty) updated['breed'] = breed;
    if (age.isNotEmpty) updated['age'] = age;
    if (role.isNotEmpty) updated['role'] = role;
    if (photoUrl.isNotEmpty) updated['photo_url'] = photoUrl;

    final roleLabel = _roleFriendlyLabel(role);

    return ProfileInteractionResult(
      status: 'success',
      action: ProfileInteractionAction.updatePetProfile,
      updatedFields: updated,
      message:
          'Perfil de ${name.isNotEmpty ? name : 'seu pet'} atualizado! 🐾 '
          '${roleLabel.isNotEmpty ? 'Função: $roleLabel. ' : ''}'
          'As informações já aparecem no seu perfil público.',
    );
  }

  /// ADD_FEED_COMMENT — validates comment text for safe/friendly communication.
  Future<ProfileInteractionResult> addFeedComment({
    required String userId,
    required Map<String, dynamic> commentData,
  }) async {
    await Future.delayed(const Duration(milliseconds: 400));

    final postId = (commentData['post_id'] as String? ?? '').trim();
    final text = (commentData['text'] as String? ?? '').trim();

    if (text.isEmpty) {
      return ProfileInteractionResult(
        status: 'error',
        action: ProfileInteractionAction.addFeedComment,
        updatedFields: {},
        message: 'O comentário não pode estar vazio. Escreva algo! 💬',
      );
    }

    // Safety check — prohibited content.
    if (_containsProhibited(text)) {
      return ProfileInteractionResult(
        status: 'error',
        action: ProfileInteractionAction.addFeedComment,
        updatedFields: {},
        message:
            'Seu comentário contém conteúdo que não é permitido em nossa '
            'comunidade segura. Por favor, revise e tente novamente. 💙',
      );
    }

    // Aggressive language check.
    if (_containsAggressive(text)) {
      return ProfileInteractionResult(
        status: 'error',
        action: ProfileInteractionAction.addFeedComment,
        updatedFields: {},
        message:
            'Hmm, detectamos uma linguagem que pode ser agressiva. '
            'Nossa comunidade é um espaço seguro e acolhedor — '
            'que tal reformular com mais gentileza? 🌸',
      );
    }

    final commentId =
        'cmt_${postId}_${userId}_${DateTime.now().millisecondsSinceEpoch}';

    return ProfileInteractionResult(
      status: 'success',
      action: ProfileInteractionAction.addFeedComment,
      updatedFields: {
        'comment_id': commentId,
        'post_id': postId,
        'author_id': userId,
        'text': text,
        'created_at': DateTime.now().toIso8601String(),
      },
      message:
          'Comentário publicado! 💬 Obrigado por contribuir com a comunidade.',
    );
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  bool _containsProhibited(String input) {
    final lower = input.toLowerCase();
    return _prohibitedKeywords.any((kw) => lower.contains(kw));
  }

  bool _containsAggressive(String input) {
    final lower = input.toLowerCase();
    return _aggressivePatterns.any((p) => lower.contains(p));
  }

  String _roleFriendlyLabel(String role) {
    switch (role.toLowerCase()) {
      case 'assistance_dog':
      case 'cão de assistência':
      case 'cao de assistencia':
        return 'Cão de Assistência';
      case 'emotional_support':
      case 'suporte emocional':
        return 'Suporte Emocional';
      case 'therapy_animal':
      case 'animal de terapia':
        return 'Animal de Terapia';
      case 'pet':
      case 'pet de estimação':
      case 'pet de estimacao':
        return 'Pet de Estimação';
      default:
        return role;
    }
  }
}
