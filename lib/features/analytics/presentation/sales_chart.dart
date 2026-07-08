import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/config/motion.dart';
import '../domain/analytics.dart';

/// Minimal revenue area line for the dashboard "Overall sales" card.
class RevenueSparkline extends StatelessWidget {
  const RevenueSparkline({super.key, required this.points, this.height = 60});

  final List<SalesPoint> points;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (points.isEmpty) return SizedBox(height: height);

    return SizedBox(
      height: height,
      child: LineChart(
        duration: AppMotion.reduced(context) ? Duration.zero : AppMotion.medium,
        curve: AppMotion.easeOut,
        LineChartData(
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < points.length; i++)
                  FlSpot(i.toDouble(), points[i].revenue),
              ],
              isCurved: true,
              color: scheme.primary,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: scheme.primary.withValues(alpha: 0.15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
