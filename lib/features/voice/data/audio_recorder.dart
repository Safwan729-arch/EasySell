import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart' as record_pkg;

/// MEMBER C seam: microphone capture for cloud transcription. The gateway now
/// accepts audio directly (superseding spec §0's on-device-only constraint),
/// so this seam records raw bytes instead of listening for a transcript
/// on-device. Kept behind this tiny interface so a richer recorder can
/// replace it without touching the controller or UI.
abstract class AudioRecorderPort {
  /// Checks (and requests, if needed) microphone permission. False when the
  /// user refused the mic or the device has no recorder.
  Future<bool> hasPermission();

  /// Begin recording to a private temp file.
  Future<void> start();

  /// Stop recording and return the captured audio, or `null` if nothing was
  /// captured (no active session, or an empty/missing file). The backing
  /// temp file is deleted before this returns either way.
  Future<({Uint8List bytes, String mime})?> stop();

  /// Stop and discard the in-progress recording (its temp file is removed).
  Future<void> cancel();

  Future<void> dispose();
}

/// Seam over `package:record`'s concrete `AudioRecorder` so the start-config
/// fallback ladder in [RecordAudioRecorder.start] is unit-testable without a
/// real microphone or platform channel.
abstract class RecorderEngine {
  Future<bool> hasPermission();
  Future<void> start(record_pkg.RecordConfig config, {required String path});
  Future<String?> stop();
  Future<void> cancel();
  Future<void> dispose();
}

/// The real engine: a thin pass-through to `package:record`.
class PackageRecorderEngine implements RecorderEngine {
  final _engine = record_pkg.AudioRecorder();

  @override
  Future<bool> hasPermission() => _engine.hasPermission();

  @override
  Future<void> start(record_pkg.RecordConfig config, {required String path}) =>
      _engine.start(config, path: path);

  @override
  Future<String?> stop() => _engine.stop();

  @override
  Future<void> cancel() => _engine.cancel();

  @override
  Future<void> dispose() => _engine.dispose();
}

/// Speech-tuned capture. Mono / 16kHz / 32kbps costs ~4 KB per second of
/// speech instead of the package defaults' ~16 KB/s, cutting upload time (and
/// therefore total latency) roughly 4x before base64's further 33%.
///
/// `sampleRate`/`numChannels`/`bitRate` are NOT universally supported --
/// `PCMReader.calculateBufferSize` throws when `AudioRecord.getMinBufferSize`
/// rejects the combination -- which is exactly why [RecordAudioRecorder.start]
/// falls back to [fallbackRecordConfig] rather than letting a rejection kill
/// the feature on that device.
///
/// The effect flags below are safe everywhere: `AudioEffectsManager.apply()`
/// guards each with `isAvailable()` and silently skips what the hardware lacks.
/// On iOS they are no-ops for file recording -- iOS's win here is the smaller
/// payload, not the flags.
const speechRecordConfig = record_pkg.RecordConfig(
  encoder: record_pkg.AudioEncoder.aacLc,
  sampleRate: 16000,
  numChannels: 1,
  bitRate: 32000,
  noiseSuppress: true,
  autoGain: true,
  // Deliberately off: echo cancellation targets speaker playback bleeding into
  // the mic (not a shop-noise problem) and the package documents that it
  // lowers recording volume -- pure cost here.
  echoCancel: false,
  androidConfig: record_pkg.AndroidRecordConfig(
    // Routes to the ASR-tuned capture path Google's own speech recognition
    // uses. Falls back to the default source on devices that don't implement
    // it, so it is safe to request unconditionally.
    audioSource: record_pkg.AndroidAudioSource.voiceRecognition,
  ),
);

/// Second rung of the ladder: today's rates (the package defaults), keeping the
/// effect flags since those can never throw. Worst case on an exotic device is
/// therefore exactly the behavior that shipped before this change.
const fallbackRecordConfig = record_pkg.RecordConfig(
  encoder: record_pkg.AudioEncoder.aacLc,
  noiseSuppress: true,
  autoGain: true,
  echoCancel: false,
  androidConfig: record_pkg.AndroidRecordConfig(
    audioSource: record_pkg.AndroidAudioSource.voiceRecognition,
  ),
);

/// Adapts `package:record` (v7.1.1) to [AudioRecorderPort], recording with a
/// speech-tuned profile and falling back to the package defaults on hardware
/// that rejects it.
///
/// The installed major requires a file path up front --
/// `AudioRecorder.start(config, path: ...)` writes straight to disk and
/// `stop()` returns that path (not bytes), so this wrapper picks a fresh
/// path in the platform temp directory (via `path_provider`) on every
/// [start], reads the bytes back on [stop], and always deletes the temp
/// file afterwards -- on [stop] once the bytes are safely read, and on
/// [cancel] (the plugin itself removes the file on cancel, but the delete
/// here is a harmless no-op if so and a real cleanup if the file survived).
/// Recording uses the AAC-LC encoder in an `.m4a` container, which is both
/// the plugin's default and the broadest-supported combination across
/// Android/iOS/Windows/macOS.
///
/// [RecorderEngine] and the temp-directory function are injectable so the
/// fallback ladder can be unit-tested without a microphone or a platform
/// channel; production wiring uses the real defaults.
class RecordAudioRecorder implements AudioRecorderPort {
  RecordAudioRecorder({
    RecorderEngine? engine,
    Future<Directory> Function()? temporaryDirectory,
  }) : _engine = engine ?? PackageRecorderEngine(),
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  final RecorderEngine _engine;
  final Future<Directory> Function() _temporaryDirectory;
  String? _pendingPath;

  @override
  Future<bool> hasPermission() => _engine.hasPermission();

  /// Two-rung ladder: ask for the speech profile, and if this device's hardware
  /// rejects those rates, release the partial session and retry once with the
  /// defaults. Only a failure of BOTH rungs propagates (the controller then
  /// reports `noSpeech`), so the optimization can never be the reason voice
  /// stops working on some phone we couldn't test.
  @override
  Future<void> start() async {
    try {
      await _startWith(speechRecordConfig);
    } catch (_) {
      await _cancelQuietly();
      await _startWith(fallbackRecordConfig);
    }
  }

  Future<void> _startWith(record_pkg.RecordConfig config) async {
    final dir = await _temporaryDirectory();
    final path =
        '${dir.path}/voice-sale-${DateTime.now().microsecondsSinceEpoch}.m4a';
    _pendingPath = path;
    await _engine.start(config, path: path);
  }

  @override
  Future<({Uint8List bytes, String mime})?> stop() async {
    final stoppedPath = await _engine.stop();
    final path = stoppedPath ?? _pendingPath;
    _pendingPath = null;
    if (path == null) return null;

    final file = File(path);
    try {
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      return (bytes: bytes, mime: 'audio/aac');
    } finally {
      await _deleteQuietly(file);
    }
  }

  @override
  Future<void> cancel() async {
    await _engine.cancel();
    final path = _pendingPath;
    _pendingPath = null;
    if (path != null) {
      await _deleteQuietly(File(path));
    }
  }

  @override
  Future<void> dispose() => _engine.dispose();

  /// Teardown between ladder rungs: the first rung may have left a partial
  /// session or temp file behind, and neither may block the retry, so every
  /// failure here is swallowed.
  Future<void> _cancelQuietly() async {
    try {
      await cancel();
    } catch (_) {
      // Best-effort: a failed cleanup must not mask the retry's own outcome.
    }
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best-effort cleanup: a stray temp file is a disk-space nit, not a
      // functional failure worth surfacing to the caller.
    }
  }
}

final audioRecorderProvider = Provider<AudioRecorderPort>((ref) {
  final recorder = RecordAudioRecorder();
  ref.onDispose(() => recorder.dispose());
  return recorder;
});
