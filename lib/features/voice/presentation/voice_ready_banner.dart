import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/motion.dart';
import '../../../core/l10n/l10n_ext.dart';
import 'voice_controller.dart';
import 'voice_sale_sheet.dart';

/// Announces a voice sale that finished parsing after its sheet was dismissed.
///
/// This is the visible half of backgrounding the parse. A shopkeeper who speaks
/// a sale and then closes the sheet to take the customer's money has nothing on
/// screen tracking that work; without this bar the finished cart would sit in
/// the controller unclaimed. Tapping reopens the sheet exactly where it left
/// off -- the review rows, or the error pane if the parse failed.
///
/// Renders nothing (zero height) unless there is genuinely a result waiting, so
/// it costs nothing in the overwhelmingly common case. Sits above the routed
/// screen alongside `OfflineBanner`, and is deliberately persistent rather than
/// a snackbar: a shopkeeper mid-transaction may not look up for half a minute,
/// and a result that timed out of a snackbar would be lost with no trace.
class VoiceReadyBanner extends ConsumerWidget {
  const VoiceReadyBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waiting = ref.watch(
      voiceControllerProvider.select((s) => s.hasBackgroundResult),
    );
    final failed = ref.watch(
      voiceControllerProvider.select((s) => s.phase == VoicePhase.error),
    );
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    // A failed background parse still needs claiming -- the error pane is where
    // "type it instead" lives -- but it must not be dressed up as good news.
    final background = failed ? scheme.errorContainer : scheme.primaryContainer;
    final foreground = failed
        ? scheme.onErrorContainer
        : scheme.onPrimaryContainer;

    return AnimatedSwitcher(
      duration: AppMotion.fast,
      switchInCurve: AppMotion.easeOut,
      switchOutCurve: AppMotion.easeOut,
      transitionBuilder: (child, animation) => SizeTransition(
        sizeFactor: animation,
        alignment: Alignment.topLeft,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: !waiting
          ? const SizedBox.shrink()
          : Material(
              key: const ValueKey('voice-ready-banner'),
              color: background,
              child: InkWell(
                onTap: () => showVoiceSaleSheet(context, ref, resume: true),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          failed
                              ? Icons.error_outline
                              : Icons.shopping_cart_checkout_rounded,
                          size: 18,
                          color: foreground,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            failed
                                ? l10n.voice_bannerFailed
                                : l10n.voice_bannerReady,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: foreground,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
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
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
