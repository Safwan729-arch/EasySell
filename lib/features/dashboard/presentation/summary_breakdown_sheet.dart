import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/haptics.dart';
import '../../../core/config/theme.dart';
import '../../../shared/extensions/format.dart';
import '../../analytics/domain/analytics.dart';

/// Bottom sheet showing the period summary in full precision (with cents) — the
/// "exact figures" escape hatch behind the compact-formatted revenue hero. All
/// numbers come from the already-loaded [DashboardSummary]; no extra fetch.
Future<void> showSummaryBreakdownSheet(
  BuildContext context, {
  required DashboardSummary summary,
  required AnalyticsPeriod period,
  required String currency,
}) {
  AppHaptics.tap();
  final theme = Theme.of(context);
  final colors = theme.extension<AppColors>()!;

  final margin = summary.revenue > 0
      ? '${(summary.profit / summary.revenue * 100).toStringAsFixed(1)}%'
      : '—';
  final avgPrice = summary.unitsSold > 0
      ? Money.format(
          summary.revenue / summary.unitsSold,
          currencyCode: currency,
        )
      : '—';

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: theme.colorScheme.surface,
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Breakdown',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${period.label} · exact figures',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          _BreakdownRow(
            label: 'Revenue',
            value: Money.format(summary.revenue, currencyCode: currency),
            emphasize: true,
          ),
          _BreakdownRow(
            label: 'Cost of goods',
            value: Money.format(summary.cost, currencyCode: currency),
          ),
          _BreakdownRow(
            label: 'Gross profit',
            value: Money.format(summary.profit, currencyCode: currency),
            emphasize: true,
            valueColor: summary.profit < 0 ? colors.negative : colors.positive,
          ),
          _BreakdownRow(label: 'Margin', value: margin),
          _BreakdownRow(
            label: 'Items sold',
            value: Money.compactCount(summary.unitsSold),
          ),
          _BreakdownRow(label: 'Avg item price', value: avgPrice),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.of(sheetContext).pop();
                context.go('/analytics');
              },
              icon: const Icon(Icons.bar_chart_rounded, size: 18),
              label: const Text('View full report'),
            ),
          ),
        ],
      ),
    ),
  );
}

/// One label/value line in the breakdown sheet, divided by a hairline rule.
class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.label,
    required this.value,
    this.emphasize = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool emphasize;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueStyle =
        (emphasize ? theme.textTheme.titleMedium : theme.textTheme.titleSmall)
            ?.copyWith(
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w700,
              color: valueColor ?? theme.colorScheme.onSurface,
            );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Column(
        children: [
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 11),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(value, style: valueStyle),
            ],
          ),
        ],
      ),
    );
  }
}
