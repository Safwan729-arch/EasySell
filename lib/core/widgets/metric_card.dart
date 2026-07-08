import 'package:flutter/material.dart';

import '../config/theme.dart';
import 'animated_count.dart';
import 'delta_chip.dart';

/// A stat card: small label with an arrow-style icon top-right, a big bold value,
/// and an optional delta chip or subtitle. Matches the reference "Workload /
/// Hours / Budget" cards.
///
/// When [animatedValue] + [valueFormatter] are supplied the figure tallies up
/// on appear (via [AnimatedCount]); otherwise the static [value] string renders.
class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    this.animatedValue,
    this.valueFormatter,
    this.icon,
    this.color,
    this.deltaPercent,
    this.subtitle,
    this.filled = false,
  });

  final String label;
  final String value;
  final double? animatedValue;
  final String Function(double)? valueFormatter;
  final IconData? icon;
  final Color? color;
  final double? deltaPercent;
  final String? subtitle;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = theme.extension<AppColors>()!;
    // Value/subtitle ink: white on a filled (blue) card; otherwise the supplied
    // accent color (e.g. amber for low-stock) or the default dark text.
    final onCard = filled
        ? appColors.heroOnAccent
        : (color ?? theme.colorScheme.onSurface);
    final labelColor = filled
        ? appColors.heroOnAccent.withValues(alpha: 0.7)
        : theme.colorScheme.onSurfaceVariant;
    final subtitleColor = filled
        ? appColors.heroOnAccent.withValues(alpha: 0.8)
        : (color ?? theme.colorScheme.onSurfaceVariant);
    final valueStyle = theme.textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w800,
      color: onCard,
    );
    final animate = animatedValue != null && valueFormatter != null;

    return Card(
      color: filled ? theme.colorScheme.primary : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: labelColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (icon != null) Icon(icon, size: 16, color: onCard),
              ],
            ),
            const SizedBox(height: 12),
            animate
                ? AnimatedCount(
                    value: animatedValue!,
                    formatter: valueFormatter!,
                    style: valueStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                : Text(
                    value,
                    style: valueStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
            if (deltaPercent != null) ...[
              const SizedBox(height: 6),
              DeltaChip(percent: deltaPercent!),
            ],
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: subtitleColor,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
