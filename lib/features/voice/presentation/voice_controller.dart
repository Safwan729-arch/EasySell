import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/locale_provider.dart';
import '../../inventory/presentation/inventory_controller.dart';
import '../../scan/domain/scan_candidates.dart';
import '../data/speech_recognizer.dart';
import '../data/voice_sale_repository.dart';
import '../domain/voice_line.dart';

/// Maps the app's active [Locale] to a speech-recognizer locale id. Pure and
/// top-level so it is directly unit-testable. Bengali gets the Bangladesh
/// locale; everything else falls back to US English (the recognizer's most
/// broadly supported id).
String recognizerLocaleFor(Locale locale) =>
    locale.languageCode == 'bn' ? 'bn_BD' : 'en_US';

enum VoicePhase { idle, listening, thinking, reviewing, error }

/// State for the voice-sale flow: mic listening -> transcript -> parsed ->
/// reviewable lines. Mirrors the vision-scan controller's shape, with the
/// ears swapped for a microphone.
class VoiceSaleState {
  const VoiceSaleState({
    this.phase = VoicePhase.idle,
    this.liveTranscript = '',
    this.heardText,
    this.lines = const <VoiceLine>[],
    this.errorMessage,
  });

  final VoicePhase phase;

  /// The transcript as recognized so far, updated live from partial results
  /// while [phase] is `listening` so the sheet can show words as they land.
  final String liveTranscript;

  /// The transcript the `parse-sale` function actually worked from, echoed
  /// back so a mishear is obvious to the user.
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
    String? liveTranscript,
    String? heardText,
    List<VoiceLine>? lines,
    String? errorMessage,
  }) => VoiceSaleState(
    phase: phase ?? this.phase,
    liveTranscript: liveTranscript ?? this.liveTranscript,
    heardText: heardText ?? this.heardText,
    lines: lines ?? this.lines,
    errorMessage: errorMessage,
  );
}

/// Orchestrates listen -> transcript -> `parse-sale` -> reviewable lines.
/// Never talks to Supabase directly (that's [VoiceSaleRepository]'s job) and
/// never builds widgets.
class VoiceController extends Notifier<VoiceSaleState> {
  @override
  VoiceSaleState build() => const VoiceSaleState();

  Future<void> startListening() async {
    final recognizer = ref.read(speechRecognizerProvider);
    final ok = await recognizer.initialize();
    if (!ok) {
      state = state.copyWith(
        phase: VoicePhase.error,
        errorMessage: 'micDenied',
      );
      return;
    }

    state = state.copyWith(phase: VoicePhase.listening, liveTranscript: '');

    final localeId = recognizerLocaleFor(ref.read(localeProvider));
    await recognizer.start(
      localeId: localeId,
      onResult: (text, isFinal) {
        state = state.copyWith(liveTranscript: text);
      },
    );
  }

  Future<void> stopAndParse() async {
    final recognizer = ref.read(speechRecognizerProvider);
    await recognizer.stop();

    final transcript = state.liveTranscript.trim();
    if (transcript.isEmpty) {
      state = state.copyWith(phase: VoicePhase.error, errorMessage: 'noSpeech');
      return;
    }

    state = state.copyWith(phase: VoicePhase.thinking);

    final products = ref.read(productsStreamProvider).value ?? const [];
    final result = await ref
        .read(voiceSaleRepositoryProvider)
        .parse(
          transcript: transcript,
          candidates: buildCandidates(products, includeUnit: true),
        );

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

  void choose(int index, String productId) =>
      _replace(index, state.lines[index].chooseProduct(productId));

  void setQuantity(int index, double quantity) =>
      _replace(index, state.lines[index].withQuantity(quantity));

  void removeLine(int index) =>
      state = state.copyWith(lines: removeLineAt(state.lines, index));

  void reset() => state = const VoiceSaleState();

  void _replace(int index, VoiceLine line) {
    final next = [...state.lines];
    next[index] = line;
    state = state.copyWith(lines: next);
  }
}

final voiceControllerProvider =
    NotifierProvider<VoiceController, VoiceSaleState>(VoiceController.new);
