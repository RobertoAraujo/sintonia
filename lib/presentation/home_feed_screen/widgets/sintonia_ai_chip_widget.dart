import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/chat_notifier.dart';
import '../../../services/supabase_service.dart';
import '../../../theme/app_theme.dart';

class SintoniaAiChipWidget extends ConsumerStatefulWidget {
  final VoidCallback onTap;

  const SintoniaAiChipWidget({super.key, required this.onTap});

  @override
  ConsumerState<SintoniaAiChipWidget> createState() =>
      _SintoniaAiChipWidgetState();
}

class _SintoniaAiChipWidgetState extends ConsumerState<SintoniaAiChipWidget> {
  final String _suggestion =
      'Tenho sugestões de conexão personalizadas para você hoje ✨';
  bool _isLoading = false;

  static const _config = ChatConfig(
    provider: 'GEMINI',
    model: 'gemini/gemini-3.7-flash',
    streaming: false,
  );

  @override
  void initState() {
    super.initState();
    _loadAiSuggestion();
  }

  Future<void> _loadAiSuggestion() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final profile = await SupabaseService.instance.fetchCurrentUserProfile();
      if (!mounted) return;

      final hyperfocuses =
          (profile?['hyperfocuses'] as List?)
              ?.map((e) => e.toString())
              .take(3)
              .join(', ') ??
          '';
      final name = (profile?['display_name'] as String?) ?? '';

      final messages = [
        {
          'role': 'system',
          'content':
              'Você é a SintonIA, assistente de apoio para pessoas neurodivergentes. '
              'Gere UMA frase curta e acolhedora (máx 12 palavras) para motivar o usuário a explorar conexões sociais hoje. '
              'Use emojis com moderação. Seja calorosa e específica se possível.',
        },
        {
          'role': 'user',
          'content':
              'Gere uma frase motivacional curta para ${name.isNotEmpty ? name : "mim"} '
              '${hyperfocuses.isNotEmpty ? "que tem interesse em: $hyperfocuses" : ""}. '
              'Máx 12 palavras, com emoji.',
        },
      ];

      await ref
          .read(chatNotifierProvider(_config).notifier)
          .sendMessage(
            messages.map((m) => Map<String, dynamic>.from(m)).toList(),
            parameters: {'temperature': 0.8, 'max_tokens': 60},
          );
    } catch (_) {
      // Keep default suggestion on error
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chatState = ref.watch(chatNotifierProvider(_config));

    final displayText = chatState.response.isNotEmpty
        ? chatState.response.trim()
        : _suggestion;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.primary.withAlpha(31),
              AppTheme.secondary.withAlpha(31),
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.primary.withAlpha(77)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.primary, AppTheme.secondary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SintonIA',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: AppTheme.primary,
                    ),
                  ),
                  chatState.isLoading
                      ? Row(
                          children: [
                            SizedBox(
                              width: 10,
                              height: 10,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: AppTheme.secondary.withAlpha(180),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Preparando sua sugestão...',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        )
                      : Text(
                          displayText,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: AppTheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}
