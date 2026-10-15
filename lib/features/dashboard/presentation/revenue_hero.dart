import 'package:flutter/material.dart';

import '../../../core/config/theme.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../shared/extensions/format.dart';

/// The dashboard's primary card: the hero gradient, leading with period
/// revenue and folding profit, margin and units into one glance. Money figures
/// are compact-formatted ([Money.compact]) and every value auto-shrinks via
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

  static const _radius = 24.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final isDark = theme.brightness == Brightness.dark;
    final onAccent = colors.heroOnAccent;
    // Secondary text on the hero (#DCE6FF): labels, the period line.
    const soft = Color(0xFFDCE6FF);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: colors.heroGradient,
        borderRadius: BorderRadius.circular(_radius),
        border: isDark ? Border.all(color: const Color(0x995B8CFF)) : null,
        boxShadow: colors.heroGlow,
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(_radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              // The faint lighter wave in the top-right corner.
              const Positioned(
                top: 0,
                right: 0,
                width: 220,
                height: 120,
                child: IgnorePointer(
                  child: CustomPaint(painter: _HeroWavePainter()),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            context.l10n.dashboard_revenuePeriod(periodWord),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontSize: 15,
                              color: soft,
                            ),
                          ),
                        ),
                        _ExpandButton(onAccent: onAccent),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          Money.compact(revenue, currencyCode: currency),
                          maxLines: 1,
                          style: theme.textTheme.displaySmall?.copyWith(
                            fontSize: 46,
                            letterSpacing: -1,
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
                        suffix: showDeltaSuffix
                            ? context.l10n.dashboard_vsYesterday
                            : null,
                        onAccent: onAccent,
                      ),
                    ],
                    const SizedBox(height: 16),
                    Divider(height: 1, color: onAccent.withValues(alpha: 0.18)),
                    const SizedBox(height: 14),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _HeroStat(
                            label: context.l10n.dashboard_profit,
                            value: Money.compact(
                              profit,
                              currencyCode: currency,
                            ),
                            onAccent: onAccent,
                            soft: soft,
                          ),
                          _StatDivider(color: onAccent),
                          _HeroStat(
                            label: context.l10n.dashboard_margin,
                            value: Pct.format(marginPercent),
                            onAccent: onAccent,
                            soft: soft,
                          ),
                          _StatDivider(color: onAccent),
                          _HeroStat(
                            label: context.l10n.dashboard_itemsSold,
                            value: Money.compactCount(unitsSold),
                            onAccent: onAccent,
                            soft: soft,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Thin vertical rule between hero stats.
class _StatDivider extends StatelessWidget {
  const _StatDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      child: VerticalDivider(
        width: 1,
        thickness: 1,
        color: color.withValues(alpha: 0.28),
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
    required this.soft,
  });

  final String label;
  final String value;
  final Color onAccent;
  final Color soft;

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
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 15,
              color: soft,
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
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 22,
                  color: onAccent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Translucent delta pill on the hero, e.g. "↗ 12% vs yesterday". The arrow
/// follows the sign of the change.
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
    final num = Pct.format(percent.abs());
    final text = suffix == null ? num : '$num $suffix';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: onAccent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: onAccent.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
            size: 18,
            // Mint up / rose down, both readable on the blue hero.
            color: up ? const Color(0xFF7CF2C8) : const Color(0xFFFFB3C0),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: theme.textTheme.labelLarge?.copyWith(
              fontSize: 15,
              color: onAccent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// The round outlined "⤢" button signalling the hero opens exact figures.
class _ExpandButton extends StatelessWidget {
  const _ExpandButton({required this.onAccent});

  final Color onAccent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: onAccent.withValues(alpha: 0.10),
        shape: BoxShape.circle,
        border: Border.all(color: onAccent.withValues(alpha: 0.55), width: 1.2),
      ),
      child: Icon(Icons.open_in_full_rounded, size: 18, color: onAccent),
    );
  }
}

/// A soft, lighter wave across the hero's top-right corner.
class _HeroWavePainter extends CustomPainter {
  const _HeroWavePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height * 0.85)
      ..cubicTo(
        size.width * 0.70,
        size.height * 0.35,
        size.width * 0.40,
        size.height * 0.95,
        0,
        size.height * 0.30,
      )
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0x1FFFFFFF), Color(0x00FFFFFF)],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_HeroWavePainter old) => false;
}
