import 'dart:async' show Timer;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/motion.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../l10n/app_localizations.dart';
import 'voice_controller.dart';
import 'voice_review_sheet.dart';
import 'voice_transcript_dialog.dart';

/// Presents [VoiceSaleSheet] as a modal bottom sheet -- mirrors the other
/// `show*Sheet` entry points (`showAddToCartSheet`, `showProductPickerSheet`).
/// A live recorder must never keep recording once the sheet is gone, so
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
/// [VoiceSaleState.phase]: mic idle, listening/recording, a thinking
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
        onStop: notifier.stopAndParse,
        deadline: state.listenDeadline,
      ),
      VoicePhase.thinking => const _ThinkingPane(),
      VoicePhase.reviewing => const VoiceReviewSheet(),
      VoicePhase.error => _ErrorPane(
        errorKey: state.errorMessage,
        // When audio was captured before the failure, retrying re-sends that
        // recording -- the shopkeeper already said the sale once. When it
        // wasn't, retry can only mean starting over.
        onRetry: state.canRetryAudio ? notifier.retryLastAudio : notifier.reset,
        onRecordAgain: state.canRetryAudio ? notifier.reset : null,
        // Retrying into the same noise repeats the same failure, so offer the
        // text path as a real way out. `context`/`ref` are available here, so
        // `_ErrorPane` stays a plain StatelessWidget.
        onTypeInstead: () =>
            showVoiceTranscriptDialog(context, ref, state.heardText ?? ''),
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
  const _ListeningPane({required this.onStop, this.deadline});

  final VoidCallback onStop;

  /// When the recording will auto-stop, or null before the cap is armed.
  final DateTime? deadline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return _PanePadding(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _MicLevelMeter(),
          const SizedBox(height: 20),
          Text(l10n.voice_recording, style: theme.textTheme.titleMedium),
          // Fixed height so the pane does not jump when the countdown appears.
          SizedBox(height: 24, child: _AutoStopCountdown(deadline: deadline)),
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

/// The live microphone level: a mic glyph that grows with what the phone is
/// actually hearing, over a row of bars.
///
/// This replaces a mic that pulsed on a fixed 900ms timer regardless of input.
/// That pulse was a fuel gauge welded to half-full -- it looked like feedback
/// while telling the shopkeeper nothing, so a phone that could not hear them at
/// all (pocket noise, hand over the mic, a metre too far away in a loud shop)
/// looked identical to one hearing them perfectly. Real bars let a person fix
/// the problem themselves, in the moment, which no amount of server-side
/// tuning can do for them.
///
/// Reduced motion suppresses the scale transform but keeps the bars: they are
/// information, not decoration.
class _MicLevelMeter extends ConsumerStatefulWidget {
  const _MicLevelMeter();

  @override
  ConsumerState<_MicLevelMeter> createState() => _MicLevelMeterState();
}

class _MicLevelMeterState extends ConsumerState<_MicLevelMeter> {
  static const _barCount = 12;

  /// Level below which the recording is treated as "nothing is reaching the
  /// mic" for the purpose of the hint. Well under normal speech, which peaks
  /// far higher even across a room.
  static const _inaudible = 0.08;

  /// Grace before nagging: people take a moment to start talking, and a hint
  /// that appears the instant recording begins is noise.
  static const _hintAfter = Duration(milliseconds: 2500);

  double _peak = 0;
  bool _hintDue = false;
  Timer? _hintTimer;

  @override
  void initState() {
    super.initState();
    // A one-shot timer, not a check on rebuild: when the level is a flat zero
    // the notifier emits no changes at all (Riverpod drops equal values), so
    // there would be no rebuild to notice the silence on.
    _hintTimer = Timer(_hintAfter, () {
      if (mounted) setState(() => _hintDue = true);
    });
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final level = ref.watch(micLevelProvider);
    if (level > _peak) _peak = level;

    final scheme = theme.colorScheme;
    final core = SizedBox(
      width: 96,
      height: 96,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.primary,
        ),
        child: Icon(Icons.mic, size: 40, color: scheme.onPrimary),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (AppMotion.reduced(context))
          core
        else
          // Same 1.0-1.12 range the old decorative pulse used, so the pane's
          // proportions are unchanged -- only what drives it is different.
          Transform.scale(scale: 1 + level * 0.12, child: core),
        const SizedBox(height: 16),
        Semantics(
          label: context.l10n.voice_levelLabel,
          value: '${(level * 100).round()}%',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < _barCount; i++)
                _LevelBar(lit: level * _barCount > i, scheme: scheme),
            ],
          ),
        ),
        if (_hintDue && _peak < _inaudible) ...[
          const SizedBox(height: 12),
          Text(
            context.l10n.voice_speakCloser,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
          ),
        ],
      ],
    );
  }
}

class _LevelBar extends StatelessWidget {
  const _LevelBar({required this.lit, required this.scheme});

  final bool lit;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        color: lit ? scheme.primary : scheme.surfaceContainerHighest,
      ),
    );
  }
}

/// Counts down the last few seconds before the recording auto-stops.
///
/// The cap exists so a clip can never grow unbounded, but it used to fire in
/// total silence -- mid-sentence, with no warning, like a phone call that hangs
/// up at fifteen seconds without a beep. Shows nothing until the recording is
/// within [autoStopWarning] of its deadline.
class _AutoStopCountdown extends StatefulWidget {
  const _AutoStopCountdown({required this.deadline});

  final DateTime? deadline;

  @override
  State<_AutoStopCountdown> createState() => _AutoStopCountdownState();
}

class _AutoStopCountdownState extends State<_AutoStopCountdown> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Sub-second so the number shown is never a whole second stale; setState is
    // cheap here because this widget's subtree is one Text.
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deadline = widget.deadline;
    if (deadline == null) return const SizedBox.shrink();

    // Must be the same clock the deadline was stamped from -- see
    // `VoiceController.startListening`.
    final remaining = deadline.difference(clock.now());
    if (remaining > autoStopWarning || remaining.isNegative) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    // Ceiling, so a recording with 0.4s left reads "1" rather than "0".
    final seconds = (remaining.inMilliseconds / 1000).ceil();
    return Center(
      child: Text(
        context.l10n.voice_stoppingIn(seconds),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
        ),
      ),
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
  const _ErrorPane({
    required this.errorKey,
    required this.onRetry,
    required this.onTypeInstead,
    this.onRecordAgain,
  });

  final String? errorKey;
  final VoidCallback onRetry;
  final VoidCallback onTypeInstead;

  /// Offered only when [onRetry] re-sends kept audio, as the way to discard it
  /// and speak again. Null when retry already means starting over.
  final VoidCallback? onRecordAgain;

  /// Maps the controller's magic error keys to localized copy. Anything else
  /// is a repository `Failure.message`, already user-friendly, and is shown
  /// as-is.
  String _message(AppLocalizations l10n) => switch (errorKey) {
    'micDenied' => l10n.voice_errMicDenied,
    'noSpeech' => l10n.voice_errNoSpeech,
    'noMatch' => l10n.voice_errNoMatch,
    'offline' => l10n.voice_errOffline,
    'tooQuiet' => l10n.voice_errTooQuiet,
    final other? => other,
    // Unreachable in practice -- every real transition to `error` sets a
    // non-null errorMessage (a magic key or a repository Failure.message).
    // Kept only so the switch stays exhaustive over String?; deliberately
    // returns the same copy as the 'noMatch' case above rather than implying
    // some distinct behavior.
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
          if (onRecordAgain case final recordAgain?) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: recordAgain,
              child: Text(l10n.voice_recordAgain),
            ),
          ],
          const SizedBox(height: 8),
          TextButton(
            onPressed: onTypeInstead,
            child: Text(l10n.voice_typeInstead),
          ),
        ],
      ),
    );
  }
}
