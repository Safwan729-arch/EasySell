import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/haptics.dart';
import '../../../core/config/motion.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/app_bottom_nav.dart';
import '../../../shared/providers/branch_scroll_provider.dart';
import '../../cart/presentation/cart_bar.dart';

/// Hosts the four primary destinations behind the bottom nav: Home, Items,
/// Reports and History. Auth, onboarding, product detail/forms and the settings
/// sub-pages render outside this shell (full screen, no bottom bar).
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell>
    with SingleTickerProviderStateMixin {
  // Drives the fade-through. Starts settled (value 1) so the first frame is
  // fully visible — the destination screens handle their own first-mount
  // entrance — and replays from 0 each time the active branch changes.
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: AppMotion.fast,
    value: 1,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _fade,
    curve: AppMotion.easeOut,
  );

  @override
  void didUpdateWidget(MainShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.navigationShell.currentIndex !=
        widget.navigationShell.currentIndex) {
      _fade.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  void _onTap(int branchIndex) {
    AppHaptics.tap();
    final reselected = branchIndex == widget.navigationShell.currentIndex;
    // Re-tapping the active tab scrolls its list back to the top (if it has
    // one) rather than doing nothing; tapping a different tab just switches.
    if (reselected) {
      final controller = ref.read(branchScrollControllerProvider(branchIndex));
      if (controller.hasClients) {
        controller.animateTo(
          0,
          duration: AppMotion.medium,
          curve: AppMotion.easeInOut,
        );
      }
    }
    widget.navigationShell.goBranch(branchIndex, initialLocation: reselected);
  }

  @override
  Widget build(BuildContext context) {
    // Fade-through between the four peer destinations. We keep a single copy of
    // navigationShell in the tree (its branches carry GlobalKeys, so the two
    // overlapping copies an AnimatedSwitcher would mount collide) and instead
    // fade/scale it in on each branch change: fast (180ms) and subtle — a
    // barely-there scale, never a directional slide (the tabs aren't spatially
    // ordered). Reduced-motion shows the shell with no transform.
    final l10n = context.l10n;
    // branchIndex maps to the StatefulShellRoute branch order in app_router.dart:
    // 0 Home · 1 Items · 2 Reports · 3 History.
    final items = [
      AppNavItem(
        icon: Icons.home_rounded,
        label: l10n.nav_home,
        branchIndex: 0,
      ),
      AppNavItem(
        icon: Icons.inventory_2_outlined,
        label: l10n.nav_items,
        branchIndex: 1,
      ),
      AppNavItem(
        icon: Icons.bar_chart_rounded,
        label: l10n.nav_reports,
        branchIndex: 2,
      ),
      AppNavItem(
        icon: Icons.access_time_rounded,
        label: l10n.nav_history,
        branchIndex: 3,
      ),
    ];
    final shell = widget.navigationShell;
    // One backdrop for all four tabs; their own scaffolds are transparent.
    return AppBackdrop(
      child: Scaffold(
        body: AppMotion.reduced(context)
            ? shell
            : FadeTransition(
                opacity: _curve,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.98, end: 1.0).animate(_curve),
                  child: shell,
                ),
              ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CartBar(),
            AppBottomNav(
              items: items,
              currentIndex: widget.navigationShell.currentIndex,
              onTap: _onTap,
            ),
          ],
        ),
      ),
    );
  }
}
