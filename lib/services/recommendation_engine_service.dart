import 'dart:isolate' if (dart.library.html) 'dart:async';
import 'dart:isolate' as isolate_lib;
import 'package:flutter/foundation.dart';
import '../models/user_profile.dart';
import '../models/profile_match_result.dart';

/// Weights used in the compatibility scoring formula.
const double _wInterests = 0.40;
const double _wValues = 0.35;
const double _wNeurotypes = 0.15;
const double _wCommunication = 0.10;

/// Pure service that calculates compatibility scores between [UserProfile]s.
///
/// All heavy list operations are safe against null lists and division-by-zero.
/// For large candidate sets (> 200 profiles) use [getRecommendedProfilesAsync]
/// which offloads computation to a Dart Isolate on native platforms.
/// On Flutter Web, it falls back to synchronous computation (Isolate.run is unsupported).
class RecommendationEngineService {
  const RecommendationEngineService();

  // ─────────────────────────────────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns a compatibility score between 0.0 and 1.0 for two profiles.
  double calculateMatchScore(UserProfile userA, UserProfile userB) {
    final interests = _jaccardSimilarity(
      userA.hyperfocusInterests.map((e) => e.toLowerCase().trim()).toSet(),
      userB.hyperfocusInterests.map((e) => e.toLowerCase().trim()).toSet(),
    );

    final values = _jaccardSimilarity(
      userA.valuesAndIdeas.map((e) => e.toLowerCase().trim()).toSet(),
      userB.valuesAndIdeas.map((e) => e.toLowerCase().trim()).toSet(),
    );

    final neurotypes = _neurotypeSimilarity(
      userA.neurotypes.toSet(),
      userB.neurotypes.toSet(),
    );

    final communication = _jaccardSimilarity(
      userA.communicationStyles.toSet(),
      userB.communicationStyles.toSet(),
    );

    return (interests * _wInterests) +
        (values * _wValues) +
        (neurotypes * _wNeurotypes) +
        (communication * _wCommunication);
  }

  /// Convenience wrapper that returns the score as a percentage (0 – 100).
  double calculateMatchPercentage(UserProfile userA, UserProfile userB) =>
      (calculateMatchScore(userA, userB) * 100).clamp(0.0, 100.0);

  /// Scores all [candidateProfiles] against [currentUser], sorts by score
  /// descending, and returns the top [limit] results.
  List<ProfileMatchResult> getRecommendedProfiles({
    required UserProfile currentUser,
    required List<UserProfile> candidateProfiles,
    int limit = 20,
  }) {
    if (candidateProfiles.isEmpty) return [];

    final results =
        candidateProfiles
            .where((p) => p.id != currentUser.id)
            .map((candidate) => _buildResult(currentUser, candidate))
            .toList()
          ..sort();

    return results.take(limit).toList();
  }

  /// Async version that offloads scoring to a Dart Isolate on native platforms.
  /// On Flutter Web, falls back to synchronous computation wrapped in a Future
  /// because [Isolate.run] is not supported on web.
  Future<List<ProfileMatchResult>> getRecommendedProfilesAsync({
    required UserProfile currentUser,
    required List<UserProfile> candidateProfiles,
    int limit = 20,
  }) async {
    if (candidateProfiles.isEmpty) return [];

    // Flutter Web does not support Isolate.run — run synchronously instead.
    if (kIsWeb) {
      return getRecommendedProfiles(
        currentUser: currentUser,
        candidateProfiles: candidateProfiles,
        limit: limit,
      );
    }

    final payload = _IsolatePayload(
      currentUser: currentUser,
      candidates: candidateProfiles,
      limit: limit,
    );

    return await isolate_lib.Isolate.run(() => _computeInIsolate(payload));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Private helpers
  // ─────────────────────────────────────────────────────────────────────────

  ProfileMatchResult _buildResult(UserProfile a, UserProfile b) {
    final interests = _jaccardSimilarity(
      a.hyperfocusInterests.map((e) => e.toLowerCase().trim()).toSet(),
      b.hyperfocusInterests.map((e) => e.toLowerCase().trim()).toSet(),
    );
    final values = _jaccardSimilarity(
      a.valuesAndIdeas.map((e) => e.toLowerCase().trim()).toSet(),
      b.valuesAndIdeas.map((e) => e.toLowerCase().trim()).toSet(),
    );
    final neurotypes = _neurotypeSimilarity(
      a.neurotypes.toSet(),
      b.neurotypes.toSet(),
    );
    final communication = _jaccardSimilarity(
      a.communicationStyles.toSet(),
      b.communicationStyles.toSet(),
    );

    final score =
        (interests * _wInterests) +
        (values * _wValues) +
        (neurotypes * _wNeurotypes) +
        (communication * _wCommunication);

    return ProfileMatchResult(
      profile: b,
      matchScore: score.clamp(0.0, 1.0),
      interestsScore: interests,
      valuesScore: values,
      neurotypesScore: neurotypes,
      communicationScore: communication,
    );
  }

  /// Standard Jaccard similarity: |A ∩ B| / |A ∪ B|.
  double _jaccardSimilarity<T>(Set<T> a, Set<T> b) {
    if (a.isEmpty && b.isEmpty) return 0.0;
    final intersection = a.intersection(b).length;
    final union = a.union(b).length;
    if (union == 0) return 0.0;
    return intersection / union;
  }

  /// Neurotype similarity with a complementary bonus.
  double _neurotypeSimilarity(Set<Neurotype> a, Set<Neurotype> b) {
    if (a.isEmpty && b.isEmpty) return 0.0;

    final jaccard = _jaccardSimilarity(a, b);

    final aHasNT = a.contains(Neurotype.neurotypical);
    final bHasNT = b.contains(Neurotype.neurotypical);
    final complementaryBonus =
        (aHasNT != bHasNT && (a.length > 1 || b.length > 1)) ? 0.2 : 0.0;

    return (jaccard + complementaryBonus).clamp(0.0, 1.0);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Isolate helpers (top-level so they can be passed to Isolate.run)
// ─────────────────────────────────────────────────────────────────────────────

class _IsolatePayload {
  final UserProfile currentUser;
  final List<UserProfile> candidates;
  final int limit;

  const _IsolatePayload({
    required this.currentUser,
    required this.candidates,
    required this.limit,
  });
}

List<ProfileMatchResult> _computeInIsolate(_IsolatePayload payload) {
  const engine = RecommendationEngineService();
  return engine.getRecommendedProfiles(
    currentUser: payload.currentUser,
    candidateProfiles: payload.candidates,
    limit: payload.limit,
  );
}