import 'package:flutter/material.dart';

import '../config/theme.dart';

/// The decoration for anything selected or primary: the blue→violet gradient
/// in light, flat bright blue in dark, with a coloured glow under it.
/// Content on it uses [ColorScheme.onPrimary].
ShapeDecoration brandFillDecoration(
  BuildContext context, {
  ShapeBorder shape = const StadiumBorder(),
  bool glow = true,
}) {
  final colors = Theme.of(context).extension<AppColors>()!;
  return ShapeDecoration(
    shape: shape,
    gradient: colors.brandGradient,
    shadows: glow ? colors.primaryGlow : null,
  );
}

/// The decoration for an idle pill, chip or round button: a white surface on a
/// soft shadow in light, a `field` fill with a glowing outline in dark.
ShapeDecoration idleFillDecoration(
  BuildContext context, {
  ShapeBorder shape = const StadiumBorder(),
  Color? color,
}) {
  final colors = Theme.of(context).extension<AppColors>()!;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final side = isDark ? BorderSide(color: colors.glowBorder) : BorderSide.none;
  final fill =
      color ?? (isDark ? colors.field : Theme.of(context).colorScheme.surface);
  return ShapeDecoration(
    // A flat gradient rather than `color`: pills animate between this and
    // [brandFillDecoration], and a ShapeDecoration lerped from a color to a
    // gradient holds both mid-way, which ShapeDecoration asserts against.
    gradient: LinearGradient(colors: [fill, fill]),
    shape: switch (shape) {
      StadiumBorder() => StadiumBorder(side: side),
      CircleBorder() => CircleBorder(side: side),
      RoundedRectangleBorder(:final borderRadius) => RoundedRectangleBorder(
        borderRadius: borderRadius,
        side: side,
      ),
      _ => shape,
    },
    shadows: isDark ? null : colors.cardShadow,
  );
}

/// A round header button (48 dp by default): white with a soft shadow in
/// light, `iconButton` glass with a glowing outline in dark. Pass [primary]
/// for the brand fill (the "+" on Items in light mode).
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 48,
    this.iconSize = 22,
    this.primary = false,
    this.tinted = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final double iconSize;

  /// Brand fill in light mode (outlined glass in dark, per the mockups).
  final bool primary;

  /// Soft blue fill in light mode (Items' scan / mic buttons).
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final useBrand = primary && !isDark;
    final decoration = useBrand
        ? brandFillDecoration(context, shape: const CircleBorder())
        : idleFillDecoration(
            context,
            shape: const CircleBorder(),
            color: isDark
                ? colors.iconButton
                : (tinted ? colors.chipBlue : null),
          );
    final iconColor = useBrand
        ? scheme.onPrimary
        : (tinted || primary ? colors.link : scheme.onSurface);
    final button = Material(
      type: MaterialType.transparency,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox.square(
          dimension: size,
          child: Icon(icon, size: iconSize, color: iconColor),
        ),
      ),
    );
    final decorated = DecoratedBox(decoration: decoration, child: button);
    return Semantics(
      button: true,
      label: tooltip,
      child: tooltip == null
          ? decorated
          : Tooltip(message: tooltip!, child: decorated),
    );
  }
}
