/// Pure mic-level maths for the voice-sale flow. No I/O, no Flutter -- the
/// recorder feeds dBFS samples in, the UI meter and the silence auto-stop read
/// verdicts out.
///
/// **Units.** Every value here is dBFS: 0 dB is a full-scale (clipping) sample
/// and quieter audio is increasingly negative. `package:record` reports
/// `20*log10(peak/32768)` clamped at 0 on Android, `AVAudioRecorder`'s power
/// readings on iOS, and a sentinel of **-160** for digital silence on both.
library;

/// Bottom of the meter. Anything at or below this renders as an empty bar.
///
/// Chosen so the meter has useful resolution across normal speaking distance:
/// a phone held at arm's length in a shop typically peaks between -30 and -6
/// dBFS, while true room tone sits well below -50.
const double micQuietDbfs = -50.0;

/// A whole clip whose loudest sample never reached this was, for practical
/// purposes, **not recorded**: a muted or physically blocked mic, or a mic held
/// by another app that handed us a silent stream.
///
/// Deliberately an *absolute* gate, not a relative one. The relative noise
/// floor in [SpeechEndDetector] is right for deciding when a sentence ended,
/// but it must never be used to decide "we heard nothing" -- in a noisy shop
/// speech can sit only a few dB above the background, and a relative test would
/// throw away a perfectly good recording. A genuinely noisy room is itself far
/// louder than -45 dBFS, so this gate can only fire when the microphone
/// delivered nothing at all.
const double micSilenceFloorDbfs = -45.0;

/// Maps a dBFS reading onto `0.0..1.0` for the level meter, where 1.0 is
/// full scale. Values above 0 dBFS (impossible in practice, but cheap to
/// tolerate) and below [micQuietDbfs] are clamped rather than rejected.
double normalizeMicLevel(double dbfs) {
  if (dbfs.isNaN) return 0;
  return ((dbfs - micQuietDbfs) / -micQuietDbfs).clamp(0.0, 1.0);
}

/// What the detector currently believes about the recording.
enum SpeechPhase {
  /// Still measuring the room. No verdict is possible yet.
  calibrating,

  /// The room is measured but nothing loud enough to be speech has arrived.
  waitingForSpeech,

  /// Speech is in progress.
  speaking,

  /// Speech happened and has now stopped for long enough to end the recording.
  /// Latched: once reached, every later sample returns this too.
  ended,
}

/// Decides when a spoken sentence has finished, from a stream of dBFS samples
/// arriving at a fixed interval.
///
/// The shape of the problem: "silence" in a grocery shop is not silence. A
/// fixed dB threshold would either never trigger in a busy market or trigger
/// constantly in a quiet back room. So the detector spends its first
/// [calibrationSamples] readings measuring the room, then treats
/// `floor + speechMarginDb` as the speech threshold.
///
/// The floor is the **minimum** of the calibration window, not the mean or the
/// max. If the shopkeeper starts talking before calibration finishes -- common,
/// since people speak as soon as they see the mic -- a mean or max would drag
/// the floor up to speech level and the threshold would become unreachable.
/// The minimum is the calibration window's quietest moment, which is the best
/// available estimate of the true background.
///
/// Failure is always toward *not* auto-stopping: if the floor is measured too
/// high, or the platform never reports amplitude at all, no verdict of
/// [SpeechPhase.ended] is ever produced and the recording simply runs until the
/// caller's own duration cap fires. That is the pre-existing behaviour, so this
/// can only ever shorten a recording, never break one.
class SpeechEndDetector {
  SpeechEndDetector({
    this.calibrationSamples = 5,
    this.speechMarginDb = 10.0,
    this.minSpeechThresholdDbfs = micSilenceFloorDbfs,
    this.speechOnsetSamples = 2,
    this.trailingSilenceSamples = 6,
  });

  /// How many opening samples are spent measuring the room.
  final int calibrationSamples;

  /// How far above the measured floor a sample must sit to count as speech.
  final double speechMarginDb;

  /// The speech threshold is never allowed below this. In a genuinely silent
  /// room the measured floor can be near the -160 dBFS sentinel, and
  /// `floor + margin` would then sit so low that room tone alone reads as
  /// speech and the recording would never auto-stop.
  final double minSpeechThresholdDbfs;

  /// Consecutive speech-level samples needed before speech is believed. Rejects
  /// one-off transients -- a dropped crate, a car horn.
  final int speechOnsetSamples;

  /// Consecutive below-threshold samples needed, after speech, to end it.
  final int trailingSilenceSamples;

  final List<double> _calibration = <double>[];
  double? _threshold;
  int _consecutiveSpeech = 0;
  int _consecutiveSilence = 0;
  bool _sawSpeech = false;
  bool _ended = false;
  int _samples = 0;
  double _peakDbfs = double.negativeInfinity;

  /// True once speech has actually been detected (not merely a transient).
  bool get sawSpeech => _sawSpeech;

  /// How many samples have been fed in. Zero means the platform never reported
  /// amplitude, which callers must treat as "unknown", never as "silent".
  int get sampleCount => _samples;

  /// Loudest sample seen so far, or [double.negativeInfinity] before any
  /// sample arrives.
  double get peakDbfs => _peakDbfs;

  /// The speech threshold once calibration has completed, else null.
  double? get speechThresholdDbfs => _threshold;

  /// True when the whole clip so far is quiet enough to count as "the
  /// microphone captured nothing" -- see [micSilenceFloorDbfs]. False while no
  /// samples have arrived, because silence and no-data are different facts.
  bool get capturedNothing => _samples > 0 && _peakDbfs < micSilenceFloorDbfs;

  /// Feeds one reading and returns the current phase.
  SpeechPhase add(double dbfs) {
    if (_ended) return SpeechPhase.ended;
    if (dbfs.isNaN) return _phase();

    _samples++;
    if (dbfs > _peakDbfs) _peakDbfs = dbfs;

    if (_threshold == null) {
      _calibration.add(dbfs);
      if (_calibration.length < calibrationSamples) {
        return SpeechPhase.calibrating;
      }
      final floor = _calibration.reduce((a, b) => a < b ? a : b);
      _threshold = (floor + speechMarginDb) < minSpeechThresholdDbfs
          ? minSpeechThresholdDbfs
          : floor + speechMarginDb;
      // Fall through: this sample is also judged against the fresh threshold,
      // so a shopkeeper who was already talking is credited for it.
    }

    if (dbfs >= _threshold!) {
      _consecutiveSilence = 0;
      _consecutiveSpeech++;
      if (_consecutiveSpeech >= speechOnsetSamples) _sawSpeech = true;
    } else {
      _consecutiveSpeech = 0;
      if (_sawSpeech) {
        _consecutiveSilence++;
        if (_consecutiveSilence >= trailingSilenceSamples) {
          _ended = true;
          return SpeechPhase.ended;
        }
      }
    }

    return _phase();
  }

  SpeechPhase _phase() {
    if (_ended) return SpeechPhase.ended;
    if (_threshold == null) return SpeechPhase.calibrating;
    return _sawSpeech ? SpeechPhase.speaking : SpeechPhase.waitingForSpeech;
  }
}
