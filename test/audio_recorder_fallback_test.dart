import 'dart:io';

import 'package:ai_shopkeeper/features/voice/data/audio_recorder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart' as record_pkg;

/// Fake engine that records every config `start()` was attempted with and can
/// be told to reject the first N attempts -- standing in for a device whose
/// hardware refuses the 16kHz/mono profile (`PCMReader` throws in that case).
class _FakeEngine implements RecorderEngine {
  _FakeEngine({this.failFirstN = 0});

  final int failFirstN;
  final attempted = <record_pkg.RecordConfig>[];
  bool cancelled = false;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> start(
    record_pkg.RecordConfig config, {
    required String path,
  }) async {
    attempted.add(config);
    if (attempted.length <= failFirstN) {
      throw Exception('Recording config is not supported by the hardware');
    }
  }

  @override
  Future<String?> stop() async => null;

  @override
  Future<void> cancel() async => cancelled = true;

  @override
  Future<void> dispose() async {}
}

RecordAudioRecorder _recorder(_FakeEngine engine) => RecordAudioRecorder(
  engine: engine,
  temporaryDirectory: () async => Directory.systemTemp,
);

void main() {
  group('RecordAudioRecorder capture profile', () {
    test('uses the speech profile when the hardware accepts it', () async {
      final engine = _FakeEngine();

      await _recorder(engine).start();

      expect(engine.attempted, hasLength(1));
      final config = engine.attempted.single;
      expect(config.sampleRate, 16000);
      expect(config.numChannels, 1);
      expect(config.bitRate, 32000);
      expect(engine.cancelled, isFalse);
    });

    test(
      'falls back to the default rates when the speech profile throws',
      () async {
        final engine = _FakeEngine(failFirstN: 1);

        await _recorder(engine).start();

        expect(engine.attempted, hasLength(2));
        final fallback = engine.attempted.last;
        expect(fallback.sampleRate, 44100);
        expect(fallback.numChannels, 2);
        expect(fallback.bitRate, 128000);
        // The partial session must be released before the retry.
        expect(engine.cancelled, isTrue);
      },
    );

    test('the fallback keeps the effect flags, which never throw', () async {
      final engine = _FakeEngine(failFirstN: 1);

      await _recorder(engine).start();

      for (final config in engine.attempted) {
        expect(config.noiseSuppress, isTrue);
        expect(config.autoGain, isTrue);
        // Off on purpose: it targets playback bleed and lowers input volume.
        expect(config.echoCancel, isFalse);
        expect(
          config.androidConfig.audioSource,
          record_pkg.AndroidAudioSource.voiceRecognition,
        );
      }
    });

    test(
      'a device that rejects both profiles propagates the failure',
      () async {
        final engine = _FakeEngine(failFirstN: 2);

        await expectLater(_recorder(engine).start(), throwsException);
        expect(engine.attempted, hasLength(2));
      },
    );
  });
}
