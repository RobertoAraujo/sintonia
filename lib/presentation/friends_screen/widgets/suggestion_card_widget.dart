import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';

import '../../../core/app_export.dart';
import '../../../widgets/status_badge_widget.dart';

class SuggestionCardWidget extends StatefulWidget {
  final Map<String, dynamic> suggestion;
  final VoidCallback onConnect;
  final bool isFriend;
  final VoidCallback? onViewProfile;

  const SuggestionCardWidget({
    super.key,
    required this.suggestion,
    required this.onConnect,
    this.isFriend = false,
    this.onViewProfile,
  });

  @override
  State<SuggestionCardWidget> createState() => _SuggestionCardWidgetState();
}

class _SuggestionCardWidgetState extends State<SuggestionCardWidget>
    with SingleTickerProviderStateMixin {
  bool _showBreakdown = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

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

  Color _connectionPotentialColor(String potential) {
    switch (potential.toLowerCase()) {
      case 'alta':
        return AppTheme.success;
      case 'media':
        return AppTheme.primary;
      default:
        return AppTheme.warning;
    }
  }

  String _connectionPotentialLabel(String potential) {
    switch (potential.toLowerCase()) {
      case 'alta':
        return '🔥 Conexão alta';
      case 'media':
        return '✨ Conexão média';
      default:
        return '💫 Conexão moderada';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suggestion = widget.suggestion;
    final compat = suggestion['compatibilityPct'] as int;
    final ndType = suggestion['neurodivType'] as String;
    final tags = (suggestion['sharedHyperfocuses'] as List)
        .map((e) {
          if (e is Map) return (e['name'] ?? e['label'] ?? '').toString();
          final s = e.toString().trim();
          if (s.startsWith('{') && s.contains('"name"')) {
            final match = RegExp(r'"name"\s*:\s*"([^"]+)"').firstMatch(s);
            return match?.group(1) ?? s;
          }
          return s;
        })
        .where((s) => s.isNotEmpty)
        .toList();
    final isConnecting = suggestion['isConnecting'] as bool;
    final distanceLabel = suggestion['distanceLabel'] as String?;

    final interestsScore = suggestion['interestsScore'] as int? ?? 0;
    final valuesScore = suggestion['valuesScore'] as int? ?? 0;
    final neurotypesScore = suggestion['neurotypesScore'] as int? ?? 0;
    final communicationScore = suggestion['communicationScore'] as int? ?? 0;
    final hasBreakdown =
        interestsScore > 0 ||
        valuesScore > 0 ||
        neurotypesScore > 0 ||
        communicationScore > 0;

    final aiInsight = suggestion['aiInsight'] as String? ?? '';
    final shortInsight = suggestion['shortInsight'] as String? ?? '';
    final aiRefined = suggestion['aiRefined'] as bool? ?? false;
    final connectionPotential =
        suggestion['connectionPotential'] as String? ?? '';

    // Use shortInsight for the inline badge, aiInsight for the expanded section
    final displayShortInsight = shortInsight.isNotEmpty
        ? shortInsight
        : (aiInsight.isNotEmpty && aiInsight.length <= 80 ? aiInsight : '');
    final displayDeepInsight = aiInsight.isNotEmpty ? aiInsight : '';

    final compatColor = compat >= 90
        ? AppTheme.success
        : compat >= 75
        ? AppTheme.primary
        : AppTheme.warning;

    final borderColor = aiRefined && compat >= 80
        ? const Color(0xFF7C3AED).withAlpha(70)
        : compat >= 80
        ? AppTheme.primary.withAlpha(55)
        : theme.colorScheme.outlineVariant.withAlpha(50);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20.0),
        border: Border.all(color: borderColor, width: aiRefined ? 1.5 : 1),
        boxShadow: [
          BoxShadow(
            color: aiRefined
                ? const Color(0xFF7C3AED).withAlpha(18)
                : Colors.black.withAlpha(18),
            blurRadius: aiRefined ? 14 : 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ──────────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar + compat badge
                GestureDetector(
                  onTap: widget.onViewProfile,
                  child: Stack(
                    children: [
                      // Pulse ring for high-compatibility AI-refined cards
                      if (aiRefined && compat >= 85)
                        AnimatedBuilder(
                          animation: _pulseAnimation,
                          builder: (context, child) => Container(
                            width: 62 + 8,
                            height: 62 + 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF7C3AED).withAlpha(
                                  (60 * _pulseAnimation.value).round(),
                                ),
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      Padding(
                        padding: EdgeInsets.all(
                          aiRefined && compat >= 85 ? 4 : 0,
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: compatColor.withAlpha(80),
                              width: 2.5,
                            ),
                          ),
                          child: ClipOval(
                            child: CustomImageWidget(
                              imageUrl: suggestion['imageUrl'] as String,
                              width: 62,
                              height: 62,
                              fit: BoxFit.cover,
                              semanticLabel:
                                  suggestion['imageSemantic'] as String,
                            ),
                          ),
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
                            color: aiRefined
                                ? const Color(0xFF7C3AED)
                                : compatColor,
                            borderRadius: BorderRadius.circular(20.0),
                            border: Border.all(
                              color: theme.colorScheme.surfaceContainerLow,
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    (aiRefined
                                            ? const Color(0xFF7C3AED)
                                            : compatColor)
                                        .withAlpha(60),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
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
                ),
                const SizedBox(width: 14),
                // Info column
                Expanded(
                  child: GestureDetector(
                    onTap: widget.onViewProfile,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Name + badges row
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                suggestion['name'] as String,
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14.sp,
                                  color: theme.colorScheme.onSurface,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (aiRefined) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF7C3AED),
                                      Color(0xFF9C6FE4),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(20.0),
                                ),
                                child: const Text(
                                  '🤖 Gemini',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                            ],
                            StatusBadgeWidget(
                              label: ndType,
                              color: _neurodivColor(ndType),
                              style: BadgeStyle.subtle,
                              fontSize: 10,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // Compat + distance + connection potential pills
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    (aiRefined
                                            ? const Color(0xFF7C3AED)
                                            : compatColor)
                                        .withAlpha(22),
                                borderRadius: BorderRadius.circular(20.0),
                              ),
                              child: Text(
                                '$compat% Compatível',
                                style: GoogleFonts.inter(
                                  fontSize: 10.sp,
                                  fontWeight: FontWeight.w700,
                                  color: aiRefined
                                      ? const Color(0xFF7C3AED)
                                      : compatColor,
                                ),
                              ),
                            ),
                            if (connectionPotential.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: _connectionPotentialColor(
                                    connectionPotential,
                                  ).withAlpha(18),
                                  borderRadius: BorderRadius.circular(20.0),
                                ),
                                child: Text(
                                  _connectionPotentialLabel(
                                    connectionPotential,
                                  ),
                                  style: GoogleFonts.inter(
                                    fontSize: 10.sp,
                                    fontWeight: FontWeight.w600,
                                    color: _connectionPotentialColor(
                                      connectionPotential,
                                    ),
                                  ),
                                ),
                              ),
                            if (distanceLabel != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withAlpha(18),
                                  borderRadius: BorderRadius.circular(20.0),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.location_on_rounded,
                                      size: 10,
                                      color: AppTheme.primary,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      distanceLabel,
                                      style: GoogleFonts.inter(
                                        fontSize: 10.sp,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Short AI insight or bio
                        if (displayShortInsight.isNotEmpty)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('✨ ', style: TextStyle(fontSize: 11)),
                              Expanded(
                                child: Text(
                                  displayShortInsight,
                                  style: GoogleFonts.inter(
                                    fontSize: 11.sp,
                                    color: const Color(0xFF9C6FE4),
                                    fontStyle: FontStyle.italic,
                                    height: 1.4,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          )
                        else
                          Text(
                            suggestion['bio'] as String,
                            style: GoogleFonts.inter(
                              fontSize: 12.sp,
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.4,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        const SizedBox(height: 8),
                        // Shared hyperfocuses chips
                        if (tags.isNotEmpty)
                          Wrap(
                            spacing: 5,
                            runSpacing: 5,
                            children: tags
                                .take(3)
                                .map(
                                  (tag) => Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.secondary.withAlpha(18),
                                      borderRadius: BorderRadius.circular(20.0),
                                      border: Border.all(
                                        color: AppTheme.secondary.withAlpha(55),
                                      ),
                                    ),
                                    child: Text(
                                      '⚡ $tag',
                                      style: GoogleFonts.inter(
                                        fontSize: 10.sp,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.secondary,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // ── Deep AI Insight section (only when AI-refined) ───────────
            if (aiRefined && displayDeepInsight.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF7C3AED).withAlpha(12),
                      const Color(0xFF4F46E5).withAlpha(8),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12.0),
                  border: Border.all(
                    color: const Color(0xFF7C3AED).withAlpha(45),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF7C3AED).withAlpha(25),
                            borderRadius: BorderRadius.circular(20.0),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('🤖', style: TextStyle(fontSize: 10)),
                              const SizedBox(width: 4),
                              Text(
                                'Análise Gemini',
                                style: GoogleFonts.inter(
                                  fontSize: 10.sp,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF7C3AED),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      displayDeepInsight,
                      style: GoogleFonts.inter(
                        fontSize: 11.sp,
                        color: theme.colorScheme.onSurface.withAlpha(200),
                        height: 1.5,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],

            // ── Compatibility breakdown ──────────────────────────────────
            if (hasBreakdown) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => setState(() => _showBreakdown = !_showBreakdown),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withAlpha(
                      80,
                    ),
                    borderRadius: BorderRadius.circular(10.0),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4.0),
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
                      const SizedBox(width: 10),
                      Icon(
                        _showBreakdown
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        _showBreakdown ? 'Ocultar' : 'Detalhes',
                        style: GoogleFonts.inter(
                          fontSize: 11.sp,
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_showBreakdown) ...[
                const SizedBox(height: 10),
                _buildBreakdownRow(
                  theme,
                  '⚡ Hiperfocuses',
                  interestsScore,
                  AppTheme.primary,
                  aiRefined: aiRefined,
                ),
                const SizedBox(height: 6),
                _buildBreakdownRow(
                  theme,
                  '💜 Valores',
                  valuesScore,
                  AppTheme.secondary,
                  aiRefined: aiRefined,
                ),
                const SizedBox(height: 6),
                _buildBreakdownRow(
                  theme,
                  '🧠 Neurotipo',
                  neurotypesScore,
                  AppTheme.teaColor,
                  aiRefined: aiRefined,
                ),
                const SizedBox(height: 6),
                _buildBreakdownRow(
                  theme,
                  '💬 Comunicação',
                  communicationScore,
                  AppTheme.success,
                  aiRefined: aiRefined,
                ),
                if (aiRefined) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        size: 11,
                        color: const Color(0xFF7C3AED).withAlpha(160),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Scores refinados por Gemini IA',
                        style: GoogleFonts.inter(
                          fontSize: 10.sp,
                          color: const Color(0xFF7C3AED).withAlpha(160),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 4),
              ],
            ],

            // ── Action buttons ───────────────────────────────────────────
            const SizedBox(height: 14),
            Divider(
              height: 1,
              thickness: 1,
              color: theme.colorScheme.outlineVariant.withAlpha(40),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                if (!widget.isFriend) ...[
                  Expanded(
                    child: FilledButton(
                      onPressed: isConnecting ? null : widget.onConnect,
                      style: FilledButton.styleFrom(
                        backgroundColor: isConnecting
                            ? theme.colorScheme.outlineVariant
                            : aiRefined
                            ? const Color(0xFF7C3AED)
                            : AppTheme.primary,
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(vertical: 0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                        elevation: 0,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isConnecting
                                ? Icons.check_rounded
                                : Icons.person_add_rounded,
                            size: 16,
                            color: isConnecting
                                ? theme.colorScheme.onSurfaceVariant
                                : Colors.white,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isConnecting ? 'Pedido enviado' : 'Conectar',
                            style: GoogleFonts.inter(
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w700,
                              color: isConnecting
                                  ? theme.colorScheme.onSurfaceVariant
                                  : Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onViewProfile,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: widget.isFriend
                          ? AppTheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                      side: BorderSide(
                        color: widget.isFriend
                            ? AppTheme.primary.withAlpha(100)
                            : theme.colorScheme.outlineVariant.withAlpha(100),
                      ),
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(vertical: 0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                    ),
                    child: Text(
                      'Ver perfil',
                      style: GoogleFonts.inter(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
    Color color, {
    bool aiRefined = false,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11.sp,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4.0),
            child: LinearProgressIndicator(
              value: score / 100,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(
                aiRefined ? color.withAlpha(200) : color,
              ),
              minHeight: 6,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 34,
          child: Text(
            '$score%',
            textAlign: TextAlign.right,
            style: GoogleFonts.inter(
              fontSize: 11.sp,
              color: aiRefined ? const Color(0xFF7C3AED) : color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
