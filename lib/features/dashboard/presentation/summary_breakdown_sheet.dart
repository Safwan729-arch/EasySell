import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/haptics.dart';
import '../../../core/config/theme.dart';
import '../../../core/l10n/enum_labels.dart';
import '../../../core/l10n/l10n_ext.dart';
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
  final l10n = context.l10n;

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
            l10n.dashboard_breakdown,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.dashboard_exactFigures(periodLabel(l10n, period)),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          _BreakdownRow(
            label: l10n.dashboard_revenue,
            value: Money.format(summary.revenue, currencyCode: currency),
            emphasize: true,
          ),
          _BreakdownRow(
            label: l10n.dashboard_costOfGoods,
            value: Money.format(summary.cost, currencyCode: currency),
          ),
          _BreakdownRow(
            label: l10n.dashboard_grossProfit,
            value: Money.format(summary.profit, currencyCode: currency),
            emphasize: true,
            valueColor: summary.profit < 0 ? colors.negative : colors.positive,
          ),
          _BreakdownRow(label: l10n.dashboard_margin, value: margin),
          _BreakdownRow(
            label: l10n.dashboard_itemsSold,
            value: Money.compactCount(summary.unitsSold),
          ),
          _BreakdownRow(label: l10n.dashboard_avgItemPrice, value: avgPrice),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.of(sheetContext).pop();
                context.go('/analytics');
              },
              icon: const Icon(Icons.bar_chart_rounded, size: 18),
              label: Text(l10n.dashboard_viewFullReport),
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
