import 'package:flutter/material.dart';

import '../../../core/app_export.dart';
import '../../../widgets/status_badge_widget.dart';

class SuggestionCardWidget extends StatefulWidget {
  final Map<String, dynamic> suggestion;
  final VoidCallback onConnect;

  const SuggestionCardWidget({
    super.key,
    required this.suggestion,
    required this.onConnect,
  });

  @override
  State<SuggestionCardWidget> createState() => _SuggestionCardWidgetState();
}

class _SuggestionCardWidgetState extends State<SuggestionCardWidget> {
  bool _showBreakdown = false;

  Color _neurodivColor(String type) {
    switch (type) {
      case 'TEA':
        return AppTheme.teaColor;
      case 'TDAH':
        return AppTheme.tdahColor;
      case 'Dislexia':
        return AppTheme.dyslexiaColor;
      case 'Tourette':
        return AppTheme.touretteColor;
      default:
        return AppTheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suggestion = widget.suggestion;
    final compat = suggestion['compatibilityPct'] as int;
    final ndType = suggestion['neurodivType'] as String;
    final tags = (suggestion['sharedHyperfocuses'] as List).cast<String>();
    final isConnecting = suggestion['isConnecting'] as bool;

    // Breakdown scores (may be absent for legacy data)
    final interestsScore = suggestion['interestsScore'] as int? ?? 0;
    final valuesScore = suggestion['valuesScore'] as int? ?? 0;
    final neurotypesScore = suggestion['neurotypesScore'] as int? ?? 0;
    final communicationScore = suggestion['communicationScore'] as int? ?? 0;
    final hasBreakdown =
        interestsScore > 0 ||
        valuesScore > 0 ||
        neurotypesScore > 0 ||
        communicationScore > 0;

    // AI refinement data
    final aiInsight = suggestion['aiInsight'] as String? ?? '';
    final aiRefined = suggestion['aiRefined'] as bool? ?? false;

    final compatColor = compat >= 90
        ? AppTheme.success
        : compat >= 75
        ? AppTheme.primary
        : AppTheme.warning;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: aiRefined && compat >= 80
              ? const Color(0xFF7C3AED).withAlpha(70)
              : compat >= 80
              ? AppTheme.primary.withAlpha(60)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar + compat badge
                Stack(
                  children: [
                    ClipOval(
                      child: CustomImageWidget(
                        imageUrl: suggestion['imageUrl'] as String,
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        semanticLabel: suggestion['imageSemantic'] as String,
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: compatColor,
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(
                            color: theme.colorScheme.surface,
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          '$compat%',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              suggestion['name'] as String,
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                          if (aiRefined)
                            Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF7C3AED).withAlpha(25),
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: const Text(
                                '🤖 IA',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF7C3AED),
                                ),
                              ),
                            ),
                          StatusBadgeWidget(
                            label: ndType,
                            color: _neurodivColor(ndType),
                            style: BadgeStyle.subtle,
                            fontSize: 10,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Show AI insight if available, otherwise bio
                      if (aiInsight.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF7C3AED).withAlpha(15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(0xFF7C3AED).withAlpha(40),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('✨ ', style: TextStyle(fontSize: 11)),
                              Expanded(
                                child: Text(
                                  aiInsight,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: const Color(0xFF7C3AED),
                                    fontStyle: FontStyle.italic,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Text(
                          suggestion['bio'] as String,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      const SizedBox(height: 8),
                      // Shared hyperfocuses
                      if (tags.isNotEmpty)
                        Row(
                          children: [
                            CustomIconWidget(
                              iconName: 'bolt_rounded',
                              color: AppTheme.primary,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                '${suggestion['sharedCount']} hiperfoco${(suggestion['sharedCount'] as int) > 1 ? 's' : ''} em comum: ${tags.take(2).join(', ')}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),

            // Compatibility breakdown (expandable)
            if (hasBreakdown) ...[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => setState(() => _showBreakdown = !_showBreakdown),
                child: Row(
                  children: [
                    // Mini score bar
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: compat / 100,
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            aiRefined ? const Color(0xFF7C3AED) : compatColor,
                          ),
                          minHeight: 5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      _showBreakdown
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      _showBreakdown ? 'Ocultar' : 'Detalhes',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (_showBreakdown) ...[
                const SizedBox(height: 10),
                _buildBreakdownRow(
                  theme,
                  '⚡ Hiperfocuses',
                  interestsScore,
                  AppTheme.primary,
                ),
                const SizedBox(height: 6),
                _buildBreakdownRow(
                  theme,
                  '💜 Valores',
                  valuesScore,
                  AppTheme.secondary,
                ),
                const SizedBox(height: 6),
                _buildBreakdownRow(
                  theme,
                  '🧠 Neurotipo',
                  neurotypesScore,
                  AppTheme.teaColor,
                ),
                const SizedBox(height: 6),
                _buildBreakdownRow(
                  theme,
                  '💬 Comunicação',
                  communicationScore,
                  AppTheme.success,
                ),
                const SizedBox(height: 4),
              ],
            ],

            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: isConnecting ? null : widget.onConnect,
                    style: FilledButton.styleFrom(
                      backgroundColor: isConnecting
                          ? theme.colorScheme.outlineVariant
                          : AppTheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      minimumSize: const Size(0, 36),
                    ),
                    child: Text(
                      isConnecting ? 'Pedido enviado ✓' : 'Conectar',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isConnecting
                            ? theme.colorScheme.onSurfaceVariant
                            : Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.onSurfaceVariant,
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 12,
                    ),
                    minimumSize: const Size(0, 36),
                  ),
                  child: const Text(
                    'Ver perfil',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBreakdownRow(
    ThemeData theme,
    String label,
    int score,
    Color color,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: score / 100,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 6,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 32,
          child: Text(
            '$score%',
            textAlign: TextAlign.right,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
