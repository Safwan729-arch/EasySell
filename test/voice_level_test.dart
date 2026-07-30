import 'package:ai_shopkeeper/features/voice/domain/voice_level.dart';
import 'package:flutter_test/flutter_test.dart';

/// Feeds a whole run of samples and returns the final phase.
SpeechPhase _feed(SpeechEndDetector d, List<double> samples) {
  var phase = SpeechPhase.calibrating;
  for (final s in samples) {
    phase = d.add(s);
  }
  return phase;
}

List<double> _repeat(double value, int times) =>
    List<double>.filled(times, value);

void main() {
  group('normalizeMicLevel', () {
    test('clamps to 0 at and below the quiet floor', () {
      expect(normalizeMicLevel(micQuietDbfs), 0);
      expect(normalizeMicLevel(-160), 0);
    });

    test('reaches 1 at full scale and clamps above it', () {
      expect(normalizeMicLevel(0), 1);
      expect(normalizeMicLevel(3), 1);
    });

    test('is monotonic and midway at half the range', () {
      expect(normalizeMicLevel(-25), closeTo(0.5, 1e-9));
      expect(normalizeMicLevel(-10), greaterThan(normalizeMicLevel(-20)));
    });

    test('NaN reads as silence rather than propagating', () {
      expect(normalizeMicLevel(double.nan), 0);
    });
  });

  group('SpeechEndDetector', () {
    test('stays calibrating until the calibration window is full', () {
      final d = SpeechEndDetector(calibrationSamples: 5);
      expect(_feed(d, _repeat(-30, 4)), SpeechPhase.calibrating);
      expect(d.speechThresholdDbfs, isNull);
    });

    test('ends the recording after speech followed by trailing silence', () {
      final d = SpeechEndDetector(
        calibrationSamples: 5,
        speechOnsetSamples: 2,
        trailingSilenceSamples: 6,
      );
      // Quiet room, then a sentence, then back to quiet.
      final phase = _feed(d, [
        ..._repeat(-40, 5), // calibrate -> threshold -30
        ..._repeat(-12, 8), // speech
        ..._repeat(-40, 6), // trailing silence
      ]);
      expect(phase, SpeechPhase.ended);
      expect(d.sawSpeech, isTrue);
    });

    test('does not end while speech is still going', () {
      final d = SpeechEndDetector(calibrationSamples: 5);
      final phase = _feed(d, [..._repeat(-40, 5), ..._repeat(-12, 20)]);
      expect(phase, SpeechPhase.speaking);
    });

    test('never ends when no speech is ever detected -- the caller\'s duration '
        'cap stays the only stop', () {
      final d = SpeechEndDetector(calibrationSamples: 5);
      final phase = _feed(d, _repeat(-40, 100));
      expect(phase, SpeechPhase.waitingForSpeech);
      expect(d.sawSpeech, isFalse);
    });

    test('a single loud transient is not speech, so it cannot end the '
        'recording', () {
      final d = SpeechEndDetector(
        calibrationSamples: 5,
        speechOnsetSamples: 2,
        trailingSilenceSamples: 6,
      );
      final phase = _feed(d, [
        ..._repeat(-40, 5),
        -6, // one dropped crate
        ..._repeat(-40, 30),
      ]);
      expect(phase, SpeechPhase.waitingForSpeech);
      expect(d.sawSpeech, isFalse);
    });

    test('a noisy shop floor raises the threshold, so background chatter alone '
        'is not speech', () {
      final d = SpeechEndDetector(calibrationSamples: 5, speechMarginDb: 10);
      // Sustained -22 dBFS market noise: floor -22, threshold -12.
      _feed(d, _repeat(-22, 5));
      expect(d.speechThresholdDbfs, closeTo(-12, 1e-9));
      // More of the same noise never reads as speech.
      expect(_feed(d, _repeat(-22, 20)), SpeechPhase.waitingForSpeech);
      // The shopkeeper speaking over it does.
      expect(_feed(d, _repeat(-8, 3)), SpeechPhase.speaking);
    });

    test('calibrating on the quietest sample survives a shopkeeper who talks '
        'immediately', () {
      final d = SpeechEndDetector(calibrationSamples: 5, speechMarginDb: 10);
      // Speech from the very first sample, with one quiet gap between words.
      _feed(d, [-10, -10, -38, -10, -10]);
      // Floor is the -38 gap, not the -10 speech, so the threshold is usable.
      expect(d.speechThresholdDbfs, closeTo(-28, 1e-9));
      // Only the final calibration sample is judged against the fresh
      // threshold, so onset needs one more -- but crucially the threshold is
      // reachable at all, which a mean/max floor would not have been.
      expect(d.add(-10), SpeechPhase.speaking);
    });

    test('a near-silent room does not drive the threshold below the absolute '
        'minimum', () {
      final d = SpeechEndDetector(
        calibrationSamples: 5,
        speechMarginDb: 10,
        minSpeechThresholdDbfs: -45,
      );
      _feed(d, _repeat(-160, 5)); // digital-silence sentinel
      expect(d.speechThresholdDbfs, -45);
    });

    test('the ended verdict latches', () {
      final d = SpeechEndDetector(
        calibrationSamples: 5,
        trailingSilenceSamples: 3,
      );
      _feed(d, [..._repeat(-40, 5), ..._repeat(-12, 4), ..._repeat(-40, 3)]);
      expect(d.add(-6), SpeechPhase.ended);
      expect(d.add(-40), SpeechPhase.ended);
    });

    group('capturedNothing', () {
      test('is false before any sample -- no data is not silence', () {
        expect(SpeechEndDetector().capturedNothing, isFalse);
        expect(SpeechEndDetector().sampleCount, 0);
      });

      test('is true when the whole clip stayed under the absolute gate', () {
        final d = SpeechEndDetector();
        _feed(d, _repeat(-160, 20));
        expect(d.capturedNothing, isTrue);
      });

      test('is false for quiet speech in a noisy room, which must still be '
          'uploaded', () {
        final d = SpeechEndDetector();
        _feed(d, [..._repeat(-30, 5), ..._repeat(-24, 10)]);
        expect(d.capturedNothing, isFalse);
      });

      test('is false once any sample crosses the gate, even briefly', () {
        final d = SpeechEndDetector();
        _feed(d, [..._repeat(-160, 20), -44]);
        expect(d.capturedNothing, isFalse);
      });
    });
  });
}
