import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/haptics.dart';
import '../../../core/config/theme.dart';
import '../../../core/l10n/enum_labels.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../core/widgets/breakdown_row.dart';
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
      ? Pct.format(summary.profit / summary.revenue * 100)
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
    // Six rows plus a button exceed the default 9/16-of-screen cap on a short
    // phone (measured: 199px of overflow at 600dp tall), so let the sheet size
    // to its content and scroll only if that content is taller than the screen.
    isScrollControlled: true,
    builder: (sheetContext) => SingleChildScrollView(
      child: Padding(
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
            BreakdownRow(
              label: l10n.dashboard_revenue,
              value: Money.format(summary.revenue, currencyCode: currency),
              emphasize: true,
            ),
            BreakdownRow(
              label: l10n.dashboard_costOfGoods,
              value: Money.format(summary.cost, currencyCode: currency),
            ),
            BreakdownRow(
              label: l10n.dashboard_grossProfit,
              value: Money.format(summary.profit, currencyCode: currency),
              emphasize: true,
              valueColor: summary.profit < 0
                  ? colors.negative
                  : colors.positive,
            ),
            BreakdownRow(label: l10n.dashboard_margin, value: margin),
            BreakdownRow(
              label: l10n.dashboard_itemsSold,
              value: Money.compactCount(summary.unitsSold),
            ),
            BreakdownRow(label: l10n.dashboard_avgItemPrice, value: avgPrice),
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
    ),
  );
}
