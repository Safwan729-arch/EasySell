import 'dart:async';
import 'dart:typed_data';

import 'package:ai_shopkeeper/core/error/failure.dart';
import 'package:ai_shopkeeper/core/error/result.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/inventory/presentation/inventory_controller.dart';
import 'package:ai_shopkeeper/features/voice/data/audio_recorder.dart';
import 'package:ai_shopkeeper/features/voice/data/voice_sale_repository.dart';
import 'package:ai_shopkeeper/features/voice/domain/voice_parse_result.dart';
import 'package:ai_shopkeeper/features/voice/presentation/voice_controller.dart';
import 'package:ai_shopkeeper/shared/providers/connectivity_provider.dart';
import 'package:ai_shopkeeper/features/transactions/presentation/sales_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The bytes/mime a recorder hands back on a successful `stop()` -- reused as
/// the default `stopResult` below so most tests don't need to think about it.
final _defaultRecording = (
  bytes: Uint8List.fromList(const [1, 2, 3]),
  mime: 'audio/m4a',
);

/// Sentinel distinguishing "the caller didn't pass `stopResult`" from
/// "the caller explicitly passed `null`" -- `stopResult: null ?? default`
/// would silently discard an intentional null (the "nothing captured" case),
/// so a plain `??` default can't be used here.
const _unset = Object();

/// Fake recorder: records which calls it received and hands back a
/// configurable `stop()` result (including `null`, for "nothing captured").
class _FakeAudioRecorder implements AudioRecorderPort {
  _FakeAudioRecorder({
    this.permissionOk = true,
    Object? stopResult = _unset,
    this.throwOnStart = false,
    this.throwOnStop = false,
  }) : stopResult = identical(stopResult, _unset)
           ? _defaultRecording
           : stopResult as ({Uint8List bytes, String mime})?;

  final bool permissionOk;
  final bool throwOnStart;
  final bool throwOnStop;
  ({Uint8List bytes, String mime})? stopResult;
  bool started = false;
  bool stopped = false;
  bool cancelled = false;
  int stopCalls = 0;

  /// Drives [levels] so tests can feed exact dBFS runs to the controller's
  /// silence detection without a microphone.
  final levelController = StreamController<double>.broadcast();

  @override
  Stream<double> get levels => levelController.stream;

  /// Pushes [samples] and lets each one be delivered before the next.
  Future<void> emitLevels(List<double> samples) async {
    for (final s in samples) {
      levelController.add(s);
      await Future<void>.delayed(Duration.zero);
    }
  }

  @override
  Future<bool> hasPermission() async => permissionOk;

  @override
  Future<void> start() async {
    if (throwOnStart) throw Exception('mic busy');
    started = true;
  }

  @override
  Future<({Uint8List bytes, String mime})?> stop() async {
    stopCalls++;
    if (throwOnStop) throw Exception('stop failed');
    stopped = true;
    return stopResult;
  }

  @override
  Future<void> cancel() async => cancelled = true;

  @override
  Future<void> dispose() async {
    await levelController.close();
  }
}

/// A run of dBFS samples shaped like a real sentence in a quiet-ish room: one
/// second of room tone to calibrate on, speech, then enough trailing silence to
/// satisfy [SpeechEndDetector]'s default window.
List<double> _sentenceThenSilence() => [
  ...List<double>.filled(5, -40),
  ...List<double>.filled(8, -12),
  ...List<double>.filled(6, -40),
];

/// Fake repository: `implements` (not `extends`) so the private `_client`
/// field of the real [VoiceSaleRepository] never needs constructing. Also
/// records the last audio it was called with, for tests that need to assert
/// what was actually sent to `parse-sale`.
class _FakeVoiceRepo implements VoiceSaleRepository {
  _FakeVoiceRepo(this._result, {Result<VoiceParseResult>? transcriptResult})
    : _transcriptResult = transcriptResult ?? _result;
  final Result<VoiceParseResult> _result;
  final Result<VoiceParseResult> _transcriptResult;
  Uint8List? lastAudioBytes;
  String? lastAudioMime;
  String? lastTranscript;
  List<Map<String, dynamic>>? lastCandidates;

  @override
  Future<Result<VoiceParseResult>> parse({
    required Uint8List audioBytes,
    required String audioMime,
    required List<Map<String, dynamic>> candidates,
  }) async {
    lastAudioBytes = audioBytes;
    lastAudioMime = audioMime;
    lastCandidates = candidates;
    return _result;
  }

  @override
  Future<Result<VoiceParseResult>> parseTranscript({
    required String transcript,
    required List<Map<String, dynamic>> candidates,
  }) async {
    lastTranscript = transcript;
    lastCandidates = candidates;
    return _transcriptResult;
  }
}

/// Fails the first audio parse and succeeds on the second, so a retry can be
/// distinguished from a first attempt. Counts audio calls to prove the retry
/// went over the wire rather than being served from stale state.
class _RetryVoiceRepo implements VoiceSaleRepository {
  _RetryVoiceRepo(this._first, this._rest);

  final Result<VoiceParseResult> _first;
  final Result<VoiceParseResult> _rest;
  int audioCalls = 0;
  Uint8List? lastAudioBytes;

  @override
  Future<Result<VoiceParseResult>> parse({
    required Uint8List audioBytes,
    required String audioMime,
    required List<Map<String, dynamic>> candidates,
  }) async {
    lastAudioBytes = audioBytes;
    return ++audioCalls == 1 ? _first : _rest;
  }

  @override
  Future<Result<VoiceParseResult>> parseTranscript({
    required String transcript,
    required List<Map<String, dynamic>> candidates,
  }) async => _rest;
}

/// A repository whose `parse` hangs until the test explicitly resolves
/// [completer] -- used to simulate a parse still in flight when the user
/// resets or starts a new session. [called] flips true the instant `parse`
/// is invoked, so a test can pump the event loop until the controller has
/// actually reached the in-flight call (not merely scheduled it).
class _PendingVoiceRepo implements VoiceSaleRepository {
  final completer = Completer<Result<VoiceParseResult>>();
  bool called = false;

  @override
  Future<Result<VoiceParseResult>> parse({
    required Uint8List audioBytes,
    required String audioMime,
    required List<Map<String, dynamic>> candidates,
  }) {
    called = true;
    return completer.future;
  }

  @override
  Future<Result<VoiceParseResult>> parseTranscript({
    required String transcript,
    required List<Map<String, dynamic>> candidates,
  }) {
    called = true;
    return completer.future;
  }
}

/// Pumps the microtask queue until [repo]'s `parse` has actually been
/// invoked -- i.e. the controller is genuinely mid-flight (phase `thinking`),
/// not merely somewhere in `recorder.stop()`.
Future<void> _untilParseCalled(_PendingVoiceRepo repo) async {
  while (!repo.called) {
    await Future<void>.delayed(Duration.zero);
  }
}

Product _product(String id) =>
    Product(id: id, shopId: 's', name: 'Product $id');

/// Counts haptic calls instead of hitting the platform channel, so the tests
/// can assert the buzzes fire at the right moments.
class _FakeHaptics extends VoiceHaptics {
  const _FakeHaptics(this.log);

  final List<String> log;

  @override
  void recordingStarted() => log.add('start');

  @override
  void recordingStopped() => log.add('stop');
}

ProviderContainer _makeContainer({
  required AudioRecorderPort recorder,
  required VoiceSaleRepository repo,
  List<Product> products = const [],
  Duration? maxRecordingDuration,
  bool online = true,
  Map<String, double> recentUnits = const {},
  bool autoStopOnSilence = true,
  List<String>? hapticLog,
}) {
  final container = ProviderContainer(
    overrides: [
      audioRecorderProvider.overrideWithValue(recorder),
      voiceSaleRepositoryProvider.overrideWithValue(repo),
      productsStreamProvider.overrideWith((ref) => Stream.value(products)),
      voiceOnlineProvider.overrideWithValue(online),
      recentUnitsSoldProvider.overrideWith((ref) => recentUnits),
      autoStopOnSilenceProvider.overrideWithValue(autoStopOnSilence),
      voiceHapticsProvider.overrideWithValue(_FakeHaptics(hapticLog ?? [])),
      if (maxRecordingDuration != null)
        maxRecordingDurationProvider.overrideWithValue(maxRecordingDuration),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('VoiceController', () {
    test('startListening: mic denied -> error micDenied', () async {
      final recorder = _FakeAudioRecorder(permissionOk: false);
      final c = _makeContainer(
        recorder: recorder,
        repo: _FakeVoiceRepo(const Result.success(VoiceParseResult())),
      );

      await c.read(voiceControllerProvider.notifier).startListening();

      final state = c.read(voiceControllerProvider);
      expect(state.phase, VoicePhase.error);
      expect(state.errorMessage, 'micDenied');
      expect(recorder.started, isFalse);
    });

    test('startListening: permission granted -> phase listening and the '
        'recorder is started', () async {
      final recorder = _FakeAudioRecorder();
      final c = _makeContainer(
        recorder: recorder,
        repo: _FakeVoiceRepo(const Result.success(VoiceParseResult())),
      );

      await c.read(voiceControllerProvider.notifier).startListening();

      expect(c.read(voiceControllerProvider).phase, VoicePhase.listening);
      expect(recorder.started, isTrue);
    });

    test('startListening: recorder.start() throws -> error noSpeech and the '
        'recorder is not left started', () async {
      final recorder = _FakeAudioRecorder(throwOnStart: true);
      final c = _makeContainer(
        recorder: recorder,
        repo: _FakeVoiceRepo(const Result.success(VoiceParseResult())),
      );

      await c.read(voiceControllerProvider.notifier).startListening();

      final state = c.read(voiceControllerProvider);
      expect(state.phase, VoicePhase.error);
      expect(state.errorMessage, 'noSpeech');
      expect(recorder.started, isFalse);
    });

    test('stopAndParse: recorder.stop() throws -> error noSpeech and parse is '
        'never called', () async {
      final recorder = _FakeAudioRecorder(throwOnStop: true);
      final repo = _FakeVoiceRepo(const Result.success(VoiceParseResult()));
      final c = _makeContainer(recorder: recorder, repo: repo);

      await c.read(voiceControllerProvider.notifier).startListening();
      await c.read(voiceControllerProvider.notifier).stopAndParse();

      final state = c.read(voiceControllerProvider);
      expect(state.phase, VoicePhase.error);
      expect(state.errorMessage, 'noSpeech');
      expect(repo.lastAudioBytes, isNull);
    });

    test('stopAndParse: recorder captured nothing -> error noSpeech', () async {
      final recorder = _FakeAudioRecorder(stopResult: null);
      final c = _makeContainer(
        recorder: recorder,
        repo: _FakeVoiceRepo(const Result.success(VoiceParseResult())),
      );

      await c.read(voiceControllerProvider.notifier).startListening();
      await c.read(voiceControllerProvider.notifier).stopAndParse();

      final state = c.read(voiceControllerProvider);
      expect(state.phase, VoicePhase.error);
      expect(state.errorMessage, 'noSpeech');
      expect(recorder.stopped, isTrue);
    });

    test('stopAndParse happy path: reviewing with lines and a clear winner is '
        'addable', () async {
      final recorder = _FakeAudioRecorder();
      final parsed = VoiceParseResult(
        heardText: 'sold 2 pepsi',
        items: [
          VoiceItem(
            heard: 'pepsi',
            quantity: 2,
            quantityAssumed: false,
            matches: const [VoiceMatch(productId: 'p1', confidence: 0.93)],
          ),
        ],
      );
      final repo = _FakeVoiceRepo(Result.success(parsed));
      final c = _makeContainer(
        recorder: recorder,
        repo: repo,
        products: [_product('p1')],
      );

      await c.read(voiceControllerProvider.notifier).startListening();
      await c.read(voiceControllerProvider.notifier).stopAndParse();

      final state = c.read(voiceControllerProvider);
      expect(state.phase, VoicePhase.reviewing);
      expect(state.heardText, 'sold 2 pepsi');
      expect(state.lines, hasLength(1));
      expect(state.lines.single.chosenProductId, 'p1');
      expect(state.canAdd, isTrue);
      expect(state.errorMessage, isNull);
      // The exact bytes/mime the recorder captured must be what's shipped.
      expect(repo.lastAudioBytes, recorder.stopResult!.bytes);
      expect(repo.lastAudioMime, recorder.stopResult!.mime);
    });

    test('stopAndParse: zero lines -> error noMatch', () async {
      final recorder = _FakeAudioRecorder();
      final c = _makeContainer(
        recorder: recorder,
        repo: _FakeVoiceRepo(const Result.success(VoiceParseResult(items: []))),
      );

      await c.read(voiceControllerProvider.notifier).startListening();
      await c.read(voiceControllerProvider.notifier).stopAndParse();

      final state = c.read(voiceControllerProvider);
      expect(state.phase, VoicePhase.error);
      expect(state.errorMessage, 'noMatch');
      expect(state.lines, isEmpty);
    });

    test(
      'stopAndParse: repository failure surfaces the failure message',
      () async {
        final recorder = _FakeAudioRecorder();
        const failure = NetworkFailure(
          'No internet connection. Please try again.',
        );
        final c = _makeContainer(
          recorder: recorder,
          repo: _FakeVoiceRepo(const Result.failure(failure)),
        );

        await c.read(voiceControllerProvider.notifier).startListening();
        await c.read(voiceControllerProvider.notifier).stopAndParse();

        final state = c.read(voiceControllerProvider);
        expect(state.phase, VoicePhase.error);
        expect(state.errorMessage, failure.message);
      },
    );

    test('choose/setQuantity/removeLine mutate the right line; reset returns '
        'to idle empty state and cancels the recorder', () async {
      final recorder = _FakeAudioRecorder();
      final parsed = VoiceParseResult(
        items: [
          VoiceItem(
            heard: 'pepsi',
            quantity: 1,
            quantityAssumed: true,
            matches: const [
              VoiceMatch(productId: 'p1', confidence: 0.55),
              VoiceMatch(productId: 'p2', confidence: 0.52),
            ],
          ),
        ],
      );
      final c = _makeContainer(
        recorder: recorder,
        repo: _FakeVoiceRepo(Result.success(parsed)),
        products: [_product('p1'), _product('p2')],
      );

      await c.read(voiceControllerProvider.notifier).startListening();
      await c.read(voiceControllerProvider.notifier).stopAndParse();

      // A coin flip arrives unsettled -- the gate must block adding.
      expect(c.read(voiceControllerProvider).canAdd, isFalse);

      final notifier = c.read(voiceControllerProvider.notifier);

      notifier.choose(0, 'p2');
      expect(
        c.read(voiceControllerProvider).lines.single.chosenProductId,
        'p2',
      );
      expect(c.read(voiceControllerProvider).canAdd, isTrue);

      notifier.setQuantity(0, 5);
      expect(c.read(voiceControllerProvider).lines.single.quantity, 5);

      notifier.removeLine(0);
      expect(c.read(voiceControllerProvider).lines, isEmpty);

      notifier.reset();
      final state = c.read(voiceControllerProvider);
      expect(state.phase, VoicePhase.idle);
      expect(state.lines, isEmpty);
      expect(state.heardText, isNull);
      expect(state.errorMessage, isNull);
      expect(recorder.cancelled, isTrue);
    });

    test('reset() during an in-flight parse discards the stale result -- final '
        'state stays idle/empty', () async {
      final recorder = _FakeAudioRecorder();
      final repo = _PendingVoiceRepo();
      final c = _makeContainer(recorder: recorder, repo: repo);
      final notifier = c.read(voiceControllerProvider.notifier);

      await notifier.startListening();
      final pending = notifier.stopAndParse(); // not awaited: parse hangs
      await _untilParseCalled(repo); // genuinely mid-flight now
      expect(c.read(voiceControllerProvider).phase, VoicePhase.thinking);

      notifier.reset();
      expect(c.read(voiceControllerProvider).phase, VoicePhase.idle);
      expect(recorder.cancelled, isTrue);

      // Resolve the stale parse only now -- after reset() already moved on.
      repo.completer.complete(
        Result.success(
          VoiceParseResult(
            items: [
              VoiceItem(
                heard: 'pepsi',
                quantity: 2,
                quantityAssumed: false,
                matches: const [VoiceMatch(productId: 'p1', confidence: 0.93)],
              ),
            ],
          ),
        ),
      );
      await pending;

      final state = c.read(voiceControllerProvider);
      expect(state.phase, VoicePhase.idle);
      expect(state.lines, isEmpty);
      expect(state.errorMessage, isNull);
    });

    test(
      'startListening() for a new session while an old parse is in flight: '
      'the old result is discarded and the new session is unaffected',
      () async {
        final recorder = _FakeAudioRecorder();
        final repo = _PendingVoiceRepo();
        final c = _makeContainer(recorder: recorder, repo: repo);
        final notifier = c.read(voiceControllerProvider.notifier);

        await notifier.startListening();
        final pending = notifier.stopAndParse(); // session 1, hangs
        await _untilParseCalled(repo); // genuinely mid-flight now

        // The user starts over before the first parse ever resolves.
        await notifier.startListening();
        expect(c.read(voiceControllerProvider).phase, VoicePhase.listening);

        // Now let the stale (session 1) parse resolve.
        repo.completer.complete(
          Result.success(
            VoiceParseResult(
              items: [
                VoiceItem(
                  heard: 'pepsi',
                  quantity: 2,
                  quantityAssumed: false,
                  matches: const [
                    VoiceMatch(productId: 'p1', confidence: 0.93),
                  ],
                ),
              ],
            ),
          ),
        );
        await pending;

        // The new (session 2) listening state must be untouched by it.
        final state = c.read(voiceControllerProvider);
        expect(state.phase, VoicePhase.listening);
        expect(state.lines, isEmpty);
        expect(state.errorMessage, isNull);
      },
    );

    test('stopAndParse() when not listening is a no-op', () async {
      final recorder = _FakeAudioRecorder();
      final c = _makeContainer(
        recorder: recorder,
        repo: _FakeVoiceRepo(const Result.success(VoiceParseResult())),
      );

      final before = c.read(voiceControllerProvider);
      await c.read(voiceControllerProvider.notifier).stopAndParse();

      expect(c.read(voiceControllerProvider).phase, before.phase);
      expect(c.read(voiceControllerProvider).phase, VoicePhase.idle);
      expect(recorder.stopped, isFalse);
    });

    test(
      'recording auto-stops and parses once the duration cap elapses',
      () async {
        final recorder = _FakeAudioRecorder();
        final parsed = VoiceParseResult(
          heardText: 'sold 2 pepsi',
          items: [
            VoiceItem(
              heard: 'pepsi',
              quantity: 2,
              quantityAssumed: false,
              matches: const [VoiceMatch(productId: 'p1', confidence: 0.93)],
            ),
          ],
        );
        final c = _makeContainer(
          recorder: recorder,
          repo: _FakeVoiceRepo(Result.success(parsed)),
          products: [_product('p1')],
          maxRecordingDuration: const Duration(milliseconds: 20),
        );

        await c.read(voiceControllerProvider.notifier).startListening();
        expect(c.read(voiceControllerProvider).phase, VoicePhase.listening);

        await Future<void>.delayed(const Duration(milliseconds: 120));

        expect(recorder.stopped, isTrue);
        expect(c.read(voiceControllerProvider).phase, VoicePhase.reviewing);
        expect(c.read(voiceControllerProvider).lines, hasLength(1));
      },
    );

    test('startListening: offline -> error offline, and the mic is never even '
        'opened', () async {
      final recorder = _FakeAudioRecorder();
      final repo = _FakeVoiceRepo(const Result.success(VoiceParseResult()));
      final c = _makeContainer(recorder: recorder, repo: repo, online: false);

      await c.read(voiceControllerProvider.notifier).startListening();

      final state = c.read(voiceControllerProvider);
      expect(state.phase, VoicePhase.error);
      expect(state.errorMessage, 'offline');
      // The whole point: no 15 seconds of talking before finding out.
      expect(recorder.started, isFalse);
      expect(state.canRetryAudio, isFalse);
    });

    test('voiceOnlineProvider fails open while connectivity is still loading, '
        'so a slow plugin never blocks a sale', () async {
      final c = ProviderContainer(
        overrides: [
          // Resolves only after the read below, so the read sees AsyncLoading.
          isOnlineProvider.overrideWith(
            (ref) => Stream.value(false).asBroadcastStream(),
          ),
        ],
      );
      addTearDown(c.dispose);
      final sub = c.listen(voiceOnlineProvider, (_, _) {});
      addTearDown(sub.close);

      expect(c.read(voiceOnlineProvider), isTrue);

      // Once a real reading arrives it is respected.
      await c.read(isOnlineProvider.future);
      expect(c.read(voiceOnlineProvider), isFalse);
    });

    test(
      'haptics fire when recording actually starts and when it stops',
      () async {
        final log = <String>[];
        final recorder = _FakeAudioRecorder();
        final c = _makeContainer(
          recorder: recorder,
          repo: _FakeVoiceRepo(const Result.success(VoiceParseResult())),
          hapticLog: log,
        );
        final notifier = c.read(voiceControllerProvider.notifier);

        await notifier.startListening();
        expect(log, ['start']);
        await notifier.stopAndParse();
        expect(log, ['start', 'stop']);
      },
    );

    test('no start haptic when the mic fails to open -- a buzz would promise '
        'recording that never began', () async {
      final log = <String>[];
      final c = _makeContainer(
        recorder: _FakeAudioRecorder(throwOnStart: true),
        repo: _FakeVoiceRepo(const Result.success(VoiceParseResult())),
        hapticLog: log,
      );

      await c.read(voiceControllerProvider.notifier).startListening();

      expect(log, isEmpty);
    });

    test('listening exposes a deadline matching the duration cap', () async {
      final c = _makeContainer(
        recorder: _FakeAudioRecorder(),
        repo: _FakeVoiceRepo(const Result.success(VoiceParseResult())),
        maxRecordingDuration: const Duration(seconds: 15),
      );

      final before = DateTime.now();
      await c.read(voiceControllerProvider.notifier).startListening();
      final deadline = c.read(voiceControllerProvider).listenDeadline;

      expect(deadline, isNotNull);
      expect(
        deadline!.difference(before).inMilliseconds,
        // Set from `now` after start() resolved, so at least the full cap.
        allOf(greaterThanOrEqualTo(15000), lessThan(17000)),
      );
    });

    test(
      'the deadline clears once recording ends, so no countdown can linger',
      () async {
        final c = _makeContainer(
          recorder: _FakeAudioRecorder(),
          repo: _FakeVoiceRepo(const Result.success(VoiceParseResult())),
        );
        final notifier = c.read(voiceControllerProvider.notifier);

        await notifier.startListening();
        expect(c.read(voiceControllerProvider).listenDeadline, isNotNull);
        await notifier.stopAndParse();
        expect(c.read(voiceControllerProvider).listenDeadline, isNull);
      },
    );

    test('a finished sentence auto-stops the recording without waiting for the '
        'duration cap', () async {
      final recorder = _FakeAudioRecorder();
      final parsed = VoiceParseResult(
        heardText: 'sold 2 pepsi',
        items: [
          VoiceItem(
            heard: 'pepsi',
            quantity: 2,
            quantityAssumed: false,
            matches: const [VoiceMatch(productId: 'p1', confidence: 0.93)],
          ),
        ],
      );
      final c = _makeContainer(
        recorder: recorder,
        repo: _FakeVoiceRepo(Result.success(parsed)),
        products: [_product('p1')],
        // Far longer than the test runs: only silence detection can stop this.
        maxRecordingDuration: const Duration(minutes: 5),
      );
      final notifier = c.read(voiceControllerProvider.notifier);

      await notifier.startListening();
      await recorder.emitLevels(_sentenceThenSilence());
      await Future<void>.delayed(Duration.zero);

      expect(recorder.stopped, isTrue);
      expect(c.read(voiceControllerProvider).phase, VoicePhase.reviewing);
    });

    test('continuous speech does not auto-stop', () async {
      final recorder = _FakeAudioRecorder();
      final c = _makeContainer(
        recorder: recorder,
        repo: _FakeVoiceRepo(const Result.success(VoiceParseResult())),
        maxRecordingDuration: const Duration(minutes: 5),
      );

      await c.read(voiceControllerProvider.notifier).startListening();
      await recorder.emitLevels([
        ...List<double>.filled(5, -40),
        ...List<double>.filled(40, -12),
      ]);

      expect(recorder.stopped, isFalse);
      expect(c.read(voiceControllerProvider).phase, VoicePhase.listening);
    });

    test('silence auto-stop fires stopAndParse exactly once even as more '
        'samples arrive', () async {
      final recorder = _FakeAudioRecorder();
      final c = _makeContainer(
        recorder: recorder,
        repo: _FakeVoiceRepo(const Result.success(VoiceParseResult())),
        maxRecordingDuration: const Duration(minutes: 5),
      );

      await c.read(voiceControllerProvider.notifier).startListening();
      await recorder.emitLevels([
        ..._sentenceThenSilence(),
        ...List<double>.filled(10, -40),
      ]);

      expect(recorder.stopCalls, 1);
    });

    test(
      'autoStopOnSilence off leaves the duration cap as the only stop',
      () async {
        final recorder = _FakeAudioRecorder();
        final c = _makeContainer(
          recorder: recorder,
          repo: _FakeVoiceRepo(const Result.success(VoiceParseResult())),
          maxRecordingDuration: const Duration(minutes: 5),
          autoStopOnSilence: false,
        );

        await c.read(voiceControllerProvider.notifier).startListening();
        await recorder.emitLevels(_sentenceThenSilence());

        expect(recorder.stopped, isFalse);
        expect(c.read(voiceControllerProvider).phase, VoicePhase.listening);
      },
    );

    test('a clip the mic never picked up fails fast as tooQuiet, without '
        'uploading anything', () async {
      final recorder = _FakeAudioRecorder();
      final repo = _FakeVoiceRepo(const Result.success(VoiceParseResult()));
      final c = _makeContainer(
        recorder: recorder,
        repo: repo,
        maxRecordingDuration: const Duration(minutes: 5),
      );
      final notifier = c.read(voiceControllerProvider.notifier);

      await notifier.startListening();
      // Digital silence throughout -- muted or covered microphone.
      await recorder.emitLevels(List<double>.filled(20, -160));
      await notifier.stopAndParse();

      final state = c.read(voiceControllerProvider);
      expect(state.phase, VoicePhase.error);
      expect(state.errorMessage, 'tooQuiet');
      expect(repo.lastAudioBytes, isNull);
      // Nothing worth keeping, so retry can only mean recording again.
      expect(state.canRetryAudio, isFalse);
    });

    test(
      'quiet speech over shop noise is still uploaded -- the silence gate is '
      'absolute, not relative to the room',
      () async {
        final recorder = _FakeAudioRecorder();
        final repo = _FakeVoiceRepo(const Result.success(VoiceParseResult()));
        final c = _makeContainer(
          recorder: recorder,
          repo: repo,
          maxRecordingDuration: const Duration(minutes: 5),
        );
        final notifier = c.read(voiceControllerProvider.notifier);

        await notifier.startListening();
        await recorder.emitLevels(List<double>.filled(10, -30));
        await notifier.stopAndParse();

        expect(repo.lastAudioBytes, isNotNull);
      },
    );

    test(
      'a platform that reports no levels at all never fails as tooQuiet',
      () async {
        final recorder = _FakeAudioRecorder();
        final repo = _FakeVoiceRepo(const Result.success(VoiceParseResult()));
        final c = _makeContainer(recorder: recorder, repo: repo);
        final notifier = c.read(voiceControllerProvider.notifier);

        await notifier.startListening(); // no emitLevels: iOS-style silence
        await notifier.stopAndParse();

        expect(repo.lastAudioBytes, isNotNull);
        expect(c.read(voiceControllerProvider).errorMessage, isNot('tooQuiet'));
      },
    );

    group('retryLastAudio', () {
      test('a parse failure offers retry, and retrying re-sends the same bytes '
          'without re-recording', () async {
        final recorder = _FakeAudioRecorder();
        final repo = _RetryVoiceRepo(
          const Result.failure(
            NetworkFailure('No internet connection. Please try again.'),
          ),
          Result.success(
            VoiceParseResult(
              heardText: 'sold 2 pepsi',
              items: [
                VoiceItem(
                  heard: 'pepsi',
                  quantity: 2,
                  quantityAssumed: false,
                  matches: const [
                    VoiceMatch(productId: 'p1', confidence: 0.93),
                  ],
                ),
              ],
            ),
          ),
        );
        final c = _makeContainer(
          recorder: recorder,
          repo: repo,
          products: [_product('p1')],
        );
        final notifier = c.read(voiceControllerProvider.notifier);

        await notifier.startListening();
        await notifier.stopAndParse();
        expect(c.read(voiceControllerProvider).phase, VoicePhase.error);
        expect(c.read(voiceControllerProvider).canRetryAudio, isTrue);

        await notifier.retryLastAudio();

        expect(c.read(voiceControllerProvider).phase, VoicePhase.reviewing);
        // The shopkeeper spoke once; the same audio went up twice.
        expect(recorder.stopCalls, 1);
        expect(repo.audioCalls, 2);
        expect(repo.lastAudioBytes, _defaultRecording.bytes);
      });

      test(
        'retryLastAudio with nothing kept falls back to a clean reset',
        () async {
          final recorder = _FakeAudioRecorder();
          final repo = _FakeVoiceRepo(const Result.success(VoiceParseResult()));
          final c = _makeContainer(recorder: recorder, repo: repo);
          final notifier = c.read(voiceControllerProvider.notifier);

          await notifier.retryLastAudio();

          expect(c.read(voiceControllerProvider).phase, VoicePhase.idle);
          expect(repo.lastAudioBytes, isNull);
        },
      );

      test('reset() discards the kept audio, so a later retry cannot resurrect '
          'a previous sale', () async {
        final recorder = _FakeAudioRecorder();
        final repo = _FakeVoiceRepo(
          const Result.failure(NetworkFailure('offline')),
        );
        final c = _makeContainer(recorder: recorder, repo: repo);
        final notifier = c.read(voiceControllerProvider.notifier);

        await notifier.startListening();
        await notifier.stopAndParse();
        expect(c.read(voiceControllerProvider).canRetryAudio, isTrue);

        notifier.reset();
        await notifier.retryLastAudio();

        expect(c.read(voiceControllerProvider).phase, VoicePhase.idle);
      });

      test('noMatch offers no audio retry -- the same bytes would produce the '
          'same answer', () async {
        final recorder = _FakeAudioRecorder();
        final repo = _FakeVoiceRepo(
          const Result.success(VoiceParseResult(items: [])),
        );
        final c = _makeContainer(recorder: recorder, repo: repo);
        final notifier = c.read(voiceControllerProvider.notifier);

        await notifier.startListening();
        await notifier.stopAndParse();

        final state = c.read(voiceControllerProvider);
        expect(state.errorMessage, 'noMatch');
        expect(state.canRetryAudio, isFalse);
      });

      test('the text path never offers an audio retry -- it would throw the '
          "shopkeeper's correction away", () async {
        final recorder = _FakeAudioRecorder();
        final repo = _FakeVoiceRepo(
          const Result.failure(NetworkFailure('offline')),
        );
        final c = _makeContainer(recorder: recorder, repo: repo);
        final notifier = c.read(voiceControllerProvider.notifier);

        await notifier.reparseFromText('2 pepsi');

        expect(c.read(voiceControllerProvider).phase, VoicePhase.error);
        expect(c.read(voiceControllerProvider).canRetryAudio, isFalse);
      });
    });

    test('recent sales volume reaches the candidate payload', () async {
      final recorder = _FakeAudioRecorder();
      final repo = _FakeVoiceRepo(const Result.success(VoiceParseResult()));
      final c = _makeContainer(
        recorder: recorder,
        repo: repo,
        products: [_product('p1'), _product('p2')],
        recentUnits: const {'p1': 42.0},
      );
      // Both feeds must have actually landed for this assertion to mean
      // anything: a StreamProvider only resolves while something listens, and
      // `_candidates()` deliberately reads `.value` rather than waiting.
      final sub = c.listen(productsStreamProvider, (_, _) {});
      addTearDown(sub.close);
      await c.read(productsStreamProvider.future);
      await c.read(recentUnitsSoldProvider.future);

      final notifier = c.read(voiceControllerProvider.notifier);
      await notifier.startListening();
      await notifier.stopAndParse();

      final byId = {for (final m in repo.lastCandidates!) m['id'] as String: m};
      expect(byId['p1']!['recent'], 42);
      // A product with no recent sales carries no hint at all.
      expect(byId['p2']!.containsKey('recent'), isFalse);
    });

    test(
      'reset() before the cap elapses stops the auto-stop from firing',
      () async {
        final recorder = _FakeAudioRecorder();
        final c = _makeContainer(
          recorder: recorder,
          repo: _FakeVoiceRepo(const Result.success(VoiceParseResult())),
          maxRecordingDuration: const Duration(milliseconds: 20),
        );
        final notifier = c.read(voiceControllerProvider.notifier);

        await notifier.startListening();
        notifier.reset();

        await Future<void>.delayed(const Duration(milliseconds: 120));

        // A stale timer firing into a fresh session would re-enter stopAndParse.
        expect(recorder.stopped, isFalse);
        expect(c.read(voiceControllerProvider).phase, VoicePhase.idle);
      },
    );
  });
}
