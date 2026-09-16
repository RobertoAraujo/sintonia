import 'package:flutter/material.dart';

import '../../../core/app_export.dart';

class AdminReportsQueueWidget extends StatelessWidget {
  final List<Map<String, dynamic>> reports;
  final void Function(String reportId, String action) onAction;

  const AdminReportsQueueWidget({
    super.key,
    required this.reports,
    required this.onAction,
  });

  Color _severityColor(String severity) {
    switch (severity) {
      case 'Alta':
        return AppTheme.error;
      case 'Média':
        return AppTheme.warning;
      default:
        return AppTheme.info;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Pendente':
        return AppTheme.warning;
      case 'Em análise':
        return AppTheme.info;
      case 'Resolvida — Banido':
        return AppTheme.error;
      case 'Arquivada':
        return AppTheme.success;
      default:
        return AppTheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: reports
          .map(
            (report) => _ReportCard(
              report: report,
              onAction: onAction,
              severityColor: _severityColor(report['severity'] as String),
              statusColor: _statusColor(report['status'] as String),
            ),
          )
          .toList(),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final Map<String, dynamic> report;
  final void Function(String, String) onAction;
  final Color severityColor;
  final Color statusColor;

  const _ReportCard({
    required this.report,
    required this.onAction,
    required this.severityColor,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = report['status'] as String;
    final isResolved = status == 'Arquivada' || status.startsWith('Resolvida');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isResolved
              ? theme.colorScheme.outlineVariant
              : severityColor.withAlpha(77),
        ),
        boxShadow: isResolved
            ? null
            : [
                BoxShadow(
                  color: severityColor.withAlpha(15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: severityColor.withAlpha(26),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(
                          report['severity'] as String,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: severityColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withAlpha(26),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  report['timestamp'] as String,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                CustomIconWidget(
                  iconName: 'flag_rounded',
                  color: severityColor,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Text(
                  report['reason'] as String,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              report['description'] as String,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.person_outline_rounded,
                  size: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  'Denunciado: ${report['reportedUser']}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  Icons.person_add_outlined,
                  size: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Por: ${report['reporterName']}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (!isResolved) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          onAction(report['id'] as String, 'dismiss'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.onSurfaceVariant,
                        side: BorderSide(
                          color: theme.colorScheme.outlineVariant,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        minimumSize: const Size(0, 32),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Arquivar',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          onAction(report['id'] as String, 'review'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.info,
                        side: BorderSide(color: AppTheme.info.withAlpha(128)),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        minimumSize: const Size(0, 32),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Analisar',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: FilledButton(
                      onPressed: () =>
                          _showBanConfirmation(context, report['id'] as String),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.error,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        minimumSize: const Size(0, 32),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Banir',
                        style: TextStyle(fontSize: 12, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showBanConfirmation(BuildContext context, String reportId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Confirmar banimento'),
        content: const Text(
          'Tem certeza que deseja banir este usuário? Esta ação não pode ser desfeita facilmente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              onAction(reportId, 'ban');
            },
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Banir', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
