import 'package:flutter/material.dart';

import '../../../services/conversation_starters_service.dart';

/// Shows Gemini-generated conversation starters based on the friend's profile.
/// Tapping a suggestion calls [onSelected] so the parent can fill the input —
/// nothing is ever sent automatically.
class ConversationStartersWidget extends StatefulWidget {
  final String friendId;
  final String friendName;
  final ValueChanged<String> onSelected;
  final VoidCallback? onDismiss;

  const ConversationStartersWidget({
    super.key,
    required this.friendId,
    required this.friendName,
    required this.onSelected,
    this.onDismiss,
  });

  @override
  State<ConversationStartersWidget> createState() =>
      _ConversationStartersWidgetState();
}

class _ConversationStartersWidgetState
    extends State<ConversationStartersWidget> {
  List<String> _starters = const [];
  bool _isLoading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      _failed = false;
    });
    final result = await ConversationStartersService.instance.generateStarters(
      friendId: widget.friendId,
      friendNameFallback: widget.friendName,
      forceRefresh: forceRefresh,
    );
    if (!mounted) return;
    setState(() {
      _starters = result;
      _failed = result.isEmpty;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withAlpha(60),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.primary.withAlpha(50)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Sugestões do Gemini para começar',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              ),
              if (!_isLoading && !_failed)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _load(forceRefresh: true),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.refresh_rounded,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (widget.onDismiss != null)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: widget.onDismiss,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Baseadas no perfil de ${widget.friendName}. Toque para editar e enviar quando quiser.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          if (_isLoading)
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text(
                  'Analisando o perfil...',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            )
          else if (_failed)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _load(forceRefresh: true),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Tentar novamente'),
              ),
            )
          else
            Column(
              children: _starters
                  .map(
                    (s) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => widget.onSelected(s),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: scheme.outlineVariant.withAlpha(120),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    s,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.north_west_rounded,
                                  size: 16,
                                  color: scheme.primary,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
}