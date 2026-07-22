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

/// Adapts `package:record` (v7.1.1) to [AudioRecorderPort].
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
class RecordAudioRecorder implements AudioRecorderPort {
  final _engine = record_pkg.AudioRecorder();
  String? _pendingPath;

  @override
  Future<bool> hasPermission() => _engine.hasPermission();

  @override
  Future<void> start() async {
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice-sale-${DateTime.now().microsecondsSinceEpoch}.m4a';
    _pendingPath = path;
    await _engine.start(
      const record_pkg.RecordConfig(encoder: record_pkg.AudioEncoder.aacLc),
      path: path,
    );
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
