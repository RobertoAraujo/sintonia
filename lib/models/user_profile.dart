/// Represents the neurological/cognitive profile types of a user.
enum Neurotype {
  adhd,
  asd,
  dyslexia,
  giftedHighAbility,
  dyscalculia,
  dyspraxia,
  tourette,
  anxiety,
  depression,
  bipolar,
  neurotypical,
}

/// Preferred communication styles.
enum CommunicationStyle {
  shortText,
  longText,
  audio,
  video,
  directMessages,
  asyncMessages,
  emojiHeavy,
  formalTone,
  informalTone,
}

/// A user profile containing all fields used for compatibility scoring.
class UserProfile {
  final String id;
  final String displayName;
  final String? avatarUrl;
  final String? bio;

  /// Neurological/cognitive conditions the user identifies with.
  final List<Neurotype> neurotypes;

  /// Topics/areas the user hyperfocuses on or is deeply passionate about.
  final List<String> hyperfocusInterests;

  /// Preferred ways of communicating.
  final List<CommunicationStyle> communicationStyles;

  /// Tags representing values, moral/social ideas, and lifestyle preferences.
  final List<String> valuesAndIdeas;

  const UserProfile({
    required this.id,
    required this.displayName,
    this.avatarUrl,
    this.bio,
    List<Neurotype>? neurotypes,
    List<String>? hyperfocusInterests,
    List<CommunicationStyle>? communicationStyles,
    List<String>? valuesAndIdeas,
  }) : neurotypes = neurotypes ?? const [],
       hyperfocusInterests = hyperfocusInterests ?? const [],
       communicationStyles = communicationStyles ?? const [],
       valuesAndIdeas = valuesAndIdeas ?? const [];

  /// Creates a copy of this profile with optional field overrides.
  UserProfile copyWith({
    String? id,
    String? displayName,
    String? avatarUrl,
    String? bio,
    List<Neurotype>? neurotypes,
    List<String>? hyperfocusInterests,
    List<CommunicationStyle>? communicationStyles,
    List<String>? valuesAndIdeas,
  }) {
    return UserProfile(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bio: bio ?? this.bio,
      neurotypes: neurotypes ?? this.neurotypes,
      hyperfocusInterests: hyperfocusInterests ?? this.hyperfocusInterests,
      communicationStyles: communicationStyles ?? this.communicationStyles,
      valuesAndIdeas: valuesAndIdeas ?? this.valuesAndIdeas,
    );
  }

  /// Deserializes a [UserProfile] from a JSON map.
  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String?,
      bio: json['bio'] as String?,
      neurotypes:
          (json['neurotypes'] as List<dynamic>?)
              ?.map((e) => _neurotypFromString(e as String))
              .whereType<Neurotype>()
              .toList() ??
          [],
      hyperfocusInterests:
          (json['hyperfocusInterests'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      communicationStyles:
          (json['communicationStyles'] as List<dynamic>?)
              ?.map((e) => _commStyleFromString(e as String))
              .whereType<CommunicationStyle>()
              .toList() ??
          [],
      valuesAndIdeas:
          (json['valuesAndIdeas'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }

  /// Serializes this profile to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'displayName': displayName,
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
      if (bio != null) 'bio': bio,
      'neurotypes': neurotypes.map((e) => e.name).toList(),
      'hyperfocusInterests': hyperfocusInterests,
      'communicationStyles': communicationStyles.map((e) => e.name).toList(),
      'valuesAndIdeas': valuesAndIdeas,
    };
  }

  static Neurotype? _neurotypFromString(String value) {
    try {
      return Neurotype.values.firstWhere((e) => e.name == value);
    } catch (_) {
      return null;
    }
  }

  static CommunicationStyle? _commStyleFromString(String value) {
    try {
      return CommunicationStyle.values.firstWhere((e) => e.name == value);
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is UserProfile && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'UserProfile(id: $id, displayName: $displayName)';
}
