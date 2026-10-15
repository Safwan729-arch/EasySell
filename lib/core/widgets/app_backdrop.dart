import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/theme.dart';

/// The screen canvas behind a page: the solid background plus soft colour in
/// the corners. Light: a lavender blur top-right and a sky-blue blur
/// bottom-left. Dark: a blue glow top-right, a faint violet glow bottom-left
/// and fine wave lines in the top-right corner.
///
/// Scaffolds are transparent (see [AppTheme]), so every route wraps its page in
/// one of these. It sits *inside* the page rather than behind the navigator so
/// each page stays opaque and a page transition never shows one page through
/// another.
class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ColoredBox(
      color: colors.background,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            // Static decoration: its own layer, so scrolling the page above it
            // never repaints it.
            child: RepaintBoundary(
              child: CustomPaint(painter: _BackdropPainter(isDark: isDark)),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Decorative wave lines for the top-right corner of a sheet or dialog in dark
/// mode. Renders nothing in light mode. Place it in a [Stack] behind content;
/// it ignores pointers.
class WaveLines extends StatelessWidget {
  const WaveLines({super.key, this.height = 160});

  final double height;

  @override
  Widget build(BuildContext context) {
    if (Theme.of(context).brightness != Brightness.dark) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: const RepaintBoundary(
          child: CustomPaint(painter: _WavePainter()),
        ),
      ),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  const _BackdropPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide * 0.95;
    if (isDark) {
      _glow(canvas, Offset(size.width, 0), r, const Color(0x473861FF));
      _glow(canvas, Offset(0, size.height), r, const Color(0x1F7B4DFA));
      _WavePainter.paintWaves(
        canvas,
        Size(size.width, math.min(220.0, size.height)),
      );
    } else {
      _glow(canvas, Offset(size.width, 0), r, const Color(0x38A78BFA));
      _glow(canvas, Offset(0, size.height), r, const Color(0x2E60A5FA));
    }
  }

  static void _glow(Canvas canvas, Offset center, double radius, Color color) {
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [color, color.withValues(alpha: 0)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(_BackdropPainter old) => old.isDark != isDark;
}

class _WavePainter extends CustomPainter {
  const _WavePainter();

  @override
  void paint(Canvas canvas, Size size) => paintWaves(canvas, size);

  /// About 13 thin contour lines flowing across the right ~60% of [size],
  /// fading out toward the left so they read as a corner motif.
  static void paintWaves(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final left = size.width * 0.38;
    final bounds = Rect.fromLTRB(left, 0, size.width, size.height);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = const LinearGradient(
        begin: Alignment.centerRight,
        end: Alignment.centerLeft,
        colors: [Color(0x8C5B8CFF), Color(0x595B8CFF), Color(0x005B8CFF)],
        stops: [0, 0.55, 1],
      ).createShader(bounds);

    const lines = 13;
    final w = bounds.width;
    for (var i = 0; i < lines; i++) {
      final y = size.height * 0.10 + i * (size.height * 0.055);
      final amp = size.height * (0.10 + i * 0.006);
      final path = Path()..moveTo(left, y + amp * 0.6);
      path.cubicTo(
        left + w * 0.30,
        y - amp,
        left + w * 0.55,
        y + amp * 1.2,
        size.width,
        y - amp * 0.4,
      );
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => false;
}
