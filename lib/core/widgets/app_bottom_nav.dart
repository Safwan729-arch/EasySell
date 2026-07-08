import 'package:flutter/material.dart';

import '../config/motion.dart';
import '../config/theme.dart';

/// A single destination in [AppBottomNav]. [branchIndex] is the shell branch the
/// slot maps to.
class AppNavItem {
  const AppNavItem({
    required this.icon,
    required this.label,
    required this.branchIndex,
  });
  final IconData icon;
  final String label;
  final int branchIndex;
}

/// Full-width light bottom navigation bar: evenly-spaced labelled destinations
/// (icon + caption always visible). The active destination is tinted with the
/// brand color.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  /// The destinations, left to right.
  final List<AppNavItem> items;

  /// The currently selected shell branch index.
  final int currentIndex;

  /// Called with the [AppNavItem.branchIndex] of the tapped destination.
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colors.navBar,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (final item in items)
                Expanded(
                  child: _NavButton(
                    item: item,
                    selected: item.branchIndex == currentIndex,
                    activeColor: scheme.primary,
                    inactiveColor: colors.onNavBar,
                    onTap: () => onTap(item.branchIndex),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.activeColor,
    required this.inactiveColor,
    required this.onTap,
  });

  final AppNavItem item;
  final bool selected;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? activeColor : inactiveColor;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: InkResponse(
        onTap: onTap,
        radius: 36,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Ease the icon tint between active/inactive so it tracks the body
            // fade-through rather than snapping a frame ahead of it.
            TweenAnimationBuilder<Color?>(
              duration: AppMotion.fast,
              curve: AppMotion.easeOut,
              tween: ColorTween(end: color),
              builder: (context, value, _) =>
                  Icon(item.icon, color: value, size: 22),
            ),
            const SizedBox(height: 4),
            AnimatedDefaultTextStyle(
              duration: AppMotion.fast,
              curve: AppMotion.easeOut,
              style: TextStyle(
                color: color,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 11,
              ),
              child: Text(item.label),
            ),
          ],
        ),
      ),
    );
  }
}
