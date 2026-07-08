import 'package:flutter/material.dart';

import '../../../core/config/theme.dart';
import '../../../shared/extensions/format.dart';

/// The dashboard's primary card: a brand-filled hero that leads with period
/// revenue and folds profit, margin and units into one glance. Money figures are
/// compact-formatted ([Money.compact]) and every value auto-shrinks via
/// [FittedBox] so large numbers (busy months, high-denomination currencies)
/// never overflow. Tapping anywhere opens the exact-figures breakdown sheet.
class RevenueHero extends StatelessWidget {
  const RevenueHero({
    super.key,
    required this.revenue,
    required this.profit,
    required this.marginPercent,
    required this.unitsSold,
    required this.currency,
    required this.periodWord,
    required this.deltaPercent,
    required this.showDeltaSuffix,
    required this.onTap,
  });

  final double revenue;
  final double profit;
  final double marginPercent;
  final int unitsSold;
  final String currency;
  final String periodWord;

  /// Day-over-day revenue change; null hides the delta chip.
  final double? deltaPercent;

  /// Whether to append "vs yesterday" — only meaningful for the Today period.
  final bool showDeltaSuffix;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onAccent = theme.extension<AppColors>()!.heroOnAccent;

    return Card(
      color: theme.colorScheme.primary,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Revenue · $periodWord',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: onAccent.withValues(alpha: 0.75),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        Money.compact(revenue, currencyCode: currency),
                        maxLines: 1,
                        style: theme.textTheme.displaySmall?.copyWith(
                          color: onAccent,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  if (deltaPercent != null) ...[
                    const SizedBox(height: 10),
                    _DeltaPill(
                      percent: deltaPercent!,
                      suffix: showDeltaSuffix ? 'vs yesterday' : null,
                      onAccent: onAccent,
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _HeroStat(
                        label: 'Profit',
                        value: Money.compact(profit, currencyCode: currency),
                        onAccent: onAccent,
                      ),
                      _HeroStat(
                        label: 'Margin',
                        value: '${marginPercent.toStringAsFixed(1)}%',
                        onAccent: onAccent,
                      ),
                      _HeroStat(
                        label: 'Items sold',
                        value: Money.compactCount(unitsSold),
                        onAccent: onAccent,
                      ),
                    ],
                  ),
                ],
              ),
              Positioned(
                top: 0,
                right: 0,
                child: _ExactChip(onAccent: onAccent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One column in the hero's profit/margin/units row. [Expanded] + scale-down so
/// three values always share width and never overflow.
class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.label,
    required this.value,
    required this.onAccent,
  });

  final String label;
  final String value;
  final Color onAccent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: onAccent.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 2),
          Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: onAccent,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Translucent delta pill rendered on the brand fill (white-on-blue), e.g.
/// "▲ 12% vs yesterday".
class _DeltaPill extends StatelessWidget {
  const _DeltaPill({
    required this.percent,
    required this.suffix,
    required this.onAccent,
  });

  final double percent;
  final String? suffix;
  final Color onAccent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final up = percent >= 0;
    var num = percent.abs().toStringAsFixed(1);
    if (num.endsWith('.0')) num = num.substring(0, num.length - 2);
    final text = suffix == null ? '$num%' : '$num% $suffix';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: onAccent.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
            size: 14,
            color: onAccent,
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: theme.textTheme.labelMedium?.copyWith(
              color: onAccent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// The "⤢" affordance signalling the hero is tappable to reveal exact figures.
/// The expand glyph alone is enough — no "EXACT" label needed.
class _ExactChip extends StatelessWidget {
  const _ExactChip({required this.onAccent});

  final Color onAccent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: onAccent.withValues(alpha: 0.16),
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.open_in_full_rounded, size: 14, color: onAccent),
    );
  }
}
