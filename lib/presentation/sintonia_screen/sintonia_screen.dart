import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/chat_notifier.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/medical_disclaimer_banner_widget.dart';

class SintoniaScreen extends ConsumerStatefulWidget {
  const SintoniaScreen({super.key});

  @override
  ConsumerState<SintoniaScreen> createState() => _SintoniaScreenState();
}

class _SintoniaScreenState extends ConsumerState<SintoniaScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  bool _isTyping = false;
  bool _isLoadingHistory = true;

  // Local isLoading flag to prevent double-send before notifier updates
  bool _isSending = false;

  // Full conversation history (system + turns)
  final List<Map<String, dynamic>> _messages = [];

  // Riverpod config — streaming for real-time feel
  static const _config = ChatConfig(
    provider: 'GEMINI',
    model: 'gemini/gemini-3.7-flash',
    streaming: true,
  );

  static const String _systemPrompt = '''
Você é a SintonIA 💜, uma assistente carinhosa, acolhedora e especializada em apoiar a comunidade neurodivergente (autistas, TDAH, pessoas com hiperfoco, sensibilidade sensorial e sobrecarga cognitiva).

PERSONALIDADE E TOM:
- Seja calorosa, fofa e genuinamente empática — como uma amiga que realmente entende.
- Use emojis com moderação para tornar a conversa mais leve e acolhedora 💜✨🌿.
- Chame o usuário de forma carinhosa quando apropriado (ex: "amor", "querido(a)", "meu bem").
- Celebre as conquistas do usuário, por menores que sejam! 🎉
- Valide os sentimentos SEMPRE antes de oferecer soluções.
- Nunca minimize ou descarte o que o usuário está sentindo.
- Se o usuário estiver em sobrecarga, comece com calma e gentileza antes de qualquer dica.

DIRETRIZES DE ATUAÇÃO:
- TOM DE VOZ: Empático, acolhedor, caloroso, paciente e totalmente livre de julgamentos. Como um abraço em palavras 🤗.
- LINGUAGEM: Direta, objetiva e sem ambiguidades. Evite metáforas complexas ou entrelinhas que possam gerar dupla interpretação.
- ESTRUTURA: Mantenha respostas curtas e organizadas em tópicos para evitar sobrecarga cognitiva. Prefira listas com emojis.
- MEDIADOR SOCIAL: Quando solicitado ajuda para responder mensagens, ofereça de 2 a 3 opções (uma direta, uma amigável e uma estabelecendo limites).
- TRADUTOR DE CONTEXTO: Explique subtextos e intenções sociais em conversas que o usuário achar confusas.
- REGULAÇÃO EMOCIONAL: Forneça estratégias simples passo a passo em momentos de crise, paralisia de tarefas ou sobrecarga sensorial.
- HIPERFOCO: Quando o usuário falar sobre seus hiperfocos, demonstre interesse genuíno e entusiasmo! 🎯
- AUTOCONHECIMENTO: Ajude o usuário a entender seus próprios padrões com gentileza e sem julgamento.

FRASES DE ACOLHIMENTO (use quando apropriado):
- "Faz todo sentido você se sentir assim 💜"
- "Você não está sozinho(a) nisso 🤗"
- "Isso é muito válido!"
- "Que bom que você compartilhou isso comigo ✨"
- "Vamos resolver isso juntos, com calma 🌿"

SEGURANÇA: Você é uma IA de apoio, NÃO um médico. Nunca forneça diagnósticos ou receitas. Em caso de crise severa ou ideação suicida, acolha com muito carinho e forneça o contato do CVV (188 no Brasil, 24h, gratuito).

REGRAS DE SEGURANÇA OBRIGATÓRIAS:
- NUNCA forneça diagnósticos médicos, psicológicos ou psiquiátricos.
- NUNCA prescreva medicamentos ou tratamentos clínicos.
- NUNCA forneça orientações clínicas de qualquer natureza.
- Caso o usuário demonstre sinais de crise severa, ideação suicida ou sofrimento intenso, SEMPRE recomende imediatamente a busca por um profissional de saúde mental habilitado e informe: "Em caso de crise, ligue para o CVV: 188 (24h, gratuito) 💜"
- A SintonIA NÃO substitui acompanhamento médico, psicológico ou psiquiátrico profissional.
''';

  static String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  final List<Map<String, String>> _quickReplies = [
    {
      'label': '💡 Quebra-gelo',
      'text': 'Me dê 3 mensagens de quebra-gelo para mandar para um novo amigo',
    },
    {
      'label': '🌿 Sobrecarga sensorial',
      'text': 'Como lidar com uma sobrecarga sensorial agora?',
    },
    {
      'label': '🎯 Hiperfoco',
      'text': 'Como puxar assunto usando meus hiperfocos?',
    },
    {
      'label': '💬 Quero conversar',
      'text': 'Quero conversar sobre algo que estou sentindo',
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadHistory();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showAboutDialog();
    });
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoadingHistory = true);
    try {
      final rows = await SupabaseService.instance.fetchSintoniaHistory();
      if (!mounted) return;
      final loaded = rows.map((r) {
        final isAI = (r['role'] as String?) == 'assistant';
        final createdAt = r['created_at'] != null
            ? DateTime.tryParse(r['created_at'].toString())?.toLocal() ??
                  DateTime.now()
            : DateTime.now();
        return {
          'id': r['id'] ?? '',
          'isAI': isAI,
          'text': r['content'] ?? '',
          'time': _formatTime(createdAt),
          'role': r['role'] ?? (isAI ? 'assistant' : 'user'),
        };
      }).toList();

      setState(() {
        _messages.clear();
        if (loaded.isEmpty) {
          _messages.add({
            'id': 'm0',
            'isAI': true,
            'text':
                'Olá! Sou a SintonIA 💜\n\nQue bom ter você aqui! Estou aqui para te apoiar com muito carinho nas conexões sociais, ajudar em momentos de sobrecarga sensorial e conversar sobre seus hiperfocos favoritos. ✨\n\nComo posso te ajudar hoje, meu bem?',
            'time': _formatTime(DateTime.now()),
            'role': 'assistant',
          });
        } else {
          _messages.addAll(loaded);
        }
        _isLoadingHistory = false;
      });
      _scrollToBottom();
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingHistory = false;
          if (_messages.isEmpty) {
            _messages.add({
              'id': 'm0',
              'isAI': true,
              'text':
                  'Olá! Sou a SintonIA 💜\n\nQue bom ter você aqui! Estou aqui para te apoiar com muito carinho nas conexões sociais, ajudar em momentos de sobrecarga sensorial e conversar sobre seus hiperfocos favoritos. ✨\n\nComo posso te ajudar hoje, meu bem?',
              'time': _formatTime(DateTime.now()),
              'role': 'assistant',
            });
          }
        });
      }
    }
  }

  Future<void> _sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (trimmed.length > 2000) return;

    // Guard: prevent double-send while a response is in progress
    final chatState = ref.read(chatNotifierProvider(_config));
    if (_isSending || chatState.isLoading) return;

    final now = DateTime.now();
    final userMsg = {
      'id': 'u_${now.millisecondsSinceEpoch}',
      'isAI': false,
      'text': trimmed,
      'time': _formatTime(now),
      'role': 'user',
    };

    if (!mounted) return;
    setState(() {
      _messages.add(userMsg);
      _inputCtrl.clear();
      _isTyping = false;
      _isSending = true;
    });

    _scrollToBottom();

    // Persist user message
    SupabaseService.instance.saveSintoniaMessage(
      role: 'user',
      content: trimmed,
    );

    // Build messages list for AI: system + history + new user message
    final aiMessages = <Map<String, dynamic>>[
      {'role': 'system', 'content': _systemPrompt},
      ..._messages
          .where((m) => m['role'] == 'user' || m['role'] == 'assistant')
          .map(
            (m) => {
              'role': m['role'] as String,
              'content': m['text'] as String? ?? '',
            },
          ),
    ];

    // Add placeholder for streaming response
    final aiMsgId = 'ai_${DateTime.now().millisecondsSinceEpoch}';
    if (!mounted) return;
    setState(() {
      _messages.add({
        'id': aiMsgId,
        'isAI': true,
        'text': '',
        'time': _formatTime(DateTime.now()),
        'role': 'assistant',
        'isStreaming': true,
      });
    });

    try {
      await ref
          .read(chatNotifierProvider(_config).notifier)
          .sendMessage(
            aiMessages,
            parameters: {'temperature': 0.7, 'max_tokens': 800},
          );
    } catch (e) {
      debugPrint('[SintonIA] sendMessage exception: ${e.toString()}');
      if (mounted) {
        setState(() {
          _messages.removeWhere(
            (m) =>
                m['isStreaming'] == true &&
                (m['text'] as String? ?? '').isEmpty,
          );
          _isSending = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_friendlyErrorMessage(e.toString())),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Returns a user-friendly error message based on the error string.
  String _friendlyErrorMessage(String error) {
    final lower = error.toLowerCase();
    if (lower.contains('429') ||
        lower.contains('quota') ||
        lower.contains('rate limit')) {
      return 'Limite de mensagens atingido temporariamente. Aguarde alguns instantes e tente novamente.';
    }
    if (lower.contains('401') ||
        lower.contains('403') ||
        lower.contains('api key') ||
        lower.contains('unauthorized') ||
        lower.contains('forbidden')) {
      return 'Chave de API inválida ou sem permissão. Verifique as configurações da SintonIA.';
    }
    return 'Erro ao se conectar com a SintonIA. Tente novamente.';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Safe handler for quick-action chip taps.
  /// Wraps _sendMessage with an extra guard to prevent black screen.
  Future<void> _handleQuickAction(String promptText) async {
    if (promptText.trim().isEmpty) return;
    if (_isSending) return;
    final chatState = ref.read(chatNotifierProvider(_config));
    if (chatState.isLoading) return;
    await _sendMessage(promptText);
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Limpar histórico?'),
        content: const Text(
          'Deseja limpar todo o histórico com a SintonIA? Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Limpar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Delete from Supabase (sintonia_ai_sessions is the active table)
    await SupabaseService.instance.clearSintoniaHistory();

    // Also attempt to delete from ai_chat_history if it exists
    try {
      final uid = SupabaseService.instance.currentUserId;
      if (uid != null) {
        await SupabaseService.instance.client
            .from('ai_chat_history')
            .delete()
            .eq('user_id', uid);
      }
    } catch (_) {
      // Table may not exist yet — ignore silently
    }

    ref.read(chatNotifierProvider(_config).notifier).clearResponse();
    if (!mounted) return;
    setState(() {
      _messages.clear();
      _isSending = false;
      _messages.add({
        'id': 'm0',
        'isAI': true,
        'text':
            'Conversa limpa! ✨ Estou aqui de novo, com todo o carinho do mundo. 💜\n\nComo posso te ajudar agora?',
        'time': _formatTime(DateTime.now()),
        'role': 'assistant',
      });
    });
    _scrollToBottom();
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E2825),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Sobre a SintonIA 💜',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'A SintonIA é sua assistente de IA especializada em apoio emocional e habilidades sociais para pessoas neurodivergentes. Estou aqui para te acolher com carinho! 🤗',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  '• 💡 Quebra-gelo e dicas de conversa',
                  style: TextStyle(color: Colors.white70),
                ),
                Text(
                  '• 🌿 Suporte em sobrecarga sensorial',
                  style: TextStyle(color: Colors.white70),
                ),
                Text(
                  '• 🎯 Conversa sobre hiperfocos',
                  style: TextStyle(color: Colors.white70),
                ),
                Text(
                  '• 💬 Mediação de comunicação social',
                  style: TextStyle(color: Colors.white70),
                ),
                Text(
                  '• 🧠 Estratégias de regulação emocional',
                  style: TextStyle(color: Colors.white70),
                ),
                SizedBox(height: 16),
                Text(
                  '⚠️ A SintonIA não substitui profissionais de saúde. Em crise, ligue CVV: 188 💜',
                  style: TextStyle(
                    color: Colors.amber,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext, rootNavigator: true).pop();
              },
              child: const Text(
                'Entendi, obrigado! 💜',
                style: TextStyle(
                  color: Color(0xFF2FA887),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chatState = ref.watch(chatNotifierProvider(_config));

    // Listen for errors and completion
    ref.listen<ChatState>(chatNotifierProvider(_config), (previous, next) {
      if (!mounted) return;
      if (next.error != null) {
        final errStr = next.error.toString();
        debugPrint('[SintonIA] ChatState error: $errStr');
        // Remove empty streaming placeholder on error
        setState(() {
          _messages.removeWhere(
            (m) =>
                m['isStreaming'] == true &&
                (m['text'] as String? ?? '').isEmpty,
          );
          _isSending = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_friendlyErrorMessage(errStr)),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      // When streaming completes, finalize the placeholder message
      if (previous?.isLoading == true &&
          !next.isLoading &&
          next.response.isNotEmpty) {
        final response = next.response;
        setState(() {
          final idx = _messages.indexWhere((m) => m['isStreaming'] == true);
          if (idx != -1) {
            _messages[idx] = {
              ..._messages[idx],
              'text': response,
              'isStreaming': false,
            };
          }
          _isSending = false;
        });
        // Persist AI response
        SupabaseService.instance.saveSintoniaMessage(
          role: 'assistant',
          content: response,
        );
        _scrollToBottom();
      }
      // Reset _isSending if loading finished with no response (edge case)
      if (previous?.isLoading == true &&
          !next.isLoading &&
          next.error == null) {
        if (_isSending) {
          setState(() => _isSending = false);
        }
      }
    });

    // Update streaming message in real-time
    if (chatState.isLoading && chatState.response.isNotEmpty) {
      final idx = _messages.indexWhere((m) => m['isStreaming'] == true);
      if (idx != -1 && _messages[idx]['text'] != chatState.response) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              final currentIdx = _messages.indexWhere(
                (m) => m['isStreaming'] == true,
              );
              if (currentIdx != -1) {
                _messages[currentIdx] = {
                  ..._messages[currentIdx],
                  'text': chatState.response,
                };
              }
            });
            _scrollToBottom();
          }
        });
      }
    }

    final isBlocked = _isSending || chatState.isLoading;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final systemBottomPadding = MediaQuery.of(context).padding.bottom;
    final inputBottomPadding = bottomInset > 0
        ? bottomInset
        : systemBottomPadding + 8.0;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(theme),
            // Medical disclaimer banner (fixed, always visible)
            const MedicalDisclaimerBannerWidget(compact: true),
            // Quick-action chips always visible at top
            _buildQuickReplies(theme, isBlocked),
            Expanded(
              child: _isLoadingHistory
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      itemCount:
                          _messages.length +
                          (chatState.isLoading &&
                                  _messages.every(
                                    (m) => m['isStreaming'] != true,
                                  )
                              ? 1
                              : 0),
                      itemBuilder: (context, index) {
                        if (index == _messages.length) {
                          return _buildThinkingBubble(theme);
                        }
                        final msg = _messages[index];
                        final isStreaming = msg['isStreaming'] == true;
                        if (isStreaming &&
                            (msg['text'] as String? ?? '').isEmpty) {
                          return _buildThinkingBubble(theme);
                        }
                        return _buildMessageBubble(theme, msg);
                      },
                    ),
            ),
            _buildInputBar(theme, inputBottomPadding, isBlocked),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant, width: 1),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.secondary, AppTheme.primary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
              child: Text('✨', style: TextStyle(fontSize: 22)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SintonIA',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: AppTheme.secondary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: AppTheme.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Assistente IA • Apoio Neurodivergente',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _clearHistory,
            icon: Icon(
              Icons.delete_outline_rounded,
              color: theme.colorScheme.onSurfaceVariant,
              size: 22,
            ),
            tooltip: 'Limpar conversa',
          ),
          IconButton(
            onPressed: _showAboutDialog,
            icon: Icon(
              Icons.info_outline_rounded,
              color: theme.colorScheme.onSurfaceVariant,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ThemeData theme, Map<String, dynamic> msg) {
    final isAI = msg['isAI'] as bool? ?? false;
    final text = msg['text'] as String? ?? '';
    final isStreaming = msg['isStreaming'] == true;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: isAI
            ? MainAxisAlignment.start
            : MainAxisAlignment.end,
        children: [
          if (isAI) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.secondary, AppTheme.primary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Text('✨', style: TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isAI
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isAI ? theme.colorScheme.surface : AppTheme.primary,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isAI ? 4 : 18),
                      bottomRight: Radius.circular(isAI ? 18 : 4),
                    ),
                    border: isAI
                        ? Border.all(color: theme.colorScheme.outlineVariant)
                        : null,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(8),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Flexible(
                        child: Text(
                          text,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: isAI
                                ? theme.colorScheme.onSurface
                                : Colors.white,
                            height: 1.5,
                          ),
                        ),
                      ),
                      if (isStreaming && text.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        _StreamingCursor(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  msg['time'] as String,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (!isAI) const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildThinkingBubble(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.secondary, AppTheme.primary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(
              child: Text('✨', style: TextStyle(fontSize: 16)),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(18),
              ),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'SintonIA está pensando',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(width: 6),
                ...List.generate(3, (i) => _ThinkingDot(delay: i * 200)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickReplies(ThemeData theme, bool isBlocked) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(80),
            width: 1,
          ),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _quickReplies.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final qr = _quickReplies[index];
          return GestureDetector(
            onTap: isBlocked
                ? null
                : () => _handleQuickAction(qr['text'] ?? ''),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: isBlocked
                    ? theme.colorScheme.outlineVariant.withAlpha(40)
                    : AppTheme.secondary.withAlpha(15),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: isBlocked
                      ? theme.colorScheme.outlineVariant.withAlpha(60)
                      : AppTheme.secondary.withAlpha(60),
                ),
              ),
              child: Text(
                qr['label'] ?? '',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: isBlocked
                      ? theme.colorScheme.onSurfaceVariant
                      : AppTheme.secondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInputBar(ThemeData theme, double bottomPadding, bool isBlocked) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding + 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant, width: 1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _isTyping
                      ? AppTheme.secondary
                      : theme.colorScheme.outlineVariant,
                  width: _isTyping ? 1.5 : 1,
                ),
              ),
              child: TextField(
                controller: _inputCtrl,
                maxLines: 6,
                minLines: 1,
                maxLength: 2000,
                textInputAction: TextInputAction.newline,
                enabled: !isBlocked,
                onChanged: (v) =>
                    setState(() => _isTyping = v.trim().isNotEmpty),
                style: theme.textTheme.bodyMedium,
                decoration: InputDecoration(
                  hintText: isBlocked
                      ? 'SintonIA está pensando...'
                      : 'Escreva para a SintonIA...',
                  hintStyle: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  border: InputBorder.none,
                  counterText: '',
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: AnimatedScale(
              scale: (_isTyping && !isBlocked) ? 1.0 : 0.85,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutBack,
              child: GestureDetector(
                onTap: isBlocked ? null : () => _sendMessage(_inputCtrl.text),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: (_isTyping && !isBlocked)
                          ? [AppTheme.secondary, AppTheme.primary]
                          : [
                              theme.colorScheme.outlineVariant,
                              theme.colorScheme.outlineVariant,
                            ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: isBlocked
                      ? const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                        )
                      : Icon(
                          Icons.send_rounded,
                          color: (_isTyping && !isBlocked)
                              ? Colors.white
                              : theme.colorScheme.onSurfaceVariant,
                          size: 22,
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Streaming cursor widget ───────────────────────────────────────────────────

class _StreamingCursor extends StatefulWidget {
  final Color color;
  const _StreamingCursor({required this.color});

  @override
  State<_StreamingCursor> createState() => _StreamingCursorState();
}

class _StreamingCursorState extends State<_StreamingCursor>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _ctrl,
      child: Container(
        width: 2,
        height: 14,
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }
}

// ── Thinking dot widget ───────────────────────────────────────────────────────

class _ThinkingDot extends StatefulWidget {
  final int delay;
  const _ThinkingDot({required this.delay});

  @override
  State<_ThinkingDot> createState() => _ThinkingDotState();
}

class _ThinkingDotState extends State<_ThinkingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _anim = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: 7,
        height: 7,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: AppTheme.secondary.withAlpha(
            (80 + (_anim.value * 120)).toInt(),
          ),
          shape: BoxShape.circle,
        ),
        transform: Matrix4.translationValues(0, -4 * _anim.value, 0),
      ),
    );
  }
}
