import 'package:flutter/material.dart';

import '../config/theme.dart';

/// A card with the design language's exact depth: a soft blue-tinted shadow and
/// no border in light; a 1 px glowing outline and faint glow in dark. Radius 22.
///
/// Prefer this over [Card] where the card is a page's main surface; [Card]'s
/// Material elevation can only approximate the light-mode shadow.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
    this.color,
    this.radius = 22,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final content = Padding(padding: padding, child: child);
    return DecoratedBox(
      decoration: colors.card(context, radius: radius, color: color),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: onTap == null ? content : InkWell(onTap: onTap, child: content),
      ),
    );
  }
}
