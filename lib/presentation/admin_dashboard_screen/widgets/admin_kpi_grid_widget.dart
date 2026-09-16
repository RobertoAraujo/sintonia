import 'package:flutter/material.dart';

import '../../../core/app_export.dart';

class AdminKpiGridWidget extends StatelessWidget {
  final List<Map<String, dynamic>> kpis;

  const AdminKpiGridWidget({super.key, required this.kpis});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.6,
      ),
      itemCount: kpis.length,
      itemBuilder: (context, index) => _KpiCard(kpi: kpis[index]),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final Map<String, dynamic> kpi;
  const _KpiCard({required this.kpi});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = Color(kpi['color'] as int);
    final deltaPositive = kpi['deltaPositive'] as bool;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withAlpha(31),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: CustomIconWidget(
                    iconName: kpi['iconName'] as String,
                    color: color,
                    size: 18,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: deltaPositive
                      ? AppTheme.success.withAlpha(26)
                      : AppTheme.error.withAlpha(26),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      deltaPositive
                          ? Icons.trending_up_rounded
                          : Icons.trending_down_rounded,
                      size: 10,
                      color: deltaPositive ? AppTheme.success : AppTheme.error,
                    ),
                  ],
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                kpi['value'] as String,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                kpi['label'] as String,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
