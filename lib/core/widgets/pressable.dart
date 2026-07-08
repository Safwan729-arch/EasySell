import 'package:flutter/material.dart';

import '../config/haptics.dart';
import '../config/motion.dart';

/// Wraps any tappable surface so it scales down slightly while pressed, giving
/// instant physical feedback that the UI "heard" the tap. Subtle by design
/// (0.97) and honours reduced-motion. Use for cards, list rows and custom CTAs
/// where there is no Material ripple to lean on.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.97,
    this.borderRadius,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  /// When set, a Material ink ripple is clipped to this radius on top of the
  /// scale feedback.
  final BorderRadius? borderRadius;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap == null) return;
    if (v) AppHaptics.tap(); // light tick the instant the press lands
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);
    final pressed = _down && !reduced;

    return GestureDetector(
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: pressed ? widget.scale : 1.0,
        duration: pressed ? AppMotion.pressIn : AppMotion.exit,
        curve: AppMotion.easeOut,
        child: widget.child,
      ),
    );
  }
}
