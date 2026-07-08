import 'package:flutter/material.dart';

import '../config/motion.dart';

/// Fade-and-rise entrance for a widget the first time it mounts. Pass [index]
/// to stagger siblings (each waits `index * stagger` before starting), which
/// makes lists and card grids cascade in instead of popping all at once.
///
/// Honours reduced-motion: when motion is disabled the child is shown
/// immediately with no transform.
class Entrance extends StatefulWidget {
  const Entrance({
    super.key,
    required this.child,
    this.index = 0,
    this.offset = 14,
    this.duration,
    this.delay = Duration.zero,
  });

  final Widget child;
  final int index;

  /// Vertical distance (logical px) the child rises from.
  final double offset;
  final Duration? duration;

  /// Extra delay applied before the per-index stagger.
  final Duration delay;

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration ?? AppMotion.medium,
  );

  @override
  void initState() {
    super.initState();
    final stagger = AppMotion.stagger * widget.index;
    Future<void>.delayed(widget.delay + stagger, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduced(context)) return widget.child;

    final curved = CurvedAnimation(parent: _c, curve: AppMotion.easeOut);
    return AnimatedBuilder(
      animation: curved,
      builder: (context, child) {
        final t = curved.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, widget.offset * (1 - t)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
