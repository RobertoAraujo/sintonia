import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/user_profile.dart';
import '../models/profile_match_result.dart';
import '../services/recommendation_engine_service.dart';

/// Abstract contract for the recommendation data layer.
abstract class RecommendationRepository {
  /// Fetches candidate profiles for [currentUser] and returns ranked results.
  Future<List<ProfileMatchResult>> fetchRecommendations({
    required UserProfile currentUser,
    int limit = 20,
  });

  /// Fetches all available candidate profiles (raw, unscored).
  Future<List<UserProfile>> fetchCandidateProfiles();
}

// ─────────────────────────────────────────────────────────────────────────────
// HTTP implementation (ready for real backend)
// ─────────────────────────────────────────────────────────────────────────────

/// HTTP-backed repository.  Replace [_baseUrl] with your actual API endpoint.
class HttpRecommendationRepository implements RecommendationRepository {
  final Dio _dio;
  final RecommendationEngineService _engine;

  static const String _baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.sintonia.app',
  );

  HttpRecommendationRepository({
    Dio? dio,
    RecommendationEngineService engine = const RecommendationEngineService(),
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: _baseUrl,
               connectTimeout: const Duration(seconds: 10),
               receiveTimeout: const Duration(seconds: 15),
             ),
           ),
       _engine = engine;

  @override
  Future<List<UserProfile>> fetchCandidateProfiles() async {
    try {
      final response = await _dio.get<List<dynamic>>('/profiles/candidates');
      final data = response.data ?? [];
      return data
          .map((json) => UserProfile.fromJson(json as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw RecommendationRepositoryException(
        'Failed to fetch candidate profiles: ${e.message}',
        cause: e,
      );
    }
  }

  @override
  Future<List<ProfileMatchResult>> fetchRecommendations({
    required UserProfile currentUser,
    int limit = 20,
  }) async {
    try {
      // Try server-side recommendations first.
      final response = await _dio.post<List<dynamic>>(
        '/profiles/recommendations',
        data: jsonEncode({'currentUser': currentUser.toJson(), 'limit': limit}),
      );

      final data = response.data ?? [];
      if (data.isNotEmpty) {
        // Server returned pre-scored results — parse them.
        return data.map((json) {
          final map = json as Map<String, dynamic>;
          return ProfileMatchResult(
            profile: UserProfile.fromJson(
              map['profile'] as Map<String, dynamic>,
            ),
            matchScore: (map['matchScore'] as num?)?.toDouble() ?? 0.0,
            interestsScore: (map['interestsScore'] as num?)?.toDouble() ?? 0.0,
            valuesScore: (map['valuesScore'] as num?)?.toDouble() ?? 0.0,
            neurotypesScore:
                (map['neurotypesScore'] as num?)?.toDouble() ?? 0.0,
            communicationScore:
                (map['communicationScore'] as num?)?.toDouble() ?? 0.0,
          );
        }).toList();
      }

      // Fallback: fetch raw candidates and score locally.
      final candidates = await fetchCandidateProfiles();
      return _engine.getRecommendedProfilesAsync(
        currentUser: currentUser,
        candidateProfiles: candidates,
        limit: limit,
      );
    } on DioException catch (e) {
      throw RecommendationRepositoryException(
        'Failed to fetch recommendations: ${e.message}',
        cause: e,
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Exception
// ─────────────────────────────────────────────────────────────────────────────

class RecommendationRepositoryException implements Exception {
  final String message;
  final Object? cause;

  const RecommendationRepositoryException(this.message, {this.cause});

  @override
  String toString() => 'RecommendationRepositoryException: $message';
}
