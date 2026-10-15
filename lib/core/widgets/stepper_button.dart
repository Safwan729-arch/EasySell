import 'package:flutter/material.dart';

import '../config/theme.dart';

/// The − / + of a quantity stepper: a 48 dp outlined circle (design §8,
/// "Confirm sheet with stepper"). An [IconButton] underneath, so disabled
/// states and tap feedback come for free.
class StepperButton extends StatelessWidget {
  const StepperButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 48,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final isDark = theme.brightness == Brightness.dark;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        fixedSize: Size.square(size),
        minimumSize: Size.square(size),
        padding: EdgeInsets.zero,
        iconSize: 24,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: isDark ? theme.colorScheme.onSurface : colors.link,
        disabledForegroundColor: colors.textDim,
        backgroundColor: isDark ? colors.iconButton : colors.muted,
        disabledBackgroundColor: (isDark ? colors.iconButton : colors.muted)
            .withValues(alpha: 0.5),
        shape: CircleBorder(side: BorderSide(color: colors.glowBorder)),
      ),
    );
  }
}
