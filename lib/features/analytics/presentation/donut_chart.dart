import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/config/motion.dart';

/// One slice of the [DonutChart].
class DonutSlice {
  const DonutSlice({required this.color, required this.value});

  final Color color;
  final double value;
}

/// A donut (ring) chart for the Reports category split — each slice drawn in its
/// category color, with an open center for an overlaid label ([centerLabel] /
/// [centerSub]). Replaces the dashboard's progress-bar rows.
class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.slices,
    this.size = 132,
    this.centerLabel,
    this.centerSub,
  });

  final List<DonutSlice> slices;
  final double size;
  final String? centerLabel;
  final String? centerSub;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            duration: AppMotion.reduced(context)
                ? Duration.zero
                : AppMotion.medium,
            curve: AppMotion.easeOut,
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: size * 0.32,
              startDegreeOffset: -90,
              sections: [
                for (final s in slices)
                  PieChartSectionData(
                    value: s.value,
                    color: s.color,
                    radius: size * 0.16,
                    showTitle: false,
                  ),
              ],
            ),
          ),
          if (centerLabel != null)
            // Constrain to the open hole so the label never overflows the ring.
            SizedBox(
              width: size * 0.58,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    centerLabel!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (centerSub != null)
                    Text(
                      centerSub!,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
