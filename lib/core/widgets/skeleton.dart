import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../config/motion.dart';

/// A shimmering placeholder block. Skeletons preserve layout while data loads,
/// which prevents the jarring spinner-then-content jump and makes loads *feel*
/// faster than a blocking spinner. Honours reduced-motion by rendering a calm,
/// static muted block.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.width, this.height = 16, this.radius = 8});

  final double? width;
  final double height;
  final double radius;

  /// Convenience for a full-width card-shaped placeholder.
  const Skeleton.card({super.key, this.height = 96, this.radius = 20})
    : width = double.infinity;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final base = colors.muted;
    final highlight = Color.alphaBlend(
      Colors.white.withValues(alpha: 0.45),
      base,
    );
    final radius = BorderRadius.circular(widget.radius);

    if (AppMotion.reduced(context)) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(color: base, borderRadius: radius),
      );
    }

    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value * 2 - 1; // -1 → 1
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment(-1 - t, 0),
              end: Alignment(1 - t, 0),
              colors: [base, highlight, base],
              stops: const [0.35, 0.5, 0.65],
            ),
          ),
        );
      },
    );
  }
}
