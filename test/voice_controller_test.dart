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

  @override
  Future<bool> hasPermission() async => permissionOk;

  @override
  Future<void> start() async {
    if (throwOnStart) throw Exception('mic busy');
    started = true;
  }

  @override
  Future<({Uint8List bytes, String mime})?> stop() async {
    if (throwOnStop) throw Exception('stop failed');
    stopped = true;
    return stopResult;
  }

  @override
  Future<void> cancel() async => cancelled = true;

  @override
  Future<void> dispose() async {}
}

/// Fake repository: `implements` (not `extends`) so the private `_client`
/// field of the real [VoiceSaleRepository] never needs constructing. Also
/// records the last audio it was called with, for tests that need to assert
/// what was actually sent to `parse-sale`.
class _FakeVoiceRepo implements VoiceSaleRepository {
  _FakeVoiceRepo(this._result);
  final Result<VoiceParseResult> _result;
  Uint8List? lastAudioBytes;
  String? lastAudioMime;

  @override
  Future<Result<VoiceParseResult>> parse({
    required Uint8List audioBytes,
    required String audioMime,
    required List<Map<String, dynamic>> candidates,
  }) async {
    lastAudioBytes = audioBytes;
    lastAudioMime = audioMime;
    return _result;
  }
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

ProviderContainer _makeContainer({
  required AudioRecorderPort recorder,
  required VoiceSaleRepository repo,
  List<Product> products = const [],
}) {
  final container = ProviderContainer(
    overrides: [
      audioRecorderProvider.overrideWithValue(recorder),
      voiceSaleRepositoryProvider.overrideWithValue(repo),
      productsStreamProvider.overrideWith((ref) => Stream.value(products)),
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
  });
}
