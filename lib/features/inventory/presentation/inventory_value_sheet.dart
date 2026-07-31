import 'package:flutter/material.dart';

import '../../../core/config/haptics.dart';
import '../../../core/config/theme.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../core/widgets/breakdown_row.dart';
import '../../../shared/extensions/format.dart';
import '../domain/inventory_totals.dart';

/// Bottom sheet showing the full-precision inventory value — the "exact figures"
/// escape hatch behind the compact `N items · <value>` line in the Items header,
/// which has to share a narrow row with three action buttons and so cannot show
/// a long figure in full.
///
/// Deliberately the same shape as the dashboard's `showSummaryBreakdownSheet`
/// (same [BreakdownRow], same title/subtitle pair): a shopkeeper who has learned
/// that tapping a squeezed number reveals the real one should find the same
/// thing here. Everything is derived from the already-loaded product list.
Future<void> showInventoryValueSheet(
  BuildContext context, {
  required InventoryTotals totals,
  required String currency,
}) {
  AppHaptics.tap();
  final theme = Theme.of(context);
  final colors = theme.extension<AppColors>()!;
  final l10n = context.l10n;

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: theme.colorScheme.surface,
    // Five rows exceed the default 9/16-of-screen cap on a short phone, so let
    // the sheet size to its content and scroll only if it outgrows the screen.
    // Matches the dashboard sheet, which had to be fixed for the same reason.
    isScrollControlled: true,
    builder: (_) => SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.inventory_valueTitle,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              l10n.inventory_valueExact,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            // The headline first: this is the number the header had to truncate.
            BreakdownRow(
              label: l10n.inventory_statInventoryValue,
              value: Money.format(totals.costValue, currencyCode: currency),
              emphasize: true,
            ),
            BreakdownRow(
              label: l10n.inventory_valueRetail,
              value: Money.format(totals.retailValue, currencyCode: currency),
            ),
            BreakdownRow(
              label: l10n.inventory_valuePotentialProfit,
              value: Money.format(
                totals.potentialProfit,
                currencyCode: currency,
              ),
              emphasize: true,
              valueColor: totals.potentialProfit < 0
                  ? colors.negative
                  : colors.positive,
            ),
            BreakdownRow(
              label: l10n.inventory_valueProducts,
              value: Money.compactCount(totals.productCount),
            ),
            BreakdownRow(
              label: l10n.inventory_filterLowStock,
              value: Money.compactCount(totals.lowStockCount),
              valueColor: totals.lowStockCount > 0 ? colors.negative : null,
            ),
          ],
        ),
      ),
    ),
  );
}
