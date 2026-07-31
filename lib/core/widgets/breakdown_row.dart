import 'package:flutter/material.dart';

/// One label/value line in an "exact figures" bottom sheet, divided from the
/// previous line by a hairline rule.
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

  /// Headline figures (revenue, profit, stock value) get the larger, heavier
  /// treatment so the eye lands on them first.
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
              // A long label (Bengali runs wider than English) must yield to the
              // figure rather than overflow the row.
              Flexible(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(value, style: valueStyle),
            ],
          ),
        ],
      ),
    );
  }
}
