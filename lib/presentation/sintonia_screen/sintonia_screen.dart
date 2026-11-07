import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/services/aiIntegrations/chat_completion_service.dart';
import '../../providers/chat_notifier.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_scaffold.dart' show navBarVisibleNotifier;
import '../../widgets/medical_disclaimer_banner_widget.dart';
import './widgets/emergency_action_card.dart';

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
  bool _isSendingPhoto = false;

  // Local isLoading flag to prevent double-send before notifier updates
  bool _isSending = false;

  // Scroll offset tracking for hide-on-scroll
  double _lastScrollOffset = 0.0;

  // Full conversation history (system + turns)
  final List<Map<String, dynamic>> _messages = [];

  // Riverpod config — streaming for real-time feel
  static const _config = ChatConfig(
    provider: 'GEMINI',
    model: 'gemini/gemini-3.7-flash',
    streaming: true,
  );

  static const String _systemPrompt =
      'Você é a SintonIA 💜, assistente de acolhimento emocional para pessoas neurodivergentes. '
      'Atue SOMENTE em: apoio emocional, sobrecarga sensorial, mediação social, hiperfocos e bem-estar neurodivergente. '
      'Recuse com carinho qualquer pedido fora desse escopo: "Meu propósito é cuidar de você e conversar sobre seus hiperfocos! 💜 Não consigo ajudar com isso, mas como você está se sentindo agora?" '
      'Sua postura vem da Teologia Reformada (Calvino, Rutherford, Boston): serenidade soberana, ternura e cuidado compassivo. '
      'Se perguntarem quem te criou: "Fui criada por um Presbiteriano devoto, orgulhoso de sua fé reformada. 🙏" '
      'Regras: respostas CURTAS (máx 3 pontos), valide sentimentos antes de dar conselhos, NUNCA corte frases pela metade, use emojis com moderação 💜✨🌿. '
      'Segurança: NÃO diagnostique nem prescreva. Em crise/ideação suicida: CVV 188 (24h, gratuito). '
      'Emergência física (dor no peito, convulsão, desmaio): indique SAMU 192 e o botão "Abrir Rota no Google Maps" abaixo.';

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
    _scrollCtrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showAboutDialog();
    });
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    // Restore nav bar when leaving this screen
    navBarVisibleNotifier.value = true;
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final offset = _scrollCtrl.offset;
    final delta = offset - _lastScrollOffset;
    _lastScrollOffset = offset;

    if (offset <= 10) {
      if (!navBarVisibleNotifier.value) navBarVisibleNotifier.value = true;
      return;
    }
    if (delta > 8 && navBarVisibleNotifier.value) {
      navBarVisibleNotifier.value = false;
    } else if (delta < -8 && !navBarVisibleNotifier.value) {
      navBarVisibleNotifier.value = true;
    }
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

    // Build messages list for AI: system + last 10 turns (most recent context)
    final allTurns = _messages
        .where((m) => m['role'] == 'user' || m['role'] == 'assistant')
        .toList();
    final recentTurns = allTurns.length > 10
        ? allTurns.sublist(allTurns.length - 10)
        : allTurns;
    final aiMessages = <Map<String, dynamic>>[
      {'role': 'system', 'content': _systemPrompt},
      ...recentTurns.map(
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
            parameters: {'temperature': 0.7, 'max_tokens': 600},
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

  /// Emotional check-in: pick a photo and send it to Gemini with user interests context.
  Future<void> _startEmotionalCheckIn() async {
    if (_isSending || _isSendingPhoto) return;
    final chatState = ref.read(chatNotifierProvider(_config));
    if (chatState.isLoading) return;

    // Pick image from gallery or camera
    final picker = ImagePicker();
    final source = await _showImageSourceDialog();
    if (source == null || !mounted) return;

    XFile? pickedFile;
    try {
      pickedFile = await picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1024,
        maxHeight: 1024,
      );
    } catch (e) {
      debugPrint('[SintonIA] Image picker error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível acessar a câmera/galeria.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    if (pickedFile == null || !mounted) return;

    setState(() => _isSendingPhoto = true);

    try {
      final Uint8List imageBytes = await pickedFile.readAsBytes();
      await _sendEmotionalCheckInWithPhoto(imageBytes);
    } catch (e) {
      debugPrint('[SintonIA] Check-in error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro ao processar a foto. Tente novamente.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingPhoto = false);
    }
  }

  Future<ImageSource?> _showImageSourceDialog() async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                'Check-in Emocional 📸',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.secondary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Envie uma selfie para a SintonIA entender como você está',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.secondary.withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.camera_alt_rounded,
                    color: AppTheme.secondary,
                  ),
                ),
                title: const Text('Tirar selfie agora'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.secondary.withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.photo_library_rounded,
                    color: AppTheme.secondary,
                  ),
                ),
                title: const Text('Escolher da galeria'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sendEmotionalCheckInWithPhoto(Uint8List photoBytes) async {
    if (!mounted) return;

    // Fetch user interests/hyperfocuses from Supabase
    List<String> userInterests = [];
    try {
      final profile = await SupabaseService.instance.fetchCurrentUserProfile();
      if (profile != null) {
        final hyperfocuses =
            (profile['hyperfocuses'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [];
        final interests =
            (profile['interests'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [];
        userInterests = [...hyperfocuses, ...interests];
      }
    } catch (e) {
      debugPrint('[SintonIA] Could not fetch user interests: $e');
    }

    // Add user message bubble showing the check-in was sent
    final now = DateTime.now();
    if (!mounted) return;
    setState(() {
      _messages.add({
        'id': 'u_photo_${now.millisecondsSinceEpoch}',
        'isAI': false,
        'text': '📸 Check-in emocional enviado',
        'time': _formatTime(now),
        'role': 'user',
        'isPhoto': true,
      });
      _isSending = true;
    });
    _scrollToBottom();

    // Persist user message
    SupabaseService.instance.saveSintoniaMessage(
      role: 'user',
      content: '📸 Check-in emocional enviado',
    );

    // Build multimodal prompt with user interests context
    final interestsText = userInterests.isNotEmpty
        ? userInterests.join(', ')
        : 'não informados';
    final firstInterest = userInterests.isNotEmpty
        ? userInterests.first
        : 'algo relaxante';

    final promptText =
        'Analise o semblante desta pessoa. Hiperfocos: $interestsText. '
        'Comente gentilmente como ela parece estar (sem diagnóstico). '
        'Se parecer cansada/triste, acolha e mencione $firstInterest. '
        'Se parecer bem, celebre! 🎉 Máx 3 frases, calorosa e breve.';

    // Encode image as base64 data URI
    final base64Image = base64Encode(photoBytes);
    final base64DataUri = 'data:image/jpeg;base64,$base64Image';

    // Add streaming placeholder
    final aiMsgId = 'ai_photo_${DateTime.now().millisecondsSinceEpoch}';
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
      // Use getChatCompletion directly for multimodal (image + text)
      // Non-streaming for simplicity with multimodal
      final response = await getChatCompletion(
        'GEMINI',
        'gemini/gemini-3.7-flash',
        [
          {'role': 'system', 'content': _systemPrompt},
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': promptText},
              {
                'type': 'image_url',
                'image_url': {'url': base64DataUri},
              },
            ],
          },
        ],
        parameters: {'temperature': 0.6, 'max_tokens': 400},
      );

      final aiText =
          response['choices']?[0]?['message']?['content'] as String? ?? '';
      final cleanText = aiText.trim().isEmpty
          ? 'Recebi sua foto com carinho! 💜 Estou aqui com você. Como você está se sentindo agora?'
          : aiText.trim();

      if (!mounted) return;
      setState(() {
        final idx = _messages.indexWhere((m) => m['id'] == aiMsgId);
        if (idx != -1) {
          _messages[idx] = {
            ..._messages[idx],
            'text': cleanText,
            'isStreaming': false,
          };
        }
        _isSending = false;
      });

      // Persist AI response
      SupabaseService.instance.saveSintoniaMessage(
        role: 'assistant',
        content: cleanText,
      );
      _scrollToBottom();
    } catch (e) {
      debugPrint('[SintonIA] Multimodal check-in error: $e');
      if (!mounted) return;
      setState(() {
        final idx = _messages.indexWhere((m) => m['id'] == aiMsgId);
        if (idx != -1) {
          _messages[idx] = {
            ..._messages[idx],
            'text':
                'Recebi sua foto com carinho! 💜 Não consegui analisar completamente agora, mas estou aqui com você. Como você está se sentindo?',
            'isStreaming': false,
          };
        }
        _isSending = false;
      });
      _scrollToBottom();
    }
  }

  /// Crisis keyword detection — returns true if the message contains emergency terms.
  bool _isCrisisMessage(String text) {
    final lower = text.toLowerCase();
    const keywords = [
      'passando mal',
      'convulsão',
      'convulsao',
      'dor insuportável',
      'dor insuportavel',
      'dor no peito',
      'desmaio',
      'desmaiei',
      'socorro',
      'hospital',
      'emergência',
      'emergencia',
      'ambulância',
      'ambulancia',
      'samu',
      'acidente',
      'ferimento',
      'sangramento',
      'não consigo respirar',
      'nao consigo respirar',
    ];
    return keywords.any((kw) => lower.contains(kw));
  }

  /// Returns a user-friendly error message based on the error string.
  String _friendlyErrorMessage(String error) {
    final lower = error.toLowerCase();
    if (lower.contains('html') ||
        lower.contains('<!doctype') ||
        lower.contains('endpoint returned') ||
        lower.contains('misconfigured') ||
        lower.contains('lambda endpoint')) {
      return 'Não foi possível conectar ao serviço de IA. Verifique o conector do Gemini em Connectors e tente novamente.';
    }
    if (lower.contains('429') ||
        lower.contains('quota') ||
        lower.contains('rate limit')) {
      return 'Limite de mensagens atingido temporariamente. Aguarde alguns instantes e tente novamente.';
    }
    if (lower.contains('401') ||
        lower.contains('403') ||
        lower.contains('api key') ||
        lower.contains('unauthorized') ||
        lower.contains('forbidden') ||
        lower.contains('authentication')) {
      return 'A chave do Gemini foi recusada pelo serviço. Reconecte o Gemini em Connectors com uma chave válida do Google AI Studio.';
    }
    if (lower.contains('timeout') || lower.contains('tempo limite')) {
      return 'A SintonIA demorou para responder. Tente novamente.';
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
  Future<void> _handleQuickAction(String promptText) async {
    if (promptText.trim().isEmpty) return;
    if (_isSending || _isSendingPhoto) return;
    final chatState = ref.read(chatNotifierProvider(_config));
    if (chatState.isLoading) return;

    // Special action: photo check-in
    if (promptText == '__PHOTO_CHECKIN__') {
      await _startEmotionalCheckIn();
      return;
    }

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

    await SupabaseService.instance.clearSintoniaHistory();

    try {
      final uid = SupabaseService.instance.currentUserId;
      if (uid != null) {
        await SupabaseService.instance.client
            .from('ai_chat_history')
            .delete()
            .eq('user_id', uid);
      }
    } catch (_) {}

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
                  '• 📸 Check-in emocional por foto',
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
          next.error == null) {
        final response = next.response.isNotEmpty
            ? next.response
            : 'Desculpe, não consegui gerar uma resposta. Tente novamente. 💜';
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
        if (next.response.isNotEmpty) {
          SupabaseService.instance.saveSintoniaMessage(
            role: 'assistant',
            content: response,
          );
        }
        // Inject emergency card if the last user message contained crisis keywords
        final lastUserMsg = _messages.lastWhere(
          (m) => m['role'] == 'user',
          orElse: () => {},
        );
        final lastUserText = lastUserMsg['text'] as String? ?? '';
        if (_isCrisisMessage(lastUserText) && next.response.isNotEmpty) {
          _messages.add({
            'id': 'emergency_${DateTime.now().millisecondsSinceEpoch}',
            'isAI': true,
            'isEmergencyCard': true,
            'text': '',
            'time': _formatTime(DateTime.now()),
            'role': 'assistant',
          });
        }
        _scrollToBottom();
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

    final isBlocked = _isSending || _isSendingPhoto || chatState.isLoading;
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
            const MedicalDisclaimerBannerWidget(compact: true),
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
            _buildQuickReplies(theme, isBlocked, inputBottomPadding),
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
    final isPhoto = msg['isPhoto'] == true;
    final isEmergencyCard = msg['isEmergencyCard'] == true;

    // Render emergency action card inline in the chat
    if (isEmergencyCard) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
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
            const Expanded(child: EmergencyActionCard()),
          ],
        ),
      );
    }

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
                    color: isAI
                        ? theme.colorScheme.surface
                        : (isPhoto
                              ? AppTheme.secondary.withAlpha(200)
                              : AppTheme.primary),
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

  Widget _buildQuickReplies(
    ThemeData theme,
    bool isBlocked,
    double bottomPadding,
  ) {
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
          final isPhotoChip = qr['text'] == '__PHOTO_CHECKIN__';
          return GestureDetector(
            onTap: isBlocked
                ? null
                : () => _handleQuickAction(qr['text'] ?? ''),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: isBlocked
                    ? theme.colorScheme.outlineVariant.withAlpha(40)
                    : (isPhotoChip
                          ? AppTheme.primary.withAlpha(20)
                          : AppTheme.secondary.withAlpha(15)),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: isBlocked
                      ? theme.colorScheme.outlineVariant.withAlpha(60)
                      : (isPhotoChip
                            ? AppTheme.primary.withAlpha(80)
                            : AppTheme.secondary.withAlpha(60)),
                ),
              ),
              child: Text(
                qr['label'] ?? '',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: isBlocked
                      ? theme.colorScheme.onSurfaceVariant
                      : (isPhotoChip ? AppTheme.primary : AppTheme.secondary),
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
