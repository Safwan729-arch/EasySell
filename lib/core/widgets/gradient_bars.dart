import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/motion.dart';

/// Vertical bars. Normal bars are a muted, theme-aware gray; the bar at
/// [highlight] (the peak by default) is drawn in the brand color. [labels]
/// are the x-axis captions.
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Muted gray-blue rest bar, derived from the theme so it stays visible on
    // both the light and the dark card surfaces.
    final restBar = scheme.onSurfaceVariant.withValues(alpha: 0.28);
    final maxVal = values.isEmpty
        ? 1.0
        : values.reduce((a, b) => a > b ? a : b);
    final maxY = maxVal <= 0 ? 1.0 : maxVal * 1.2;
    final peak =
        highlight ??
        (values.isEmpty
            ? 0
            : values.indexOf(values.reduce((a, b) => a > b ? a : b)));

    return SizedBox(
      height: height,
      child: BarChart(
        duration: AppMotion.reduced(context) ? Duration.zero : AppMotion.medium,
        curve: AppMotion.easeOut,
        BarChartData(
          maxY: maxY,
          alignment: BarChartAlignment.spaceAround,
          borderData: FlBorderData(show: false),
          gridData: const FlGridData(show: false),
          // Tap a bar to read its value. The tooltip uses the inverse-surface
          // pair (dark-on-light in dark mode, light-on-dark in light mode) so
          // the figure stays high-contrast and legible in either theme.
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
                    NumberFormat.decimalPattern().format(rod.toY),
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
                reservedSize: 24,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= labels.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      labels[i],
                      style: Theme.of(context).textTheme.labelSmall,
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
                    toY: values[i],
                    width: 22,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(8),
                    ),
                    color: i == peak ? scheme.primary : restBar,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
