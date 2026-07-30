import 'dart:io';

import 'package:ai_shopkeeper/features/voice/data/audio_recorder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart' as record_pkg;

/// Fake engine that records every config `start()` was attempted with and can
/// be told to reject the first N attempts -- standing in for a device whose
/// hardware refuses the 16kHz/mono profile (`PCMReader` throws in that case).
class _FakeEngine implements RecorderEngine {
  _FakeEngine({this.failFirstN = 0, this.amplitudes, this.amplitudeError});

  final int failFirstN;

  /// Successive dBFS readings `getAmplitude()` hands back, cycling once
  /// exhausted. Null means a flat -20.
  final List<double>? amplitudes;

  /// When set, `getAmplitude()` always throws it -- a platform that cannot
  /// report loudness at all.
  final Object? amplitudeError;

  final attempted = <record_pkg.RecordConfig>[];
  bool cancelled = false;
  int amplitudeCalls = 0;

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
  Future<record_pkg.Amplitude> getAmplitude() async {
    if (amplitudeError case final error?) throw error;
    final samples = amplitudes;
    final value = samples == null || samples.isEmpty
        ? -20.0
        : samples[amplitudeCalls % samples.length];
    amplitudeCalls++;
    return record_pkg.Amplitude(current: value, max: value);
  }

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

  group('RecordAudioRecorder level sampling', () {
    /// Long enough for several [micLevelInterval] ticks.
    Future<void> sampleFor([int intervals = 4]) =>
        Future<void>.delayed(micLevelInterval * intervals);

    test('emits dBFS samples while recording', () async {
      final engine = _FakeEngine(amplitudes: const [-30, -12]);
      final recorder = _recorder(engine);
      final seen = <double>[];
      final sub = recorder.levels.listen(seen.add);
      addTearDown(sub.cancel);

      await recorder.start();
      await sampleFor();

      expect(seen, isNotEmpty);
      expect(seen, everyElement(anyOf(-30.0, -12.0)));
      await recorder.stop();
    });

    test('emits nothing before start', () async {
      final recorder = _recorder(_FakeEngine());
      final seen = <double>[];
      final sub = recorder.levels.listen(seen.add);
      addTearDown(sub.cancel);

      await sampleFor();

      expect(seen, isEmpty);
    });

    test('stops emitting after stop, so samples never leak into the next '
        'recording', () async {
      final engine = _FakeEngine();
      final recorder = _recorder(engine);
      final seen = <double>[];
      final sub = recorder.levels.listen(seen.add);
      addTearDown(sub.cancel);

      await recorder.start();
      await sampleFor();
      await recorder.stop();
      final afterStop = seen.length;
      await sampleFor();

      expect(seen, hasLength(afterStop));
    });

    test('stops emitting after cancel', () async {
      final recorder = _recorder(_FakeEngine());
      final seen = <double>[];
      final sub = recorder.levels.listen(seen.add);
      addTearDown(sub.cancel);

      await recorder.start();
      await sampleFor();
      await recorder.cancel();
      final afterCancel = seen.length;
      await sampleFor();

      expect(seen, hasLength(afterCancel));
    });

    test('a platform that cannot report loudness degrades to no samples '
        'instead of failing the recording', () async {
      final engine = _FakeEngine(amplitudeError: UnimplementedError());
      final recorder = _recorder(engine);
      final errors = <Object>[];
      final seen = <double>[];
      final sub = recorder.levels.listen(seen.add, onError: errors.add);
      addTearDown(sub.cancel);

      await recorder.start();
      await sampleFor(8);

      expect(seen, isEmpty);
      expect(errors, isEmpty);
      // Polling gives up rather than hammering a channel that cannot answer.
      expect(engine.amplitudeCalls, lessThanOrEqualTo(3));
      await recorder.stop();
    });
  });
}
