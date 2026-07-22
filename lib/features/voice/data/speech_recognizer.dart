import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// MEMBER C seam: on-device speech-to-text. The gateway cannot accept audio
/// (spec §0), so the phone listens and only the transcript leaves the device.
/// Kept behind this tiny interface so a richer engine can replace it without
/// touching the controller or UI.
abstract class SpeechRecognizerPort {
  /// Prepares the engine and triggers the permission prompt. False when the
  /// user refused the mic or the device has no recognizer.
  Future<bool> initialize();

  /// Begin listening. [onResult] fires repeatedly with the partial transcript
  /// and once more with `isFinal: true` when recognition settles.
  Future<void> start({
    required String localeId,
    required void Function(String text, bool isFinal) onResult,
  });

  Future<void> stop();
  Future<void> cancel();
}

/// Adapts `package:speech_to_text` (v7.4.0) to [SpeechRecognizerPort].
///
/// `initialize()` and `stop()`/`cancel()` match the port 1:1. `listen()` is
/// the one method whose surface changed upstream: since 6.6.0 the individual
/// `partialResults`/`localeId` params are deprecated in favour of a single
/// `listenOptions: SpeechListenOptions(...)` object, so we build that instead
/// of passing `localeId` directly (avoids deprecation warnings and is the
/// documented way forward). `onResult` still hands back a
/// `SpeechRecognitionResult` with `.recognizedWords` / `.finalResult`, which
/// is what the brief's sketch assumed.
class SpeechToTextRecognizer implements SpeechRecognizerPort {
  final _engine = SpeechToText();

  @override
  Future<bool> initialize() => _engine.initialize();

  @override
  Future<void> start({
    required String localeId,
    required void Function(String text, bool isFinal) onResult,
  }) => _engine.listen(
    onResult: (result) => onResult(result.recognizedWords, result.finalResult),
    listenOptions: SpeechListenOptions(
      localeId: localeId,
      partialResults: true,
    ),
  );

  @override
  Future<void> stop() => _engine.stop();

  @override
  Future<void> cancel() => _engine.cancel();
}

final speechRecognizerProvider = Provider<SpeechRecognizerPort>((ref) {
  return SpeechToTextRecognizer();
});
