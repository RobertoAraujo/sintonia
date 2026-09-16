import 'package:flutter/material.dart';

import '../../core/app_export.dart';
import '../../services/supabase_service.dart';
import './widgets/admin_actions_log_widget.dart';
import './widgets/admin_kpi_grid_widget.dart';
import './widgets/admin_reports_chart_widget.dart';
import './widgets/admin_reports_queue_widget.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  bool _isCheckingAdmin = true;
  bool _isAdmin = false;
  bool _isLoadingKpis = true;
  bool _isLoadingReports = true;

  List<Map<String, dynamic>> _kpisMaps = [];
  List<Map<String, dynamic>> _reportsMaps = [];
  String _lastUpdated = '';

  // Action log is derived from resolved/dismissed reports
  final List<Map<String, dynamic>> _actionLogMaps = [];

  @override
  void initState() {
    super.initState();
    _checkAdminAccess();
  }

  Future<void> _checkAdminAccess() async {
    try {
      final profile = await SupabaseService.instance.fetchCurrentUserProfile();
      // Check role field from user_profiles
      final role = profile?['role'] as String? ?? 'user';
      final isAdmin = role == 'admin' || role == 'moderator';
      if (mounted) {
        setState(() {
          _isAdmin = isAdmin;
          _isCheckingAdmin = false;
        });
        if (isAdmin) {
          _loadDashboardData();
        } else {
          context.go('/home-feed-screen');
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isCheckingAdmin = false);
        context.go('/home-feed-screen');
      }
    }
  }

  Future<void> _loadDashboardData() async {
    _loadKpis();
    _loadReports();
  }

  Future<void> _loadKpis() async {
    setState(() => _isLoadingKpis = true);
    try {
      final kpis = await SupabaseService.instance.fetchAdminKpis();
      if (!mounted) return;
      setState(() {
        _kpisMaps = [
          {
            'label': 'Usuários Totais',
            'value': _formatNumber(kpis['users'] ?? 0),
            'delta': 'Total cadastrado',
            'deltaPositive': true,
            'iconName': 'people_rounded',
            'color': 0xFF2D7D6F,
          },
          {
            'label': 'Posts Publicados',
            'value': _formatNumber(kpis['posts'] ?? 0),
            'delta': 'Conteúdo ativo',
            'deltaPositive': true,
            'iconName': 'article_rounded',
            'color': 0xFF7C6FC4,
          },
          {
            'label': 'Denúncias Abertas',
            'value': _formatNumber(kpis['openReports'] ?? 0),
            'delta': 'Aguardando revisão',
            'deltaPositive': (kpis['openReports'] ?? 0) == 0,
            'iconName': 'flag_rounded',
            'color': 0xFFB91C1C,
          },
          {
            'label': 'Grupos Ativos',
            'value': _formatNumber(kpis['groups'] ?? 0),
            'delta': 'Comunidades',
            'deltaPositive': true,
            'iconName': 'group_rounded',
            'color': 0xFF1B4FD8,
          },
        ];
        _isLoadingKpis = false;
        _lastUpdated =
            '${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}';
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingKpis = false);
    }
  }

  Future<void> _loadReports() async {
    setState(() => _isLoadingReports = true);
    try {
      final rows = await SupabaseService.instance.fetchReports(limit: 30);
      if (!mounted) return;
      final mapped = rows.map((r) {
        final reporter = r['reporter'] as Map<String, dynamic>? ?? {};
        final reportedUser = r['reported_user'] as Map<String, dynamic>? ?? {};
        final createdAt = r['created_at'] != null
            ? DateTime.tryParse(r['created_at'].toString())?.toLocal()
            : null;
        final status = r['status'] as String? ?? 'open';
        return {
          'id': r['id'] ?? '',
          'reportedUser': reportedUser['full_name'] ?? 'Usuário',
          'reporterName': reporter['full_name'] ?? 'Usuário',
          'reason': _translateReason(r['reason'] as String? ?? 'other'),
          'description': r['description'] ?? '',
          'severity': _severityFromReason(r['reason'] as String? ?? 'other'),
          'timestamp': createdAt != null ? _formatDateTime(createdAt) : '',
          'status': _translateStatus(status),
          'rawStatus': status,
        };
      }).toList();
      setState(() {
        _reportsMaps = mapped;
        _isLoadingReports = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingReports = false);
    }
  }

  String _formatNumber(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return n.toString();
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _translateReason(String reason) {
    const map = {
      'harassment': 'Assédio',
      'hate_speech': 'Discurso de ódio',
      'spam': 'Spam',
      'misinformation': 'Desinformação',
      'inappropriate_content': 'Conteúdo inadequado',
      'other': 'Outro',
    };
    return map[reason] ?? reason;
  }

  String _severityFromReason(String reason) {
    if (reason == 'harassment' || reason == 'hate_speech') return 'Alta';
    if (reason == 'spam' || reason == 'misinformation') return 'Média';
    return 'Baixa';
  }

  String _translateStatus(String status) {
    const map = {
      'open': 'Pendente',
      'reviewing': 'Em análise',
      'resolved': 'Resolvida',
      'dismissed': 'Arquivada',
    };
    return map[status] ?? status;
  }

  Future<void> _handleReportAction(String reportId, String action) async {
    final newStatus = action == 'ban'
        ? 'resolved'
        : action == 'review'
        ? 'reviewing'
        : 'dismissed';

    final success = await SupabaseService.instance.updateReportStatus(
      reportId,
      newStatus,
    );

    if (!mounted) return;
    if (success) {
      setState(() {
        final idx = _reportsMaps.indexWhere((r) => r['id'] == reportId);
        if (idx != -1) {
          _reportsMaps[idx]['status'] = _translateStatus(newStatus);
          _reportsMaps[idx]['rawStatus'] = newStatus;
          // Add to action log
          _actionLogMaps.insert(0, {
            'id': 'act_${DateTime.now().millisecondsSinceEpoch}',
            'adminName': 'Admin',
            'action': action == 'ban'
                ? 'Denúncia resolvida'
                : action == 'review'
                ? 'Denúncia em análise'
                : 'Denúncia arquivada',
            'target': 'Report #${reportId.substring(0, 8)}',
            'timestamp': _formatDateTime(DateTime.now()),
            'actionType': action,
          });
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == 'ban'
                ? 'Denúncia resolvida ✓'
                : action == 'review'
                ? 'Denúncia em análise'
                : 'Denúncia arquivada',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erro ao atualizar denúncia. Tente novamente.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingAdmin) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_isAdmin) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final isTablet = MediaQuery.of(context).size.width >= 840;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: CustomIconWidget(
            iconName: 'arrow_back_rounded',
            color: theme.colorScheme.onSurface,
            size: 24,
          ),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.error.withAlpha(31),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.admin_panel_settings_rounded,
                    size: 16,
                    color: AppTheme.error,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'ADMIN',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.error,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text('Dashboard', style: theme.textTheme.headlineSmall),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _loadDashboardData,
            icon: CustomIconWidget(
              iconName: 'refresh_rounded',
              color: theme.colorScheme.onSurface,
              size: 22,
            ),
          ),
          if (_lastUpdated.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Text(
                  'Atualizado $_lastUpdated',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: isTablet ? _buildTabletLayout(theme) : _buildPhoneLayout(theme),
      ),
    );
  }

  Widget _buildPhoneLayout(ThemeData theme) {
    return RefreshIndicator(
      onRefresh: _loadDashboardData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _isLoadingKpis
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : AdminKpiGridWidget(kpis: _kpisMaps),
            const SizedBox(height: 20),
            Text(
              'Denúncias por Dia (últimos 7 dias)',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            AdminReportsChartWidget(),
            const SizedBox(height: 20),
            Row(
              children: [
                Text('Fila de Denúncias', style: theme.textTheme.titleSmall),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withAlpha(26),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    _reportsMaps
                        .where((r) => r['rawStatus'] == 'open')
                        .length
                        .toString(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.error,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _isLoadingReports
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : AdminReportsQueueWidget(
                    reports: _reportsMaps,
                    onAction: _handleReportAction,
                  ),
            const SizedBox(height: 20),
            Text('Log de Ações Recentes', style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            AdminActionsLogWidget(actions: _actionLogMaps),
          ],
        ),
      ),
    );
  }

  Widget _buildTabletLayout(ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _isLoadingKpis
                    ? const Center(child: CircularProgressIndicator())
                    : AdminKpiGridWidget(kpis: _kpisMaps),
                const SizedBox(height: 20),
                Text('Denúncias por Dia', style: theme.textTheme.titleSmall),
                const SizedBox(height: 12),
                AdminReportsChartWidget(),
              ],
            ),
          ),
        ),
        VerticalDivider(width: 1, color: theme.colorScheme.outlineVariant),
        Expanded(
          flex: 2,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Fila de Denúncias',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.error.withAlpha(26),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        _reportsMaps
                            .where((r) => r['rawStatus'] == 'open')
                            .length
                            .toString(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _isLoadingReports
                    ? const Center(child: CircularProgressIndicator())
                    : AdminReportsQueueWidget(
                        reports: _reportsMaps,
                        onAction: _handleReportAction,
                      ),
                const SizedBox(height: 20),
                Text('Log de Ações', style: theme.textTheme.titleSmall),
                const SizedBox(height: 12),
                AdminActionsLogWidget(actions: _actionLogMaps),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
