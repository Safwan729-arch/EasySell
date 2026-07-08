import 'package:flutter/material.dart';

import '../config/theme.dart';

/// A glowing circular progress ring around a center icon — the Kalo "streak"
/// element. [progress] is 0..1; the ring glows with the accent.
class StreakRing extends StatelessWidget {
  const StreakRing({
    super.key,
    required this.progress,
    this.icon = Icons.local_fire_department_rounded,
    this.size = 64,
  });

  final double progress;
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final appColors = Theme.of(context).extension<AppColors>()!;
    final glow = appColors.warning;
    // Subtle, theme-aware track behind the progress arc.
    final track = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.12);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: glow.withValues(alpha: 0.5), blurRadius: 16),
              ],
            ),
          ),
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              strokeWidth: 4,
              backgroundColor: track,
              valueColor: AlwaysStoppedAnimation(glow),
            ),
          ),
          Icon(icon, color: glow, size: size * 0.4),
        ],
      ),
    );
  }
}
