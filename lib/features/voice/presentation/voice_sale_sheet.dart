import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/motion.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../l10n/app_localizations.dart';
import 'voice_controller.dart';
import 'voice_review_sheet.dart';

/// Presents [VoiceSaleSheet] as a modal bottom sheet -- mirrors the other
/// `show*Sheet` entry points (`showAddToCartSheet`, `showVoiceReviewSheet`).
/// A live recognizer must never keep listening once the sheet is gone, so
/// dismissal by ANY route -- swipe, back button, or the phase reaching
/// `reviewing` and the review sheet popping itself -- always resets the
/// controller via `whenComplete` (harmless if already reset: [VoiceController.reset]
/// is idempotent).
Future<void> showVoiceSaleSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (_) => const VoiceSaleSheet(),
  ).whenComplete(() => ref.read(voiceControllerProvider.notifier).reset());
}

/// Hosts the whole voice-sale flow in one bottom sheet, switching on
/// [VoiceSaleState.phase]: mic idle, live-listening transcript, a thinking
/// placeholder while `parse-sale` runs, the review step (delegates entirely to
/// [VoiceReviewSheet], which closes the sheet itself once a sale is added),
/// and an error state with retry. This widget only renders whatever
/// [voiceControllerProvider] currently says -- [showVoiceSaleSheet] owns
/// resetting the controller when the sheet goes away.
class VoiceSaleSheet extends ConsumerWidget {
  const VoiceSaleSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(voiceControllerProvider);
    final notifier = ref.read(voiceControllerProvider.notifier);

    return switch (state.phase) {
      VoicePhase.idle => _IdlePane(onStart: notifier.startListening),
      VoicePhase.listening => _ListeningPane(
        transcript: state.liveTranscript,
        onStop: notifier.stopAndParse,
      ),
      VoicePhase.thinking => const _ThinkingPane(),
      VoicePhase.reviewing => const VoiceReviewSheet(),
      VoicePhase.error => _ErrorPane(
        errorKey: state.errorMessage,
        onRetry: notifier.reset,
      ),
    };
  }
}

/// Shared padding for every non-review pane -- matches `VoiceReviewSheet`'s and
/// `_AddToCartSheet`'s bottom-sheet insets so the mic sheet's phases don't
/// visually jump against the review step that follows them.
class _PanePadding extends StatelessWidget {
  const _PanePadding({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [child]),
    );
  }
}

/// A large circular icon button -- the mic to start listening, or (in its
/// error-colored form) the stop button while listening. No tooltip, matching
/// this feature's own icon-only convention (see `_NotFoundRow`'s close
/// button in `voice_review_sheet.dart`).
class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.onPressed,
    required this.color,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final onColor = Theme.of(context).colorScheme.onPrimary;
    return SizedBox(
      width: 96,
      height: 96,
      child: IconButton.filled(
        onPressed: onPressed,
        icon: Icon(icon, size: 40),
        style: IconButton.styleFrom(
          backgroundColor: color,
          foregroundColor: onColor,
          shape: const CircleBorder(),
        ),
      ),
    );
  }
}

class _IdlePane extends StatelessWidget {
  const _IdlePane({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return _PanePadding(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RoundIconButton(
            icon: Icons.mic,
            onPressed: onStart,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 20),
          Text(
            l10n.voice_hintIdle,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

class _ListeningPane extends StatelessWidget {
  const _ListeningPane({required this.transcript, required this.onStop});

  final String transcript;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return _PanePadding(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _PulsingMic(),
          const SizedBox(height: 20),
          Text(l10n.voice_recording, style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          // Grows live as partial results land -- see VoiceController.startListening.
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Text(
              transcript,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 24),
          _RoundIconButton(
            icon: Icons.stop,
            onPressed: onStop,
            color: theme.colorScheme.error,
          ),
        ],
      ),
    );
  }
}

/// A softly pulsing mic glyph -- purely decorative feedback that the phone is
/// listening (the actual stop action lives in its own button below). Honours
/// reduced motion by rendering the same glyph static, per `AppMotion.reduced`
/// (the same idiom `Skeleton` uses).
class _PulsingMic extends StatefulWidget {
  const _PulsingMic();

  @override
  State<_PulsingMic> createState() => _PulsingMicState();
}

class _PulsingMicState extends State<_PulsingMic>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final core = SizedBox(
      width: 96,
      height: 96,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: theme.colorScheme.primary,
        ),
        child: Icon(Icons.mic, size: 40, color: theme.colorScheme.onPrimary),
      ),
    );

    if (AppMotion.reduced(context)) return core;

    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) =>
          Transform.scale(scale: 1 + _c.value * 0.12, child: child),
      child: core,
    );
  }
}

class _ThinkingPane extends StatelessWidget {
  const _ThinkingPane();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return _PanePadding(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.voice_thinking, style: theme.textTheme.titleMedium),
          const SizedBox(height: 20),
          const Skeleton.card(height: 56),
          const SizedBox(height: 12),
          const Skeleton.card(height: 56),
        ],
      ),
    );
  }
}

class _ErrorPane extends StatelessWidget {
  const _ErrorPane({required this.errorKey, required this.onRetry});

  final String? errorKey;
  final VoidCallback onRetry;

  /// Maps the controller's magic error keys to localized copy. Anything else
  /// is a repository `Failure.message`, already user-friendly, and is shown
  /// as-is.
  String _message(AppLocalizations l10n) => switch (errorKey) {
    'micDenied' => l10n.voice_errMicDenied,
    'noSpeech' => l10n.voice_errNoSpeech,
    'noMatch' => l10n.voice_errNoMatch,
    final other? => other,
    null => l10n.voice_errNoMatch,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return _PanePadding(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
          const SizedBox(height: 12),
          Text(
            _message(l10n),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          FilledButton.tonal(onPressed: onRetry, child: Text(l10n.voice_retry)),
        ],
      ),
    );
  }
}
