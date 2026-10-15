import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/motion.dart';
import '../config/theme.dart';

/// Vertical bars, rounded at the top. The bar at [highlight] (the peak by
/// default) is the primary blue, fading violet→blue in dark. Other days use
/// `barIdle`, and zero days show as a flat `barEmpty` stub so the week still
/// reads as seven days. Dark adds dashed vertical grid lines. [labels] are the
/// x-axis captions.
class GradientBars extends StatelessWidget {
  const GradientBars({
    super.key,
    required this.values,
    required this.labels,
    this.highlight,
    this.height = 180,
  });

  final List<double> values;
  final List<String> labels;
  final int? highlight;
  final double height;

  static const _labelSpace = 30.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = theme.extension<AppColors>()!;
    final isDark = theme.brightness == Brightness.dark;
    final maxVal = values.isEmpty
        ? 1.0
        : values.reduce((a, b) => a > b ? a : b);
    final maxY = maxVal <= 0 ? 1.0 : maxVal * 1.2;
    // A zero day draws as a short stub rather than nothing.
    final stub = maxY * 0.025;
    final peak =
        highlight ??
        (values.isEmpty
            ? 0
            : values.indexOf(values.reduce((a, b) => a > b ? a : b)));

    final chart = BarChart(
      duration: AppMotion.reduced(context) ? Duration.zero : AppMotion.medium,
      curve: AppMotion.easeOut,
      BarChartData(
        maxY: maxY,
        alignment: BarChartAlignment.spaceAround,
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: false),
        // Tap a bar to read its value. The tooltip uses the inverse-surface
        // pair so the figure stays high-contrast in either theme. It reads the
        // real value, not the rod height (a zero day's rod is a stub).
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => scheme.inverseSurface,
            tooltipBorderRadius: BorderRadius.circular(8),
            tooltipPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 6,
            ),
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                BarTooltipItem(
                  NumberFormat.decimalPattern().format(values[groupIndex]),
                  TextStyle(
                    color: scheme.onInverseSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: _labelSpace,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= labels.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    labels[i],
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < values.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: values[i] > 0 ? values[i] : stub,
                  width: 26,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(10),
                    bottom: Radius.circular(3),
                  ),
                  gradient: i == peak && values[i] > 0 && isDark
                      ? LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [colors.violet, scheme.primary],
                        )
                      : null,
                  color: values[i] <= 0
                      ? colors.barEmpty
                      : i == peak
                      ? (isDark ? null : scheme.primary)
                      : colors.barIdle,
                ),
              ],
            ),
        ],
      ),
    );

    return SizedBox(
      height: height,
      child: isDark
          ? Stack(
              children: [
                Positioned.fill(
                  bottom: _labelSpace,
                  child: CustomPaint(
                    painter: _DashedColumnsPainter(
                      count: values.length,
                      color: colors.gridLine,
                    ),
                  ),
                ),
                chart,
              ],
            )
          : chart,
    );
  }
}

/// Dashed vertical lines at each bar's centre (bars are spaced evenly, so the
/// centres sit at (i + ½) / n of the width), plus a solid baseline.
class _DashedColumnsPainter extends CustomPainter {
  const _DashedColumnsPainter({required this.count, required this.color});

  final int count;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (count == 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var i = 0; i < count; i++) {
      final x = size.width * (i + 0.5) / count;
      for (var y = 0.0; y < size.height; y += 7) {
        canvas.drawLine(Offset(x, y), Offset(x, y + 3), paint);
      }
    }
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(_DashedColumnsPainter old) =>
      old.count != count || old.color != color;
}
