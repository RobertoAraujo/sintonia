import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../core/services/aiIntegrations/chat_completion_service.dart';
import '../models/profile_match_result.dart';
import '../models/user_profile.dart';

/// Uses Gemini (via AWS Lambda) to refine friend suggestion rankings.
///
/// Takes the top candidates already scored by [RecommendationEngineService]
/// and asks Gemini to re-rank them with deeper analysis of:
/// - Shared hyperfocus depth and quality
/// - Communication style compatibility for neurodivergent users
/// - Neurodivergence type alignment and complementary dynamics
///
/// Falls back to the original order if the AI call fails.
class GeminiRecommendationService {
  const GeminiRecommendationService();

  static const String _provider = 'GEMINI';
  static const String _model = 'gemini/gemini-3.7-flash';

  /// Refines [candidates] ranking using Gemini analysis.
  ///
  /// [currentUser] is the logged-in user.
  /// [candidates] should already be pre-scored and sorted (best first).
  /// Returns a re-ranked list with an updated [matchScore] and an
  /// optional [aiInsight] string added to each result's profile bio.
  Future<List<ProfileMatchResult>> refineRankings({
    required UserProfile currentUser,
    required List<ProfileMatchResult> candidates,
    int maxCandidates = 20,
  }) async {
    if (candidates.isEmpty) return candidates;

    // Only send the top slice to Gemini to keep the prompt concise.
    final slice = candidates.take(maxCandidates).toList();

    try {
      final prompt = _buildPrompt(currentUser, slice);

      final response = await getChatCompletion(
        _provider,
        _model,
        [
          {
            'role': 'system',
            'content':
                'Você é um especialista em compatibilidade para pessoas neurodivergentes. '
                'Analise perfis e retorne APENAS JSON válido, sem markdown, sem explicações.',
          },
          {'role': 'user', 'content': prompt},
        ],
        parameters: {
          'temperature': 0.3,
          'max_tokens': 2000,
          'response_format': {
            'type': 'json_schema',
            'json_schema': {
              'name': 'refined_rankings',
              'schema': {
                'type': 'object',
                'properties': {
                  'rankings': {
                    'type': 'array',
                    'items': {
                      'type': 'object',
                      'properties': {
                        'id': {'type': 'string'},
                        'aiScore': {
                          'type': 'number',
                          'description':
                              'Score de 0.0 a 1.0 baseado na análise de IA',
                        },
                        'insight': {
                          'type': 'string',
                          'description':
                              'Frase curta (máx 60 chars) explicando a compatibilidade',
                        },
                        'hyperfocusDepth': {
                          'type': 'number',
                          'description': 'Profundidade de hiperfocuses 0.0-1.0',
                        },
                        'commCompatibility': {
                          'type': 'number',
                          'description':
                              'Compatibilidade de comunicação 0.0-1.0',
                        },
                        'neurodivAlignment': {
                          'type': 'number',
                          'description': 'Alinhamento de neurotipo 0.0-1.0',
                        },
                      },
                      'required': [
                        'id',
                        'aiScore',
                        'insight',
                        'hyperfocusDepth',
                        'commCompatibility',
                        'neurodivAlignment',
                      ],
                    },
                  },
                },
                'required': ['rankings'],
              },
              'strict': true,
            },
          },
        },
      );

      final content =
          response['choices']?[0]?['message']?['content'] as String?;
      if (content == null || content.isEmpty) return candidates;

      return _applyAiRankings(slice, content, candidates);
    } catch (e) {
      debugPrint('GeminiRecommendationService: AI refinement failed — $e');
      return candidates;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Prompt builder
  // ─────────────────────────────────────────────────────────────────────────

  String _buildPrompt(UserProfile user, List<ProfileMatchResult> candidates) {
    final userJson = {
      'neurotypes': user.neurotypes.map((n) => _neurotypeName(n)).toList(),
      'hyperfocuses': user.hyperfocusInterests,
      'communicationStyles': user.communicationStyles
          .map((c) => _commStyleName(c))
          .toList(),
      'values': user.valuesAndIdeas,
    };

    final candidatesJson = candidates.map((r) {
      final p = r.profile;
      return {
        'id': p.id,
        'neurotypes': p.neurotypes.map((n) => _neurotypeName(n)).toList(),
        'hyperfocuses': p.hyperfocusInterests,
        'communicationStyles': p.communicationStyles
            .map((c) => _commStyleName(c))
            .toList(),
        'values': p.valuesAndIdeas,
        'baseScore': r.matchScore,
      };
    }).toList();

    return '''
Analise a compatibilidade entre o usuário principal e os candidatos abaixo.
Considere especialmente:
1. HIPERFOCUSES: profundidade e qualidade dos interesses em comum (não apenas quantidade)
2. COMUNICAÇÃO: se os estilos de comunicação são complementares para pessoas neurodivergentes
3. NEUROTIPO: dinâmicas de alinhamento e complementaridade entre tipos neurodivergentes

Usuário principal:
${jsonEncode(userJson)}

Candidatos (${candidates.length} perfis):
${jsonEncode(candidatesJson)}

Retorne um JSON com rankings refinados. O aiScore deve combinar o baseScore (peso 40%) com sua análise qualitativa (peso 60%).
''';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Apply AI rankings back to ProfileMatchResult list
  // ─────────────────────────────────────────────────────────────────────────

  List<ProfileMatchResult> _applyAiRankings(
    List<ProfileMatchResult> slice,
    String jsonContent,
    List<ProfileMatchResult> allCandidates,
  ) {
    try {
      final parsed = jsonDecode(jsonContent) as Map<String, dynamic>;
      final rankings = parsed['rankings'] as List<dynamic>;

      // Build a lookup map: id → AI data
      final aiMap = <String, Map<String, dynamic>>{};
      for (final item in rankings) {
        final r = item as Map<String, dynamic>;
        final id = r['id'] as String?;
        if (id != null) aiMap[id] = r;
      }

      // Re-score the slice with AI data
      final refined = slice.map((result) {
        final ai = aiMap[result.profile.id];
        if (ai == null) return result;

        final aiScore =
            (ai['aiScore'] as num?)?.toDouble() ?? result.matchScore;
        final insight = ai['insight'] as String? ?? '';
        final hyperfocusDepth =
            (ai['hyperfocusDepth'] as num?)?.toDouble() ??
            result.interestsScore;
        final commCompat =
            (ai['commCompatibility'] as num?)?.toDouble() ??
            result.communicationScore;
        final neurodivAlign =
            (ai['neurodivAlignment'] as num?)?.toDouble() ??
            result.neurotypesScore;

        // Blend original score with AI score (60/40)
        final blendedScore = (aiScore * 0.6 + result.matchScore * 0.4).clamp(
          0.0,
          1.0,
        );

        // Attach insight to bio via a new profile copy
        final updatedProfile = result.profile.copyWith(
          bio: insight.isNotEmpty ? insight : result.profile.bio,
        );

        return ProfileMatchResult(
          profile: updatedProfile,
          matchScore: blendedScore,
          interestsScore: hyperfocusDepth,
          valuesScore: result.valuesScore,
          neurotypesScore: neurodivAlign,
          communicationScore: commCompat,
          aiInsight: insight,
          aiRefined: true,
        );
      }).toList()..sort();

      // Append any candidates beyond the slice (unchanged)
      final sliceIds = slice.map((r) => r.profile.id).toSet();
      final remainder = allCandidates
          .where((r) => !sliceIds.contains(r.profile.id))
          .toList();

      return [...refined, ...remainder];
    } catch (e) {
      debugPrint(
        'GeminiRecommendationService: Failed to parse AI response — $e',
      );
      return allCandidates;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Enum → display string helpers
  // ─────────────────────────────────────────────────────────────────────────

  String _neurotypeName(Neurotype n) {
    switch (n) {
      case Neurotype.adhd:
        return 'TDAH';
      case Neurotype.asd:
        return 'TEA';
      case Neurotype.dyslexia:
        return 'Dislexia';
      case Neurotype.giftedHighAbility:
        return 'AH/SD';
      case Neurotype.dyscalculia:
        return 'Discalculia';
      case Neurotype.dyspraxia:
        return 'Dispraxia';
      case Neurotype.tourette:
        return 'Tourette';
      case Neurotype.anxiety:
        return 'Ansiedade';
      case Neurotype.depression:
        return 'Depressão';
      case Neurotype.bipolar:
        return 'Bipolar';
      case Neurotype.neurotypical:
        return 'NT';
    }
  }

  String _commStyleName(CommunicationStyle c) {
    switch (c) {
      case CommunicationStyle.shortText:
        return 'Texto curto';
      case CommunicationStyle.longText:
        return 'Texto longo';
      case CommunicationStyle.audio:
        return 'Áudio';
      case CommunicationStyle.video:
        return 'Vídeo';
      case CommunicationStyle.directMessages:
        return 'Mensagens diretas';
      case CommunicationStyle.asyncMessages:
        return 'Mensagens assíncronas';
      case CommunicationStyle.emojiHeavy:
        return 'Emojis';
      case CommunicationStyle.formalTone:
        return 'Tom formal';
      case CommunicationStyle.informalTone:
        return 'Tom informal';
    }
  }
}
