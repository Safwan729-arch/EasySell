import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/motion.dart';
import '../../../core/l10n/l10n_ext.dart';
import 'voice_controller.dart';
import 'voice_sale_sheet.dart';

/// The standing handle on a voice sale whose sheet is not on screen.
///
/// Shows for the sale's whole life, not just its final moment. It used to
/// appear only once parsing had finished, which left a dead zone: dismiss the
/// sheet and the sale became invisible until the result landed. Nothing said
/// work was in progress, so it could not be watched, reopened, or cancelled --
/// and tapping the mic again would quietly supersede it, losing a sale the
/// shopkeeper had already spoken. Covering the pending phase is what closes
/// that hole; being able to reopen is almost a side effect.
///
/// Renders zero height when no backgrounded sale exists, so it costs nothing in
/// the common case. Sits above the routed screen alongside `OfflineBanner` so it
/// survives navigating away from wherever the sale was started, and is
/// deliberately persistent rather than a snackbar: a shopkeeper mid-transaction
/// may not look up for half a minute, and a timed-out snackbar would lose the
/// result with no trace.
class VoiceReadyBanner extends ConsumerWidget {
  const VoiceReadyBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showing = ref.watch(
      voiceControllerProvider.select((s) => s.hasBackgroundSale),
    );
    final pending = ref.watch(
      voiceControllerProvider.select((s) => s.isBackgroundPending),
    );
    final failed = ref.watch(
      voiceControllerProvider.select((s) => s.phase == VoicePhase.error),
    );

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;

    // Three states, one bar. Still working reads as neutral/in-progress; a
    // finished cart as good news; a failure as something needing attention --
    // it still has to be claimed (the error pane is where "type it instead"
    // lives) but must not be dressed up as success.
    final (background, foreground) = switch ((pending, failed)) {
      (true, _) => (scheme.surfaceContainerHighest, scheme.onSurface),
      (false, true) => (scheme.errorContainer, scheme.onErrorContainer),
      (false, false) => (scheme.primaryContainer, scheme.onPrimaryContainer),
    };

    final label = pending
        ? l10n.voice_bannerWorking
        : failed
        ? l10n.voice_bannerFailed
        : l10n.voice_bannerReady;

    return AnimatedSwitcher(
      duration: AppMotion.fast,
      switchInCurve: AppMotion.easeOut,
      switchOutCurve: AppMotion.easeOut,
      transitionBuilder: (child, animation) => SizeTransition(
        sizeFactor: animation,
        alignment: Alignment.topLeft,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: !showing
          ? const SizedBox.shrink()
          : Material(
              key: const ValueKey('voice-ready-banner'),
              color: background,
              child: InkWell(
                onTap: () => showVoiceSaleSheet(context, ref),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                    child: Row(
                      children: [
                        _BannerLeading(pending: pending, failed: failed),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            label,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: foreground,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (pending)
                          // Abandoning a sale in progress has to be a deliberate
                          // act with a button behind it. Without this the only
                          // way to drop a misspoken sale was to tap the mic
                          // again and have it discarded as a side effect --
                          // which is exactly the silent data loss this banner
                          // exists to prevent.
                          IconButton(
                            onPressed: () => ref
                                .read(voiceControllerProvider.notifier)
                                .reset(),
                            icon: const Icon(Icons.close_rounded, size: 18),
                            color: foreground,
                            visualDensity: VisualDensity.compact,
                            tooltip: l10n.voice_bannerCancel,
                          )
                        else ...[
                          Text(
                            l10n.voice_bannerAction,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: foreground,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: foreground,
                          ),
                          const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

/// The bar's status glyph: a live spinner while parsing continues, otherwise
/// the outcome. The spinner is the part that makes "something is happening"
/// legible at a glance, without the shopkeeper having to read anything.
class _BannerLeading extends StatelessWidget {
  const _BannerLeading({required this.pending, required this.failed});

  final bool pending;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!pending) {
      return Icon(
        failed ? Icons.error_outline : Icons.shopping_cart_checkout_rounded,
        size: 18,
        color: failed ? scheme.onErrorContainer : scheme.onPrimaryContainer,
      );
    }
    // Reduced motion: a spinner is the only moving thing here, so fall back to
    // a static glyph rather than leaving the row empty.
    if (AppMotion.reduced(context)) {
      return Icon(Icons.hourglass_top_rounded, size: 18, color: scheme.primary);
    }
    return SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2.5, color: scheme.primary),
    );
  }
}
