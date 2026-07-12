import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/providers/connectivity_provider.dart';
import '../config/motion.dart';

/// A slim, full-width bar that appears whenever the device is offline and
/// animates away when connectivity returns. Meant to sit at the top of the app,
/// above the routed content. Renders nothing (zero height) while online.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Fail open: only treat as offline once we have a concrete `false` reading.
    final isOnline = ref.watch(isOnlineProvider).value ?? true;
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return AnimatedSwitcher(
      duration: AppMotion.fast,
      switchInCurve: AppMotion.easeOut,
      switchOutCurve: AppMotion.easeOut,
      transitionBuilder: (child, animation) => SizeTransition(
        sizeFactor: animation,
        // Equivalent to the deprecated `axisAlignment: -1` for a vertical axis,
        // per SizeTransition's own migration guidance.
        alignment: Alignment.topLeft,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: isOnline
          ? const SizedBox.shrink()
          : Material(
              key: const ValueKey('offline-banner'),
              color: scheme.errorContainer,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.wifi_off_rounded,
                        size: 18,
                        color: scheme.onErrorContainer,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          l10n.common_noInternet,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: scheme.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
