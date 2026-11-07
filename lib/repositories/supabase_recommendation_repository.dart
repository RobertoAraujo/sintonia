import 'package:flutter/foundation.dart';
import '../models/user_profile.dart';
import '../models/profile_match_result.dart';
import '../services/recommendation_engine_service.dart';
import '../services/supabase_service.dart';
import '../services/gemini_recommendation_service.dart';

/// Supabase-backed recommendation repository.
///
/// Fetches real user profiles from the database, maps them to [UserProfile]
/// objects, scores them using [RecommendationEngineService], and then refines
/// the rankings with [GeminiRecommendationService] for higher-quality matches.
class SupabaseRecommendationRepository {
  final RecommendationEngineService _engine;
  final GeminiRecommendationService _gemini;

  const SupabaseRecommendationRepository({
    RecommendationEngineService engine = const RecommendationEngineService(),
    GeminiRecommendationService gemini = const GeminiRecommendationService(),
  }) : _engine = engine,
       _gemini = gemini;

  // ─────────────────────────────────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────────────────────────────────

  /// Fetches the current user's profile from Supabase and converts it to
  /// a [UserProfile] for use as the scoring baseline.
  Future<UserProfile?> fetchCurrentUserProfile() async {
    try {
      final data = await SupabaseService.instance.fetchCurrentUserProfile();
      if (data == null) return null;
      return _mapDbRowToUserProfile(data);
    } catch (e) {
      debugPrint(
        'SupabaseRecommendationRepository.fetchCurrentUserProfile: $e',
      );
      return null;
    }
  }

  /// Fetches candidate profiles (all active users except the current user)
  /// and returns them as [UserProfile] objects.
  Future<List<UserProfile>> fetchCandidateProfiles() async {
    try {
      final uid = SupabaseService.instance.currentUserId;
      if (uid == null) return [];

      final client = SupabaseService.instance.client;
      final data = await client
          .from('user_profiles')
          .select(
            'id, full_name, avatar_url, bio, neurodiv_type, '
            'hyperfocuses, interests, communication_styles, values_and_ideas, '
            'communication_preferences',
          )
          .eq('is_active', true)
          .neq('id', uid)
          .limit(200);

      return (data as List<dynamic>)
          .map((row) => _mapDbRowToUserProfile(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('SupabaseRecommendationRepository.fetchCandidateProfiles: $e');
      return [];
    }
  }

  /// Fetches candidates, scores them against [currentUser], and returns
  /// the top [limit] results sorted by compatibility descending.
  ///
  /// Tries the server-side `get_recommended_connections` RPC first (uses the
  /// PostgreSQL Haversine + weighted compatibility function for ordering).
  /// Falls back to the legacy `get_compatible_users` RPC, then client-side scoring.
  /// After initial scoring, refines rankings using Gemini AI analysis.
  Future<List<ProfileMatchResult>> fetchRecommendations({
    required UserProfile currentUser,
    int limit = 20,
  }) async {
    List<ProfileMatchResult> initialResults = [];

    // ── Try new get_recommended_connections RPC first ─────────────────────
    try {
      final uid = SupabaseService.instance.currentUserId;
      if (uid != null) {
        final rows = await SupabaseService.instance.client.rpc(
          'get_recommended_connections',
          params: {'current_user_id': uid, 'max_distance_km': 50.0},
        );
        if (rows is List && rows.isNotEmpty) {
          final results = <ProfileMatchResult>[];
          for (final row in rows) {
            final r = row as Map<String, dynamic>;
            final hyperfocusList = _jsonListToStrings(r['hyperfocus']);
            final interestsList = _jsonListToStrings(r['interests']);
            final profile = UserProfile(
              id: (r['user_id'] as String?) ?? '',
              displayName: (r['display_name'] as String?) ?? 'Usuário',
              avatarUrl: r['avatar_url'] as String?,
              bio: r['bio'] as String?,
              neurotypes: [],
              hyperfocusInterests: [...hyperfocusList, ...interestsList],
              communicationStyles: [],
              valuesAndIdeas: [],
            );
            final pct = (r['compatibility_score'] as int? ?? 30).toDouble();
            final distKm = r['distance_km'] as double?;
            results.add(
              ProfileMatchResult(
                profile: profile,
                matchScore: pct / 100,
                interestsScore: pct / 100,
                valuesScore: 0,
                neurotypesScore: 0,
                communicationScore: 0,
                distanceKm: distKm,
              ),
            );
          }
          initialResults = results;
        }
      }
    } catch (e) {
      debugPrint(
        'SupabaseRecommendationRepository: RPC get_recommended_connections failed, '
        'trying legacy RPC. Error: $e',
      );
    }

    // ── Try legacy get_compatible_users RPC ───────────────────────────────
    if (initialResults.isEmpty) {
      try {
        final uid = SupabaseService.instance.currentUserId;
        if (uid != null) {
          final rows = await SupabaseService.instance.client.rpc(
            'get_compatible_users',
            params: {'requesting_user_id': uid, 'result_limit': limit},
          );
          if (rows is List && rows.isNotEmpty) {
            final results = <ProfileMatchResult>[];
            for (final row in rows) {
              final r = row as Map<String, dynamic>;
              final profile = _mapDbRowToUserProfile({
                'id': r['user_id'],
                'full_name': r['full_name'],
                'avatar_url': r['avatar_url'],
                'bio': r['bio'],
                'neurodiv_type': r['neurodiv_type'],
                'hyperfocuses': r['hyperfocuses'],
                'interests': r['interests'],
                'communication_preferences': r['communication_preferences'],
              });
              final pct = (r['compatibility_pct'] as int? ?? 0).toDouble();
              results.add(
                ProfileMatchResult(
                  profile: profile,
                  matchScore: pct / 100,
                  interestsScore: pct / 100,
                  valuesScore: 0,
                  neurotypesScore: 0,
                  communicationScore: 0,
                ),
              );
            }
            initialResults = results;
          }
        }
      } catch (e) {
        debugPrint(
          'SupabaseRecommendationRepository: RPC get_compatible_users failed, '
          'falling back to client-side scoring. Error: $e',
        );
      }
    }

    // ── Client-side fallback ──────────────────────────────────────────────
    if (initialResults.isEmpty) {
      final candidates = await fetchCandidateProfiles();
      if (candidates.isEmpty) return [];

      if (candidates.length > 50) {
        initialResults = await _engine.getRecommendedProfilesAsync(
          currentUser: currentUser,
          candidateProfiles: candidates,
          limit: limit,
        );
      } else {
        initialResults = _engine.getRecommendedProfiles(
          currentUser: currentUser,
          candidateProfiles: candidates,
          limit: limit,
        );
      }
    }

    // ── Gemini AI refinement ──────────────────────────────────────────────
    try {
      final refined = await _gemini.refineRankings(
        currentUser: currentUser,
        candidates: initialResults,
        maxCandidates: limit,
      );
      return refined;
    } catch (e) {
      debugPrint(
        'SupabaseRecommendationRepository: Gemini refinement failed, '
        'returning initial results. Error: $e',
      );
      return initialResults;
    }
  }

  /// Converts a dynamic JSON list (from Supabase) to a List<String>.
  /// Handles both plain strings and Map objects (extracts the 'name' field).
  List<String> _jsonListToStrings(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) {
      return raw
          .map((e) {
            if (e is Map) {
              // Extract 'name' field if present, otherwise try 'label' or 'title'
              final name = e['name'] ?? e['label'] ?? e['title'];
              return name?.toString() ?? '';
            }
            return e.toString();
          })
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return [];
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Mapping helpers
  // ─────────────────────────────────────────────────────────────────────────

  UserProfile _mapDbRowToUserProfile(Map<String, dynamic> row) {
    return UserProfile(
      id: row['id'] as String? ?? '',
      displayName: row['full_name'] as String? ?? 'Usuário',
      avatarUrl: row['avatar_url'] as String?,
      bio: row['bio'] as String?,
      neurotypes: _parseNeurotypes(row),
      hyperfocusInterests:
          _parseStringList(row, 'hyperfocuses') +
          _parseStringList(row, 'interests'),
      communicationStyles: _parseCommunicationStyles(row),
      valuesAndIdeas: _parseStringList(row, 'values_and_ideas'),
    );
  }

  /// Parses the neurodiv_type DB field into [Neurotype] enum values.
  List<Neurotype> _parseNeurotypes(Map<String, dynamic> row) {
    final raw = row['neurodiv_type'];
    if (raw == null) return [];

    // DB stores a single enum value as string
    final typeStr = raw.toString().toLowerCase().trim();
    final mapped = _neurodivStringToNeurotype(typeStr);
    return mapped != null ? [mapped] : [];
  }

  Neurotype? _neurodivStringToNeurotype(String value) {
    switch (value) {
      case 'tdah':
        return Neurotype.adhd;
      case 'tea':
        return Neurotype.asd;
      case 'dislexia':
        return Neurotype.dyslexia;
      case 'superdotacao':
        return Neurotype.giftedHighAbility;
      case 'discalculia':
        return Neurotype.dyscalculia;
      case 'tourette':
        return Neurotype.tourette;
      case 'toc':
        return Neurotype.anxiety;
      default:
        return null;
    }
  }

  /// Parses a JSONB array column into a list of strings.
  List<String> _parseStringList(Map<String, dynamic> row, String key) {
    final raw = row[key];
    if (raw == null) return [];
    if (raw is List) {
      return raw
          .map((e) {
            if (e is Map) {
              final name = e['name'] ?? e['label'] ?? e['title'];
              return name?.toString() ?? '';
            }
            return e.toString();
          })
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return [];
  }

  /// Parses communication styles from either `communication_styles` JSONB
  /// or falls back to `communication_preferences` JSONB object.
  List<CommunicationStyle> _parseCommunicationStyles(Map<String, dynamic> row) {
    // Try direct communication_styles array first
    final stylesRaw = row['communication_styles'];
    if (stylesRaw is List && stylesRaw.isNotEmpty) {
      return stylesRaw
          .map((e) => _commStyleFromString(e.toString()))
          .whereType<CommunicationStyle>()
          .toList();
    }

    // Fall back to communication_preferences object keys
    final prefsRaw = row['communication_preferences'];
    if (prefsRaw is Map) {
      final styles = <CommunicationStyle>[];
      if (prefsRaw['prefers_text'] == true) {
        styles.add(CommunicationStyle.shortText);
      }
      if (prefsRaw['prefers_audio'] == true) {
        styles.add(CommunicationStyle.audio);
      }
      if (prefsRaw['prefers_video'] == true) {
        styles.add(CommunicationStyle.video);
      }
      if (prefsRaw['prefers_async'] == true) {
        styles.add(CommunicationStyle.asyncMessages);
      }
      return styles;
    }

    return [];
  }

  CommunicationStyle? _commStyleFromString(String value) {
    try {
      return CommunicationStyle.values.firstWhere(
        (e) => e.name.toLowerCase() == value.toLowerCase(),
      );
    } catch (_) {
      return null;
    }
  }
}
