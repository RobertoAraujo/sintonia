import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../theme/app_theme.dart';

class AdminReportsChartWidget extends StatelessWidget {
  const AdminReportsChartWidget({super.key});

  // Reports per day for the last 7 days — realistic variance with a spike
  static const List<double> _reportData = [4, 7, 5, 12, 8, 18, 11];
  static const List<String> _dayLabels = [
    'Qui',
    'Sex',
    'Sáb',
    'Dom',
    'Seg',
    'Ter',
    'Qua',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = AppTheme.primary;
    final errorColor = AppTheme.error;

    return Container(
      height: 200,
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: 22,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              tooltipBgColor: theme.colorScheme.inverseSurface,
              getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                  BarTooltipItem(
                    '${rod.toY.toInt()} denúncias',
                    TextStyle(
                      color: theme.colorScheme.onInverseSurface,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= _dayLabels.length) {
                    return const SizedBox();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _dayLabels[idx],
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                },
                reservedSize: 24,
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 5,
                reservedSize: 28,
                getTitlesWidget: (value, meta) => Text(
                  value.toInt().toString(),
                  style: TextStyle(
                    fontSize: 9,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: 5,
            getDrawingHorizontalLine: (_) => FlLine(
              color: theme.colorScheme.outlineVariant,
              strokeWidth: 1,
              dashArray: [4, 4],
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(_reportData.length, (index) {
            final isSpike = _reportData[index] >= 15;
            return BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: _reportData[index],
                  color: isSpike ? errorColor : primary,
                  width: 24,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(6),
                  ),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: 22,
                    color: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}
