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

/// Bottom navigation with evenly spaced, always-labelled destinations.
///
/// Light: a floating white bar, all corners rounded, inset from the screen
/// edges. The active tab gets a pale blue highlight behind the icon, a blue
/// label and a small dot. Dark: a docked bar with only the top corners rounded
/// and a glowing top edge. The active tab is simply blue.
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final row = SizedBox(
      height: 68,
      child: Row(
        children: [
          for (final item in items)
            Expanded(
              child: _NavButton(
                item: item,
                selected: item.branchIndex == currentIndex,
                activeColor: colors.link,
                inactiveColor: colors.onNavBar,
                highlight: isDark ? null : colors.chipBlue,
                onTap: () => onTap(item.branchIndex),
              ),
            ),
        ],
      ),
    );

    if (isDark) {
      return Container(
        decoration: BoxDecoration(
          color: colors.navBar,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(top: BorderSide(color: colors.glowBorder)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x2E3C6EFF),
              blurRadius: 18,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(top: false, child: row),
      );
    }

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.navBar,
            borderRadius: BorderRadius.circular(26),
            boxShadow: colors.cardShadow,
          ),
          child: row,
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
    required this.highlight,
    required this.onTap,
  });

  final AppNavItem item;
  final bool selected;
  final Color activeColor;
  final Color inactiveColor;

  /// Pale pill behind the active icon (light only); null hides it and the dot.
  final Color? highlight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? activeColor : inactiveColor;
    final duration = AppMotion.reduced(context)
        ? Duration.zero
        : AppMotion.fast;
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
            AnimatedContainer(
              duration: duration,
              curve: AppMotion.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
              decoration: BoxDecoration(
                color: selected && highlight != null
                    ? highlight
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
              // Ease the icon tint between active/inactive so it tracks the
              // body fade-through rather than snapping a frame ahead of it.
              child: TweenAnimationBuilder<Color?>(
                duration: duration,
                curve: AppMotion.easeOut,
                tween: ColorTween(end: color),
                builder: (context, value, _) =>
                    Icon(item.icon, color: value, size: 24),
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: duration,
              curve: AppMotion.easeOut,
              style: TextStyle(
                color: color,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 12,
              ),
              child: Text(item.label, maxLines: 1),
            ),
            if (highlight != null)
              AnimatedOpacity(
                duration: duration,
                opacity: selected ? 1 : 0,
                child: Container(
                  margin: const EdgeInsets.only(top: 3),
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: activeColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
