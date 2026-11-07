import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

/// Dialog for reporting content or users.
/// Shows reason options and submits to the reports table.
class ReportContentDialog extends StatefulWidget {
  final String contentType; // 'post', 'comment', 'message', 'profile'
  final String? contentId;
  final String? reportedUserId;
  final String? postAuthorId; // author of the post being reported

  const ReportContentDialog({
    super.key,
    required this.contentType,
    this.contentId,
    this.reportedUserId,
    this.postAuthorId,
  });

  @override
  State<ReportContentDialog> createState() => _ReportContentDialogState();
}

class _ReportContentDialogState extends State<ReportContentDialog> {
  String? _selectedReason;
  final TextEditingController _detailsCtrl = TextEditingController();
  bool _isSubmitting = false;

  static const List<Map<String, String>> _reasons = [
    {
      'value': 'Discurso de ódio ou discriminação',
      'label': '🔴 Discurso de ódio ou discriminação',
    },
    {
      'value': 'Assédio, bullying ou ameaças',
      'label': '🔴 Assédio, bullying ou ameaças',
    },
    {
      'value': 'Conteúdo explícito ou sexualmente inadequado',
      'label': '🔴 Conteúdo explícito ou sexualmente inadequado',
    },
    {
      'value': 'Spam, fraude ou perfil falso',
      'label': '🔴 Spam, fraude ou perfil falso',
    },
    {'value': 'Outro', 'label': '🔴 Outro'},
  ];

  bool get _isOtherSelected => _selectedReason == 'Outro';

  @override
  void dispose() {
    _detailsCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedReason == null) return;
    if (_isOtherSelected && _detailsCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, descreva o motivo da denúncia.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await SupabaseService.instance.submitReport(
        reportedUserId: widget.reportedUserId,
        contentType: widget.contentType,
        contentId: widget.contentId,
        reason: _selectedReason!,
        details: _isOtherSelected ? _detailsCtrl.text.trim() : null,
        postAuthorId: widget.postAuthorId,
      );
      if (mounted) {
        Navigator.pop(context);
        _showConfirmationDialog();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Erro ao enviar denúncia. Tente novamente.'),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showConfirmationDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.withAlpha(20),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: Colors.green,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Denúncia Enviada',
              style: GoogleFonts.nunitoSans(
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: Text(
          'Obrigado. Sua denúncia foi enviada e nossa equipe revisará o perfil em até 24 horas.',
          style: GoogleFonts.nunitoSans(fontSize: 14),
        ),
        actions: [
          if (widget.reportedUserId != null)
            TextButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _blockUser();
              },
              icon: const Icon(
                Icons.block_rounded,
                color: Colors.red,
                size: 18,
              ),
              label: const Text(
                'Bloquear este usuário',
                style: TextStyle(color: Colors.red),
              ),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<void> _blockUser() async {
    if (widget.reportedUserId == null) return;
    try {
      await SupabaseService.instance.submitReport(
        reportedUserId: widget.reportedUserId,
        contentType: 'profile',
        reason: 'Outro',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Usuário bloqueado com sucesso.'),
            backgroundColor: AppTheme.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível bloquear o usuário.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.error.withAlpha(20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.flag_rounded, color: AppTheme.error, size: 20),
          ),
          const SizedBox(width: 10),
          Text(
            'Denunciar',
            style: GoogleFonts.nunitoSans(
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Por que você está denunciando?',
                style: GoogleFonts.nunitoSans(
                  fontSize: 13,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              ..._reasons.map(
                (reason) => RadioListTile<String>(
                  value: reason['value']!,
                  groupValue: _selectedReason,
                  onChanged: (v) => setState(() => _selectedReason = v),
                  title: Text(
                    reason['label']!,
                    style: GoogleFonts.nunitoSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  activeColor: AppTheme.error,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
              // "Outro" text field — shown only when "Outro" is selected
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                child: _isOtherSelected
                    ? Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: TextField(
                          controller: _detailsCtrl,
                          maxLines: 3,
                          minLines: 2,
                          autofocus: true,
                          decoration: InputDecoration(
                            hintText: 'Descreva o motivo (obrigatório)...',
                            hintStyle: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            filled: true,
                            fillColor:
                                theme.colorScheme.surfaceContainerHighest,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.all(12),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: (_selectedReason != null && !_isSubmitting)
              ? _submit
              : null,
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.error,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'Enviar denúncia',
                  style: TextStyle(color: Colors.white),
                ),
        ),
      ],
    );
  }
}

/// Helper to show the report dialog from anywhere.
void showReportDialog(
  BuildContext context, {
  required String contentType,
  String? contentId,
  String? reportedUserId,
  String? postAuthorId,
}) {
  showDialog(
    context: context,
    builder: (_) => ReportContentDialog(
      contentType: contentType,
      contentId: contentId,
      postAuthorId: postAuthorId,
      reportedUserId: reportedUserId,
    ),
  );
}
