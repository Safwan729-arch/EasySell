import 'package:flutter/material.dart';

import '../config/theme.dart';

/// One label/value line in an "exact figures" bottom sheet: an outlined row
/// (radius 16, ~60 high) with the label on the left and the figure on the
/// right.
///
/// Shared so every breakdown sheet reads the same way — the dashboard's period
/// summary and the inventory value sheet are the same idea reached from two
/// screens, and a shopkeeper should not have to re-learn the layout.
class BreakdownRow extends StatelessWidget {
  const BreakdownRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasize = false,
    this.valueColor,
  });

  final String label;
  final String value;

  /// Headline figures (revenue, profit, stock value) get the heavier
  /// treatment so the eye lands on them first.
  final bool emphasize;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final valueStyle = theme.textTheme.titleMedium?.copyWith(
      fontSize: emphasize ? 19 : 17,
      fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
      color: valueColor ?? theme.colorScheme.onSurface,
    );
    return Container(
      margin: const EdgeInsets.only(top: 10),
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: colors.rowDecoration(),
      child: Row(
        children: [
          // A long label (Bengali runs wider than English) must yield to the
          // figure rather than overflow the row.
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(value, style: valueStyle),
        ],
      ),
    );
  }
}
