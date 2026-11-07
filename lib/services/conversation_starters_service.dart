import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/services/aiIntegrations/chat_completion_service.dart';
import './supabase_service.dart';

/// Generates low-pressure conversation starters with Gemini by analyzing the
/// friend's profile (neurodivergence, hyperfocuses, interests, bio) together
/// with the current user's profile.
class ConversationStartersService {
  ConversationStartersService._();
  static final ConversationStartersService instance =
      ConversationStartersService._();

  static const String _provider = 'GEMINI';
  static const String _model = 'gemini/gemini-3.7-flash';

  final Map<String, List<String>> _cache = {};

  static const String _columns =
      'id, full_name, username, bio, neurodiv_type, hyperfocuses, interests';

  /// Returns up to 3 conversation starters in pt-BR for [friendId].
  /// Pass [forceRefresh] to bypass the in-memory cache.
  /// Returns an empty list when the AI is unavailable.
  Future<List<String>> generateStarters({
    required String friendId,
    String? friendNameFallback,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && (_cache[friendId]?.isNotEmpty ?? false)) {
      return _cache[friendId]!;
    }

    try {
      final client = SupabaseService.instance.client;
      final myId = SupabaseService.instance.currentUserId;

      final friendRow = await client
          .from('user_profiles')
          .select(_columns)
          .eq('id', friendId)
          .maybeSingle();

      Map<String, dynamic>? myRow;
      if (myId != null && myId.isNotEmpty) {
        myRow = await client
            .from('user_profiles')
            .select(_columns)
            .eq('id', myId)
            .maybeSingle();
      }

      final friend = _compact(friendRow, friendNameFallback);
      final me = _compact(myRow, null);

      final prompt =
          '''
Gere 3 sugestões de mensagens para EU iniciar uma conversa com meu amigo(a).

Perfil do meu amigo(a):
${jsonEncode(friend)}

Meu perfil:
${jsonEncode(me)}

Regras:
- Escreva em português do Brasil, em primeira pessoa, como se EU estivesse enviando.
- Cada mensagem deve ter no máximo 120 caracteres, ser leve, concreta e fácil de responder.
- Use hiperfocos e interesses REAIS do perfil do amigo(a) (e interesses em comum, se houver).
- Evite perguntas vagas como "tudo bem?"; prefira uma pergunta específica ou um comentário sobre um interesse.
- Sem pressão social, sem exigir resposta imediata, tom acolhedor e direto (bom para pessoas neurodivergentes).
- Use no máximo 1 emoji por mensagem. Não mencione diagnósticos explicitamente.
''';

      final response = await getChatCompletion(
        _provider,
        _model,
        [
          {
            'role': 'system',
            'content':
                'Você é um assistente que ajuda pessoas neurodivergentes a superar a paralisia '
                'da página em branco ao iniciar conversas. Seja caloroso, específico e respeitoso. '
                'Retorne APENAS JSON válido, sem markdown.',
          },
          {'role': 'user', 'content': prompt},
        ],
        parameters: {
          'temperature': 0.8,
          'max_tokens': 600,
          'response_format': {
            'type': 'json_schema',
            'json_schema': {
              'name': 'conversation_starters',
              'schema': {
                'type': 'object',
                'properties': {
                  'starters': {
                    'type': 'array',
                    'items': {'type': 'string'},
                  },
                },
                'required': ['starters'],
              },
              'strict': true,
            },
          },
        },
      );

      final content =
          response['choices']?[0]?['message']?['content'] as String?;
      if (content == null || content.trim().isEmpty) return const [];

      final starters = _parse(content);
      if (starters.isNotEmpty) _cache[friendId] = starters;
      return starters;
    } catch (e) {
      debugPrint('ConversationStartersService: failed — $e');
      return const [];
    }
  }

  Map<String, dynamic> _compact(Map<String, dynamic>? row, String? fallback) {
    if (row == null) {
      return {if (fallback != null && fallback.isNotEmpty) 'nome': fallback};
    }
    final name = (row['full_name'] as String?)?.isNotEmpty == true
        ? row['full_name'] as String
        : (row['username'] as String? ?? fallback ?? '');
    return {
      if (name.isNotEmpty) 'nome': name,
      if ((row['bio'] as String?)?.isNotEmpty == true) 'bio': row['bio'],
      'neurodivergencia': _asList(row['neurodiv_type']),
      'hiperfocos': _asList(row['hyperfocuses']),
      'interesses': _asList(row['interests']),
    };
  }

  List<String> _asList(dynamic v) {
    if (v == null) return const [];
    if (v is List) {
      return v
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    final s = v.toString().trim();
    return s.isEmpty ? const [] : [s];
  }

  List<String> _parse(String raw) {
    var text = raw.trim();
    if (text.startsWith('```')) {
      text = text
          .replaceFirst(RegExp(r'^```(?:json)?'), '')
          .replaceFirst(RegExp(r'```$'), '')
          .trim();
    }
    try {
      final decoded = jsonDecode(text);
      final list = decoded is Map ? decoded['starters'] : decoded;
      if (list is List) {
        return list
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .take(3)
            .toList();
      }
    } catch (e) {
      debugPrint('ConversationStartersService: parse error — $e');
    }
    return const [];
  }
}
