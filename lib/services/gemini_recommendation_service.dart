import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../core/services/aiIntegrations/chat_completion_service.dart';
import '../models/profile_match_result.dart';
import '../models/user_profile.dart';

/// Uses Gemini (via AWS Lambda) to refine friend suggestion rankings.
///
/// Takes the top candidates already scored by [RecommendationEngineService]
/// and asks Gemini to re-rank them with deeper analysis of:
/// - Shared hyperfocus depth and quality (not just count)
/// - Communication style compatibility for neurodivergent users
/// - Neurodivergence type alignment and complementary dynamics
/// - Shared passion intensity and topic overlap quality
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
                'Sua análise vai além de números — você entende como diferentes neurotipos '
                'se complementam, como hiperfocuses compartilhados criam conexões profundas, '
                'e como estilos de comunicação afetam relacionamentos neurodivergentes. '
                'Retorne APENAS JSON válido, sem markdown, sem explicações extras.',
          },
          {'role': 'user', 'content': prompt},
        ],
        parameters: {
          'temperature': 0.25,
          'max_tokens': 3000,
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
                              'Score final de 0.0 a 1.0 combinando todos os fatores',
                        },
                        'insight': {
                          'type': 'string',
                          'description':
                              'Frase curta e específica (máx 80 chars) explicando POR QUE são compatíveis — mencione hiperfocuses ou neurotipos específicos',
                        },
                        'hyperfocusDepth': {
                          'type': 'number',
                          'description':
                              'Profundidade qualitativa dos hiperfocuses compartilhados 0.0-1.0. '
                              'Considere: sobreposição temática, intensidade dos interesses, '
                              'potencial de conversas profundas',
                        },
                        'commCompatibility': {
                          'type': 'number',
                          'description':
                              'Compatibilidade de estilos de comunicação 0.0-1.0. '
                              'Considere se os estilos são complementares para neurodivergentes',
                        },
                        'neurodivAlignment': {
                          'type': 'number',
                          'description':
                              'Alinhamento e dinâmica entre neurotipos 0.0-1.0. '
                              'Considere: neurotipos similares (empatia mútua), '
                              'neurotipos complementares (TDAH+TEA pode ser ótimo), '
                              'potencial de suporte mútuo',
                        },
                        'sharedPassionScore': {
                          'type': 'number',
                          'description':
                              'Qualidade das paixões compartilhadas 0.0-1.0. '
                              'Considera sobreposição de valores, ideias e interesses além dos hiperfocuses',
                        },
                        'connectionPotential': {
                          'type': 'string',
                          'description':
                              'Uma das opções: "alta", "media", "moderada" — potencial de conexão genuína',
                        },
                      },
                      'required': [
                        'id',
                        'aiScore',
                        'insight',
                        'hyperfocusDepth',
                        'commCompatibility',
                        'neurodivAlignment',
                        'sharedPassionScore',
                        'connectionPotential',
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

  /// Performs a deep one-on-one compatibility analysis between [currentUser]
  /// and a single [candidate]. Returns an enriched [ProfileMatchResult].
  /// Used for on-demand per-card analysis in the Friends screen.
  Future<ProfileMatchResult?> analyzeCompatibility({
    required UserProfile currentUser,
    required ProfileMatchResult candidate,
  }) async {
    try {
      final userJson = _profileToJson(currentUser);
      final candidateJson = _profileToJson(candidate.profile);

      final prompt =
          '''
Faça uma análise PROFUNDA e ESPECÍFICA de compatibilidade entre estas duas pessoas neurodivergentes.

Usuário principal:
${jsonEncode(userJson)}

Candidato:
${jsonEncode(candidateJson)}
Score base (algoritmo): ${(candidate.matchScore * 100).round()}%

Analise especificamente:
1. HIPERFOCUSES: Quais interesses se sobrepõem? Qual é a profundidade temática? Há potencial para conversas intensas?
2. NEUROTIPOS: Como esses neurotipos interagem? São complementares (ex: TDAH+TEA) ou similares (empatia mútua)?
3. COMUNICAÇÃO: Os estilos de comunicação se encaixam para pessoas neurodivergentes?
4. VALORES: Há alinhamento de valores e visão de mundo?
5. POTENCIAL: Qual o potencial real de uma amizade genuína?

Retorne uma análise detalhada e personalizada.
''';

      final response = await getChatCompletion(
        _provider,
        _model,
        [
          {
            'role': 'system',
            'content':
                'Você é um especialista em conexões humanas para pessoas neurodivergentes. '
                'Analise com profundidade e empatia. Seja específico sobre os interesses e neurotipos mencionados. '
                'Retorne APENAS JSON válido.',
          },
          {'role': 'user', 'content': prompt},
        ],
        parameters: {
          'temperature': 0.3,
          'max_tokens': 800,
          'response_format': {
            'type': 'json_schema',
            'json_schema': {
              'name': 'deep_compatibility',
              'schema': {
                'type': 'object',
                'properties': {
                  'aiScore': {'type': 'number'},
                  'insight': {
                    'type': 'string',
                    'description':
                        'Insight específico e personalizado (máx 100 chars) mencionando interesses ou neurotipos reais',
                  },
                  'hyperfocusDepth': {'type': 'number'},
                  'commCompatibility': {'type': 'number'},
                  'neurodivAlignment': {'type': 'number'},
                  'sharedPassionScore': {'type': 'number'},
                  'connectionPotential': {'type': 'string'},
                  'deepInsight': {
                    'type': 'string',
                    'description':
                        'Análise mais longa (máx 200 chars) explicando a dinâmica da conexão potencial',
                  },
                },
                'required': [
                  'aiScore',
                  'insight',
                  'hyperfocusDepth',
                  'commCompatibility',
                  'neurodivAlignment',
                  'sharedPassionScore',
                  'connectionPotential',
                  'deepInsight',
                ],
              },
              'strict': true,
            },
          },
        },
      );

      final content =
          response['choices']?[0]?['message']?['content'] as String?;
      if (content == null || content.isEmpty) return null;

      final parsed = jsonDecode(content) as Map<String, dynamic>;
      final aiScore =
          (parsed['aiScore'] as num?)?.toDouble() ?? candidate.matchScore;
      final insight = parsed['insight'] as String? ?? '';
      final deepInsight = parsed['deepInsight'] as String? ?? '';
      final hyperfocusDepth =
          (parsed['hyperfocusDepth'] as num?)?.toDouble() ??
          candidate.interestsScore;
      final commCompat =
          (parsed['commCompatibility'] as num?)?.toDouble() ??
          candidate.communicationScore;
      final neurodivAlign =
          (parsed['neurodivAlignment'] as num?)?.toDouble() ??
          candidate.neurotypesScore;
      final sharedPassion =
          (parsed['sharedPassionScore'] as num?)?.toDouble() ??
          candidate.valuesScore;
      final connectionPotential =
          parsed['connectionPotential'] as String? ?? 'moderada';

      final blendedScore = (aiScore * 0.65 + candidate.matchScore * 0.35).clamp(
        0.0,
        1.0,
      );

      return ProfileMatchResult(
        profile: candidate.profile,
        matchScore: blendedScore,
        interestsScore: hyperfocusDepth,
        valuesScore: sharedPassion,
        neurotypesScore: neurodivAlign,
        communicationScore: commCompat,
        aiInsight: deepInsight.isNotEmpty ? deepInsight : insight,
        aiRefined: true,
        distanceKm: candidate.distanceKm,
        connectionPotential: connectionPotential,
        shortInsight: insight,
      );
    } catch (e) {
      debugPrint('GeminiRecommendationService: Per-card analysis failed — $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Prompt builder
  // ─────────────────────────────────────────────────────────────────────────

  String _buildPrompt(UserProfile user, List<ProfileMatchResult> candidates) {
    final userJson = _profileToJson(user);

    final candidatesJson = candidates.map((r) {
      final p = r.profile;
      return {
        ..._profileToJson(p),
        'id': p.id,
        'baseScore': r.matchScore,
        'sharedHyperfocuses': p.hyperfocusInterests
            .where(
              (i) => user.hyperfocusInterests
                  .map((u) => u.toLowerCase())
                  .contains(i.toLowerCase()),
            )
            .toList(),
      };
    }).toList();

    return '''
Analise a compatibilidade PROFUNDA entre o usuário principal e os candidatos abaixo.

Para cada candidato, considere:
1. HIPERFOCUSES COMPARTILHADOS: Não apenas quantidade — analise a QUALIDADE da sobreposição.
   - Hiperfocuses no mesmo domínio (ex: ambos gostam de música eletrônica) valem mais que categorias amplas
   - Considere o potencial de conversas intensas e projetos conjuntos
   
2. DINÂMICA DE NEUROTIPOS: Como esses neurotipos específicos interagem?
   - TDAH+TDAH: energia mútua, pode ser caótico mas divertido
   - TEA+TEA: compreensão profunda, comunicação direta
   - TDAH+TEA: complementaridade clássica — TDAH traz energia, TEA traz foco
   - Neurotipos diferentes podem ser mais complementares que similares
   
3. ESTILOS DE COMUNICAÇÃO: Para neurodivergentes, comunicação compatível é crucial
   - Texto curto + texto curto = fluxo natural
   - Áudio + texto longo = possível fricção
   - Assíncrono + assíncrono = respeito mútuo ao ritmo
   
4. VALORES E INTERESSES: Alinhamento de visão de mundo e valores

O aiScore deve combinar o baseScore (peso 35%) com sua análise qualitativa (peso 65%).
Seja específico no insight — mencione hiperfocuses ou neurotipos reais dos perfis.

Usuário principal:
${jsonEncode(userJson)}

Candidatos (${candidates.length} perfis):
${jsonEncode(candidatesJson)}
''';
  }

  Map<String, dynamic> _profileToJson(UserProfile p) => {
    'neurotypes': p.neurotypes.map((n) => _neurotypeName(n)).toList(),
    'hyperfocuses': p.hyperfocusInterests,
    'communicationStyles': p.communicationStyles
        .map((c) => _commStyleName(c))
        .toList(),
    'values': p.valuesAndIdeas,
  };

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
        final sharedPassion =
            (ai['sharedPassionScore'] as num?)?.toDouble() ??
            result.valuesScore;
        final connectionPotential =
            ai['connectionPotential'] as String? ?? 'moderada';

        // Blend original score with AI score (65/35)
        final blendedScore = (aiScore * 0.65 + result.matchScore * 0.35).clamp(
          0.0,
          1.0,
        );

        return ProfileMatchResult(
          profile: result.profile,
          matchScore: blendedScore,
          interestsScore: hyperfocusDepth,
          valuesScore: sharedPassion,
          neurotypesScore: neurodivAlign,
          communicationScore: commCompat,
          aiInsight: insight,
          aiRefined: true,
          distanceKm: result.distanceKm,
          connectionPotential: connectionPotential,
          shortInsight: insight,
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
