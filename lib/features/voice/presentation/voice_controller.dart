import 'dart:async' show unawaited;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../inventory/presentation/inventory_controller.dart';
import '../../scan/domain/scan_candidates.dart';
import '../data/audio_recorder.dart';
import '../data/voice_sale_repository.dart';
import '../domain/voice_line.dart';

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
  });

  final VoicePhase phase;

  /// The transcript the `parse-sale` function actually worked from (produced
  /// server-side from the recorded audio), echoed back so a mishear is
  /// obvious to the user.
  final String? heardText;

  final List<VoiceLine> lines;

  /// A magic string key (`micDenied` / `noSpeech` / `noMatch`) or a repository
  /// `Failure.message` -- the UI maps these to localized copy.
  final String? errorMessage;

  bool get canAdd => canAddToCart(lines);

  /// [errorMessage] is intentionally NOT defaulted to `this.errorMessage`: every
  /// transition must explicitly say whether an error applies, so a stale error
  /// can never leak into a later, successful state.
  VoiceSaleState copyWith({
    VoicePhase? phase,
    String? heardText,
    List<VoiceLine>? lines,
    String? errorMessage,
  }) => VoiceSaleState(
    phase: phase ?? this.phase,
    heardText: heardText ?? this.heardText,
    lines: lines ?? this.lines,
    errorMessage: errorMessage,
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

  @override
  VoiceSaleState build() => const VoiceSaleState();

  Future<void> startListening() async {
    final session = ++_session;
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
    }
  }

  Future<void> stopAndParse() async {
    // Guards double-tap and stop-before-start.
    if (state.phase != VoicePhase.listening) return;
    final session = _session;

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

    state = state.copyWith(phase: VoicePhase.thinking);

    final products = ref.read(productsStreamProvider).value ?? const [];
    final result = await ref
        .read(voiceSaleRepositoryProvider)
        .parse(
          audioBytes: recording.bytes,
          audioMime: recording.mime,
          candidates: buildCandidates(products, includeUnit: true),
        );
    if (_session != session) return;

    result.when(
      success: (parsed) {
        final lines = buildVoiceLines(parsed);
        state = state.copyWith(
          phase: lines.isEmpty ? VoicePhase.error : VoicePhase.reviewing,
          heardText: parsed.heardText,
          lines: lines,
          errorMessage: lines.isEmpty ? 'noMatch' : null,
        );
      },
      failure: (f) => state = state.copyWith(
        phase: VoicePhase.error,
        errorMessage: f.message,
      ),
    );
  }

  /// Re-runs parsing on a shopkeeper-edited [transcript] (the text path of
  /// `parse-sale`), rebuilding the reviewable lines so a single misheard word
  /// can be fixed without re-recording. Empty input is a no-op.
  Future<void> reparseFromText(String transcript) async {
    final text = transcript.trim();
    if (text.isEmpty) return;
    final session = ++_session; // supersede any in-flight recording/parse
    state = state.copyWith(phase: VoicePhase.thinking);

    final products = ref.read(productsStreamProvider).value ?? const [];
    final result = await ref
        .read(voiceSaleRepositoryProvider)
        .parseTranscript(
          transcript: text,
          candidates: buildCandidates(products, includeUnit: true),
        );
    if (_session != session) return;

    result.when(
      success: (parsed) {
        final lines = buildVoiceLines(parsed);
        state = state.copyWith(
          phase: lines.isEmpty ? VoicePhase.error : VoicePhase.reviewing,
          heardText: parsed.heardText ?? text,
          lines: lines,
          errorMessage: lines.isEmpty ? 'noMatch' : null,
        );
      },
      failure: (f) => state = state.copyWith(
        phase: VoicePhase.error,
        errorMessage: f.message,
      ),
    );
  }

  void choose(int index, String productId) =>
      _replace(index, state.lines[index].chooseProduct(productId));

  void setQuantity(int index, double quantity) =>
      _replace(index, state.lines[index].withQuantity(quantity));

  void removeLine(int index) =>
      state = state.copyWith(lines: removeLineAt(state.lines, index));

  void reset() {
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
