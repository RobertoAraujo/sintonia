import 'dart:math';


/// Enum representing the two supported media actions.
enum MediaActionType { updateProfilePicture, createFeedPost }

/// Result returned by the MediaProcessingService after processing a media action.
class MediaProcessingResult {
  final String status;
  final MediaActionType actionExecuted;
  final String mediaUrl;
  final String? feedPostId;
  final bool sensoryWarning;
  final String notificationMessage;

  const MediaProcessingResult({
    required this.status,
    required this.actionExecuted,
    required this.mediaUrl,
    this.feedPostId,
    required this.sensoryWarning,
    required this.notificationMessage,
  });

  Map<String, dynamic> toJson() => {
    'status': status,
    'action_executed': actionExecuted == MediaActionType.updateProfilePicture
        ? 'UPDATE_PROFILE_PICTURE'
        : 'CREATE_FEED_POST',
    'media_url': mediaUrl,
    if (feedPostId != null) 'feed_post_id': feedPostId,
    'sensory_warning': sensoryWarning,
    'notification_message': notificationMessage,
  };
}

/// Service responsible for processing media uploads for profile pictures and feed posts.
class MediaProcessingService {
  static final MediaProcessingService _instance =
      MediaProcessingService._internal();
  factory MediaProcessingService() => _instance;
  MediaProcessingService._internal();

  // Keywords that indicate high-stimulation / sensory-heavy content.
  static const List<String> _sensorySensitiveKeywords = [
    'flash',
    'strobe',
    'luzes fortes',
    'luz forte',
    'brilhante',
    'neon',
    'piscando',
    'contraste alto',
    'padrão intenso',
    'cores vibrantes',
    'explosão',
    'confete',
    'glitter',
    'faísca',
    'laser',
    'estroboscópio',
    'flickering',
    'bright lights',
    'high contrast',
    'intense pattern',
  ];

  // Explicit / violent content keywords (basic community-guidelines check).
  static const List<String> _prohibitedKeywords = [
    'violência',
    'nudez',
    'ódio',
    'gore',
    'explicit',
    'nsfw',
  ];

  /// Processes a media action and returns a [MediaProcessingResult].
  ///
  /// [actionType]     – the action to perform.
  /// [userId]         – ID of the acting user.
  /// [imageUrl]       – URL or local path of the image.
  /// [postCaption]    – caption text (required for CREATE_FEED_POST).
  /// [sensitivityTags]– optional list of sensitivity tags provided by the user.
  Future<MediaProcessingResult> process({
    required MediaActionType actionType,
    required String userId,
    required String imageUrl,
    String? postCaption,
    List<String>? sensitivityTags,
  }) async {
    // Simulate async processing (e.g., upload, moderation check).
    await Future.delayed(const Duration(milliseconds: 600));

    if (actionType == MediaActionType.updateProfilePicture) {
      return _processProfilePicture(
        userId: userId,
        imageUrl: imageUrl,
        sensitivityTags: sensitivityTags,
      );
    } else {
      return _processFeedPost(
        userId: userId,
        imageUrl: imageUrl,
        caption: postCaption ?? '',
        sensitivityTags: sensitivityTags,
      );
    }
  }

  // ─── Private helpers ───────────────────────────────────────────────────────

  MediaProcessingResult _processProfilePicture({
    required String userId,
    required String imageUrl,
    List<String>? sensitivityTags,
  }) {
    // Community-guidelines check on tags.
    final prohibited = _containsProhibited(sensitivityTags ?? []);
    if (prohibited) {
      return MediaProcessingResult(
        status: 'error',
        actionExecuted: MediaActionType.updateProfilePicture,
        mediaUrl: imageUrl,
        sensoryWarning: false,
        notificationMessage:
            'Ops! Sua foto não pôde ser atualizada pois viola as diretrizes da comunidade. '
            'Por favor, escolha uma imagem adequada. 💙',
      );
    }

    return MediaProcessingResult(
      status: 'success',
      actionExecuted: MediaActionType.updateProfilePicture,
      mediaUrl: imageUrl,
      sensoryWarning: false,
      notificationMessage:
          'Foto de perfil atualizada com sucesso! ✨ '
          'Seu novo avatar já está visível no feed e nas buscas.',
    );
  }

  MediaProcessingResult _processFeedPost({
    required String userId,
    required String imageUrl,
    required String caption,
    List<String>? sensitivityTags,
  }) {
    // Detect sensory-heavy content from caption + explicit tags.
    final hasSensoryContent = _detectSensoryContent(caption, sensitivityTags);

    // Generate a unique post ID.
    final postId =
        'post_${userId}_${DateTime.now().millisecondsSinceEpoch}_'
        '${Random().nextInt(9999)}';

    final warningNote = hasSensoryContent
        ? ' ⚠️ Um aviso de filtro sensorial foi adicionado automaticamente ao seu post.'
        : '';

    return MediaProcessingResult(
      status: 'success',
      actionExecuted: MediaActionType.createFeedPost,
      mediaUrl: imageUrl,
      feedPostId: postId,
      sensoryWarning: hasSensoryContent,
      notificationMessage:
          'Sua publicação foi compartilhada no Feed Global e no seu Perfil! 🎉'
          '$warningNote',
    );
  }

  /// Public wrapper — used by MediaUploadModal to check sensory content before posting.
  bool detectSensoryContent(String caption, List<String>? tags) =>
      _detectSensoryContent(caption, tags);

  bool _detectSensoryContent(String caption, List<String>? tags) {
    final lowerCaption = caption.toLowerCase();
    final lowerTags = (tags ?? []).map((t) => t.toLowerCase()).toList();

    for (final keyword in _sensorySensitiveKeywords) {
      if (lowerCaption.contains(keyword)) return true;
    }
    for (final tag in lowerTags) {
      for (final keyword in _sensorySensitiveKeywords) {
        if (tag.contains(keyword)) return true;
      }
    }
    return false;
  }

  bool _containsProhibited(List<String> tags) {
    final lowerTags = tags.map((t) => t.toLowerCase()).toList();
    for (final tag in lowerTags) {
      for (final kw in _prohibitedKeywords) {
        if (tag.contains(kw)) return true;
      }
    }
    return false;
  }

  /// Builds the post map expected by the feed from a successful CREATE_FEED_POST result.
  Map<String, dynamic> buildFeedPostMap({
    required MediaProcessingResult result,
    required Map<String, dynamic> authorData,
    required String caption,
    required List<String> hyperfocusTags,
  }) {
    return {
      'id':
          result.feedPostId ?? 'post_${DateTime.now().millisecondsSinceEpoch}',
      'authorId': authorData['id'] ?? 'u1',
      'authorName': authorData['name'] ?? 'Usuário',
      'authorImage': authorData['avatarUrl'] ?? '',
      'authorImageSemantic':
          authorData['avatarSemantic'] ?? 'Avatar do usuário',
      'neurodivType': authorData['neurodivType'] ?? 'TEA',
      'hyperfocusTags': hyperfocusTags,
      'content': caption,
      'imageUrl': result.mediaUrl.isNotEmpty ? result.mediaUrl : null,
      'imageSemantic': result.mediaUrl.isNotEmpty
          ? 'Imagem publicada pelo usuário'
          : null,
      'likes': 0,
      'comments': 0,
      'saves': 0,
      'timeAgo': 'agora',
      'isLiked': false,
      'isSaved': false,
      'sensoryWarning': result.sensoryWarning,
    };
  }
}
