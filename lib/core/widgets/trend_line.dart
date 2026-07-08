import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../config/motion.dart';

/// Smooth line with a faint area fill and a dot on the final point — the Kalo
/// "weight trend" style. [labels] caption the x-axis.
class TrendLine extends StatelessWidget {
  const TrendLine({
    super.key,
    required this.values,
    required this.labels,
    this.height = 160,
  });

  final List<double> values;
  final List<String> labels;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (values.isEmpty) return SizedBox(height: height);
    final lastIndex = values.length - 1;

    return SizedBox(
      height: height,
      child: LineChart(
        duration: AppMotion.reduced(context) ? Duration.zero : AppMotion.medium,
        curve: AppMotion.easeOut,
        LineChartData(
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
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
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < values.length; i++)
                  FlSpot(i.toDouble(), values[i]),
              ],
              isCurved: true,
              color: scheme.primary,
              barWidth: 3,
              dotData: FlDotData(
                show: true,
                checkToShowDot: (spot, _) => spot.x == lastIndex.toDouble(),
                getDotPainter: (spot, pct, bar, idx) => FlDotCirclePainter(
                  radius: 5,
                  color: scheme.primary,
                  // Ring the dot in the surface color so it reads as a clean
                  // cutout on whatever card it sits on (light or dark).
                  strokeColor: scheme.surface,
                  strokeWidth: 2,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    scheme.primary.withValues(alpha: 0.25),
                    scheme.primary.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
