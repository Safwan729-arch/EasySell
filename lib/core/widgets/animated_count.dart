import 'package:flutter/material.dart';

import '../config/motion.dart';

/// Counts a numeric value up to [value] when it first appears (and tweens
/// between values on change), formatting each frame through [formatter]. Gives
/// stat cards a sense of "tallying" that makes the dashboard feel alive without
/// being noisy. Tabular figures in the theme keep the width steady mid-count.
///
/// Honours reduced-motion: the final, formatted value is rendered immediately.
class AnimatedCount extends StatelessWidget {
  const AnimatedCount({
    super.key,
    required this.value,
    required this.formatter,
    this.style,
    this.maxLines,
    this.overflow,
  });

  final double value;
  final String Function(double) formatter;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduced(context)) {
      return Text(
        formatter(value),
        style: style,
        maxLines: maxLines,
        overflow: overflow,
      );
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: AppMotion.count,
      curve: AppMotion.easeOut,
      builder: (context, v, _) => Text(
        formatter(v),
        style: style,
        maxLines: maxLines,
        overflow: overflow,
      ),
    );
  }
}
