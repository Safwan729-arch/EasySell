import 'dart:async' show StreamSubscription, Timer, unawaited;
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/result.dart';
import '../../../shared/providers/connectivity_provider.dart';
import '../../inventory/presentation/inventory_controller.dart';
import '../../scan/domain/scan_candidates.dart';
import '../../transactions/presentation/sales_providers.dart';
import '../data/audio_recorder.dart';
import '../data/voice_sale_repository.dart';
import '../domain/voice_decision.dart';
import '../domain/voice_level.dart';
import '../domain/voice_line.dart';
import '../domain/voice_parse_result.dart';

enum VoicePhase { idle, listening, thinking, reviewing, error }

/// State for the voice-sale flow: mic recording -> uploaded audio -> parsed ->
/// reviewable lines. Mirrors the vision-scan controller's shape, with the
/// ears swapped for a microphone.
class VoiceSaleState {
  const VoiceSaleState({
    this.phase = VoicePhase.idle,
    this.heardText,
    this.lines = const <VoiceLine>[],
    this.errorMessage,
    this.listenDeadline,
    this.canRetryAudio = false,
  });

  final VoicePhase phase;

  /// When the current recording will auto-stop, so the listening pane can warn
  /// before it happens instead of cutting the shopkeeper off mid-sentence. Null
  /// outside `listening`, and also for the brief window after `listening` is
  /// entered but before `recorder.start()` resolves -- there is no deadline to
  /// show until the timer that enforces it actually exists.
  final DateTime? listenDeadline;

  /// True in the `error` phase when the failure happened *after* audio was
  /// captured, so retrying can re-send that same recording instead of making
  /// the shopkeeper say the whole sale again. False for failures where nothing
  /// usable was recorded (mic denied, offline, silence).
  final bool canRetryAudio;

  /// The transcript the `parse-sale` function actually worked from (produced
  /// server-side from the recorded audio), echoed back so a mishear is
  /// obvious to the user.
  final String? heardText;

  final List<VoiceLine> lines;

  /// A magic string key (`micDenied` / `noSpeech` / `noMatch`) or a repository
  /// `Failure.message` -- the UI maps these to localized copy.
  final String? errorMessage;

  bool get canAdd => canAddToCart(lines);

  /// [errorMessage], [listenDeadline] and [canRetryAudio] are intentionally NOT
  /// defaulted to their current values: each describes one specific moment, so
  /// every transition must state it explicitly and a stale error, a deadline
  /// from a finished recording, or a retry offer for discarded audio can never
  /// leak into a later state.
  VoiceSaleState copyWith({
    VoicePhase? phase,
    String? heardText,
    List<VoiceLine>? lines,
    String? errorMessage,
    DateTime? listenDeadline,
    bool canRetryAudio = false,
  }) => VoiceSaleState(
    phase: phase ?? this.phase,
    heardText: heardText ?? this.heardText,
    lines: lines ?? this.lines,
    errorMessage: errorMessage,
    listenDeadline: listenDeadline,
    canRetryAudio: canRetryAudio,
  );
}

/// Orchestrates record -> stop -> `parse-sale` -> reviewable lines. Never
/// talks to Supabase directly (that's [VoiceSaleRepository]'s job) and never
/// builds widgets.
class VoiceController extends Notifier<VoiceSaleState> {
  /// Bumped by [startListening] and [reset] to invalidate any in-flight
  /// recording/parse from a previous session. Every `await` boundary in
  /// [startListening]/[stopAndParse] re-checks this before touching [state],
  /// so a result that resolves after the user moved on can never clobber
  /// fresh state.
  int _session = 0;

  /// Auto-stop for the current recording. NOT always cancelled before a
  /// transition out of `listening`: [startListening] sets `phase` to
  /// `listening` before `await recorder.start()`, and `_capTimer` is only
  /// armed after `start()` resolves. If the user taps Stop during that
  /// window, [stopAndParse] sees `phase == listening` and proceeds -- but
  /// there is no timer yet to cancel, and it does not bump [_session] (it's
  /// still the same session, just stopped early). When `start()` later
  /// resolves, [startListening] arms a fresh timer for a session that has
  /// already moved on. The `state.phase == VoicePhase.listening` guard in
  /// the timer callback is what actually stops that stale timer from firing
  /// a spurious second [stopAndParse] -- by the time it fires, the earlier
  /// stop will have already moved `phase` past `listening`. It is load-bearing,
  /// not redundant with the `_session` check above it.
  Timer? _capTimer;

  /// Loudness samples for the recording in progress, feeding both the level
  /// meter (via [micLevelProvider]) and [_detector]. Cancelled wherever
  /// [_capTimer] is.
  StreamSubscription<double>? _levelSub;

  /// Judges when the shopkeeper has finished speaking, so the recording can
  /// stop itself. Recreated per recording; null outside `listening`.
  SpeechEndDetector? _detector;

  /// The last captured recording, kept so a failure that happened *after*
  /// capture can be retried without re-recording. Cleared by [reset] and
  /// whenever a fresh recording starts.
  ({Uint8List bytes, String mime})? _lastRecording;

  @override
  VoiceSaleState build() {
    ref.onDispose(_stopWatchingLevels);
    ref.onDispose(() => _capTimer?.cancel());
    return const VoiceSaleState();
  }

  Future<void> startListening() async {
    final session = ++_session;
    _lastRecording = null;

    // Checked first, and synchronously: with no network nothing downstream can
    // possibly succeed, so recording 15 seconds of a shopkeeper's voice only to
    // then admit we were offline wastes their time and their breath.
    // [voiceOnlineProvider] fails open, so an unresolved connectivity reading
    // never blocks a sale.
    if (!ref.read(voiceOnlineProvider)) {
      state = state.copyWith(phase: VoicePhase.error, errorMessage: 'offline');
      return;
    }

    final recorder = ref.read(audioRecorderProvider);
    final ok = await recorder.hasPermission();
    if (_session != session) return; // superseded while awaiting permission

    if (!ok) {
      state = state.copyWith(
        phase: VoicePhase.error,
        errorMessage: 'micDenied',
      );
      return;
    }

    // Warms the recent-sales hint during the seconds the shopkeeper spends
    // speaking, so [stopAndParse] can read whatever arrived without ever
    // waiting on it. Not autoDispose, so a plain read keeps the result.
    ref.read(recentUnitsSoldProvider);

    state = state.copyWith(phase: VoicePhase.listening);
    try {
      await recorder.start();
    } catch (_) {
      // The `record` plugin throws readily (mic held by another app, encoder
      // failure); nothing was captured, so this is the same user-facing
      // outcome as "no speech" -- and it's truthful, since nothing was heard.
      unawaited(recorder.cancel());
      if (_session != session) return; // superseded while awaiting start()
      state = state.copyWith(phase: VoicePhase.error, errorMessage: 'noSpeech');
      return;
    }
    if (_session != session) return; // superseded while awaiting start()

    // Only once recording is genuinely live: a buzz for a mic that failed to
    // open would be a lie the shopkeeper feels before they read the error.
    ref.read(voiceHapticsProvider).recordingStarted();

    final cap = ref.read(maxRecordingDurationProvider);
    _capTimer?.cancel();
    _capTimer = Timer(cap, () {
      // Both guards matter: the session may have moved on, and the user may
      // have already stopped manually.
      if (_session == session && state.phase == VoicePhase.listening) {
        unawaited(stopAndParse());
      }
    });
    _watchLevels(session);
    state = state.copyWith(
      phase: VoicePhase.listening,
      // `clock.now()`, not `DateTime.now()`: identical in production, but under
      // fake_async it advances with the same virtual time as the cap Timer, so
      // the countdown this feeds is testable without a real 15-second wait.
      listenDeadline: clock.now().add(cap),
    );
  }

  /// Subscribes to the recorder's loudness samples for [session]: publishes
  /// them for the meter and feeds the silence detector, stopping the recording
  /// once a sentence has clearly finished.
  void _watchLevels(int session) {
    _stopWatchingLevels();
    // A level left over from the previous recording must not flash in the meter
    // before the first fresh sample arrives.
    ref.read(micLevelProvider.notifier).clear();
    final detector = SpeechEndDetector();
    _detector = detector;
    _levelSub = ref.read(audioRecorderProvider).levels.listen(
      (dbfs) {
        if (_session != session || state.phase != VoicePhase.listening) return;
        ref.read(micLevelProvider.notifier).report(dbfs);
        if (!ref.read(autoStopOnSilenceProvider)) return;
        if (detector.add(dbfs) == SpeechPhase.ended) {
          unawaited(stopAndParse());
        }
      },
      // A recorder that fails mid-stream must not take the sale down with it;
      // losing the meter and the auto-stop leaves the duration cap in charge,
      // which is exactly the behaviour before any of this existed.
      onError: (_) {},
    );
  }

  void _stopWatchingLevels() {
    _levelSub?.cancel();
    _levelSub = null;
    _detector = null;
  }

  Future<void> stopAndParse() async {
    // Guards double-tap and stop-before-start.
    if (state.phase != VoicePhase.listening) return;
    _capTimer?.cancel();
    _capTimer = null;
    final detector = _detector;
    _stopWatchingLevels();
    final session = _session;

    ref.read(voiceHapticsProvider).recordingStopped();

    final recorder = ref.read(audioRecorderProvider);
    ({Uint8List bytes, String mime})? recording;
    try {
      recording = await recorder.stop();
    } catch (_) {
      // Same reasoning as the start() catch above: a stop() throw means
      // nothing usable was captured, so it's a "no speech" outcome, not a
      // crash. No parse call happens.
      if (_session != session) return;
      state = state.copyWith(phase: VoicePhase.error, errorMessage: 'noSpeech');
      return;
    }
    if (_session != session) return;

    if (recording == null) {
      state = state.copyWith(phase: VoicePhase.error, errorMessage: 'noSpeech');
      return;
    }

    // The microphone delivered measurable samples and not one of them cleared
    // the absolute silence gate: the mic was muted, covered, or held by another
    // app. Uploading tens of kilobytes of nothing to be told "I heard nothing"
    // costs the shopkeeper the full round trip, so answer immediately. Only
    // fires when samples actually arrived -- see [SpeechEndDetector.capturedNothing].
    if (detector != null && detector.capturedNothing) {
      state = state.copyWith(phase: VoicePhase.error, errorMessage: 'tooQuiet');
      return;
    }

    _lastRecording = recording;
    await _parseAudio(recording, session);
  }

  /// Re-sends the recording already in hand. The shopkeeper said the sale once;
  /// a transport failure or a model hiccup is no reason to make them say it
  /// again into the same noisy room. Falls back to [reset] when there is
  /// nothing kept (mic denied, offline, silence -- nothing was ever captured).
  Future<void> retryLastAudio() async {
    final recording = _lastRecording;
    if (recording == null) {
      reset();
      return;
    }
    _capTimer?.cancel();
    _capTimer = null;
    _stopWatchingLevels();
    final session = ++_session; // supersede anything still in flight
    await _parseAudio(recording, session);
  }

  /// Shared tail of [stopAndParse] and [retryLastAudio]: upload, match, and
  /// land in `reviewing` or `error`. [session] must already be current.
  Future<void> _parseAudio(
    ({Uint8List bytes, String mime}) recording,
    int session,
  ) async {
    state = state.copyWith(phase: VoicePhase.thinking);

    final result = await ref
        .read(voiceSaleRepositoryProvider)
        .parse(
          audioBytes: recording.bytes,
          audioMime: recording.mime,
          candidates: _candidates(),
        );
    if (_session != session) return;
    // The audio is still in hand either way, so a failure here can always be
    // retried without re-recording.
    _applyResult(result, canRetryAudio: true);
  }

  /// Re-runs parsing on a shopkeeper-edited [transcript] (the text path of
  /// `parse-sale`), rebuilding the reviewable lines so a single misheard word
  /// can be fixed without re-recording. Empty input is a no-op.
  Future<void> reparseFromText(String transcript) async {
    _capTimer?.cancel();
    _capTimer = null;
    _stopWatchingLevels();
    final text = transcript.trim();
    if (text.isEmpty) return;
    final session = ++_session; // supersede any in-flight recording/parse
    state = state.copyWith(phase: VoicePhase.thinking);

    final result = await ref
        .read(voiceSaleRepositoryProvider)
        .parseTranscript(transcript: text, candidates: _candidates());
    if (_session != session) return;

    // The shopkeeper typed this sale; offering "retry the recording" here would
    // throw their correction away, so the audio path stays closed.
    _applyResult(result, canRetryAudio: false, fallbackHeardText: text);
  }

  /// The shop's products as matching candidates, enriched with recent sales
  /// volume when that lookup has landed. `.value ?? const {}` throughout: this
  /// runs on the latency-critical path, so missing data degrades the hint and
  /// never delays the upload.
  List<Map<String, dynamic>> _candidates() => buildCandidates(
    ref.read(productsStreamProvider).value ?? const [],
    includeUnit: true,
    recentUnits: ref.read(recentUnitsSoldProvider).value,
  );

  /// Lands a parse result in `reviewing` or `error`, uniformly for the audio and
  /// text paths.
  ///
  /// [canRetryAudio] applies only to the *failure* branch -- a transport error
  /// or a model hiccup, where the same bytes really may succeed on a second
  /// attempt.
  void _applyResult(
    Result<VoiceParseResult> result, {
    required bool canRetryAudio,
    String? fallbackHeardText,
  }) {
    result.when(
      success: (parsed) {
        final lines = buildVoiceLines(
          parsed,
          thresholds: ref.read(voiceThresholdsProvider),
        );
        _logCalibration(parsed, lines);
        state = state.copyWith(
          phase: lines.isEmpty ? VoicePhase.error : VoicePhase.reviewing,
          heardText: parsed.heardText ?? fallbackHeardText,
          lines: lines,
          errorMessage: lines.isEmpty ? 'noMatch' : null,
          // Deliberately false even for `noMatch`. The upload succeeded and the
          // model gave a real answer -- it just matched nothing in this shop.
          // Re-sending identical bytes would produce the identical answer, so
          // offering "try again" there is the same empty promise the error pane
          // used to make. Typing the sale, or recording it again, are the only
          // actions that can actually change the outcome.
          canRetryAudio: false,
        );
      },
      failure: (f) => state = state.copyWith(
        phase: VoicePhase.error,
        errorMessage: f.message,
        canRetryAudio: canRetryAudio,
      ),
    );
  }

  /// Debug-only trace of what the model was confident about versus what
  /// [VoiceThresholds] then did with it.
  ///
  /// The thresholds shipped as estimates -- 0.80 to pre-fill, a 0.15 lead over
  /// the runner-up -- and were never checked against real speech. Calibrating
  /// them is a measuring job, not a coding one: run real sales, watch how often
  /// a confident-and-correct top match still landed in `ambiguous` (thresholds
  /// too strict) or a wrong one got pre-filled (too loose), then override
  /// [voiceThresholdsProvider]. This line is the measurement.
  void _logCalibration(VoiceParseResult parsed, List<VoiceLine> lines) {
    if (!kDebugMode) return;
    for (var i = 0; i < parsed.items.length && i < lines.length; i++) {
      final ranked = [...parsed.items[i].matches]
        ..sort((a, b) => b.confidence.compareTo(a.confidence));
      final top = ranked.isNotEmpty ? ranked.first.confidence : null;
      final second = ranked.length > 1 ? ranked[1].confidence : null;
      debugPrint(
        'voice-calibration: heard="${parsed.items[i].heard}" '
        'status=${lines[i].status.name} top=$top runnerUp=$second '
        'lead=${top != null && second != null ? (top - second).toStringAsFixed(2) : 'n/a'}',
      );
    }
  }

  void choose(int index, String productId) =>
      _replace(index, state.lines[index].chooseProduct(productId));

  void setQuantity(int index, double quantity) =>
      _replace(index, state.lines[index].withQuantity(quantity));

  void removeLine(int index) =>
      state = state.copyWith(lines: removeLineAt(state.lines, index));

  void reset() {
    _capTimer?.cancel();
    _capTimer = null;
    _stopWatchingLevels();
    _lastRecording = null;
    _session++;
    // Fire-and-forget: a user backing out mid-recording must actually stop
    // the mic, but reset() itself stays synchronous.
    unawaited(ref.read(audioRecorderProvider).cancel());
    state = const VoiceSaleState();
  }

  void _replace(int index, VoiceLine line) {
    final next = [...state.lines];
    next[index] = line;
    state = state.copyWith(lines: next);
  }
}

final voiceControllerProvider =
    NotifierProvider<VoiceController, VoiceSaleState>(VoiceController.new);

/// How long a single recording may run before it auto-stops and parses.
/// Unbounded clips are a real latency risk: in a noisy shop people repeat
/// themselves, and every extra second is more to upload and more for the model
/// to transcribe. A provider (not a bare constant) so tests can shorten it.
final maxRecordingDurationProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 15),
);

/// How long before [maxRecordingDurationProvider] elapses the listening pane
/// starts counting down. Long enough to finish a sentence, short enough that the
/// warning is not on screen for most of a normal recording.
const autoStopWarning = Duration(seconds: 5);

/// Whether the device currently has a usable network interface, as a plain
/// synchronous bool.
///
/// Exists so the recording path never has to reason about `AsyncValue`: it
/// **fails open**, reporting online whenever connectivity is still loading or
/// errored, matching `AuthController`'s idiom. Being wrong in that direction
/// costs a wasted upload; being wrong the other way would refuse to record for a
/// shopkeeper whose connection is fine.
final voiceOnlineProvider = Provider<bool>(
  (ref) => ref.watch(isOnlineProvider).value ?? true,
);

/// Whether a recording stops itself once the shopkeeper stops speaking. A
/// provider so it can be turned off wholesale if silence detection ever proves
/// wrong for a particular shop, without touching the recording path.
final autoStopOnSilenceProvider = Provider<bool>((ref) => true);

/// Thresholds mapping model confidence onto a review action. A provider (not a
/// bare const) because the shipped values are estimates that want calibrating
/// against real speech -- see [VoiceController._logCalibration] for how to
/// gather the evidence, then override this.
final voiceThresholdsProvider = Provider<VoiceThresholds>(
  (ref) => const VoiceThresholds(),
);

/// The live microphone level, `0.0..1.0`, for the listening pane's meter.
///
/// Separate from [VoiceSaleState] on purpose: this changes five times a second,
/// and folding it into the controller's state would rebuild the whole sheet --
/// review rows and all -- at that rate. Here, only the meter watches it.
class MicLevel extends Notifier<double> {
  @override
  double build() => 0;

  /// Publishes one raw dBFS reading from the recorder.
  void report(double dbfs) => state = normalizeMicLevel(dbfs);

  void clear() => state = 0;
}

final micLevelProvider = NotifierProvider<MicLevel, double>(MicLevel.new);

/// Physical confirmation that recording started and stopped, so a shopkeeper
/// mid-transaction does not have to look at the screen to know the phone heard
/// the tap. Behind a seam because it is a platform channel: tests override it,
/// and every call is best-effort -- a device without a vibrator, or a test
/// binding with no platform, must never turn a missing buzz into a failed sale.
class VoiceHaptics {
  const VoiceHaptics();

  void recordingStarted() => _fire(HapticFeedback.mediumImpact);

  void recordingStopped() => _fire(HapticFeedback.selectionClick);

  static void _fire(Future<void> Function() effect) {
    try {
      effect().catchError((_) {});
    } catch (_) {
      // Synchronous throw (no platform binding at all) -- same non-event.
    }
  }
}

final voiceHapticsProvider = Provider<VoiceHaptics>(
  (ref) => const VoiceHaptics(),
);
