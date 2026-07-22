import 'dart:async';

import 'package:ai_shopkeeper/core/error/failure.dart';
import 'package:ai_shopkeeper/core/error/result.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/inventory/presentation/inventory_controller.dart';
import 'package:ai_shopkeeper/features/voice/data/speech_recognizer.dart';
import 'package:ai_shopkeeper/features/voice/data/voice_sale_repository.dart';
import 'package:ai_shopkeeper/features/voice/domain/voice_parse_result.dart';
import 'package:ai_shopkeeper/features/voice/presentation/voice_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake recognizer: `start` just records what it was called with and stashes
/// the callback so a test can fire partial/final results whenever it likes.
class _FakeRecognizer implements SpeechRecognizerPort {
  _FakeRecognizer({this.initOk = true});

  final bool initOk;
  String? capturedLocale;
  bool stopped = false;
  bool cancelled = false;
  void Function(String text, bool isFinal)? _onResult;

  @override
  Future<bool> initialize() async => initOk;

  @override
  Future<void> start({
    required String localeId,
    required void Function(String text, bool isFinal) onResult,
  }) async {
    capturedLocale = localeId;
    _onResult = onResult;
  }

  @override
  Future<void> stop() async => stopped = true;

  @override
  Future<void> cancel() async => cancelled = true;

  void emit(String text, {bool isFinal = false}) =>
      _onResult?.call(text, isFinal);
}

/// Fake repository: `implements` (not `extends`) so the private `_client`
/// field of the real [VoiceSaleRepository] never needs constructing. Also
/// records the last transcript it was called with, for tests that need to
/// assert what was actually sent to `parse-sale`.
class _FakeVoiceRepo implements VoiceSaleRepository {
  _FakeVoiceRepo(this._result);
  final Result<VoiceParseResult> _result;
  String? lastTranscript;

  @override
  Future<Result<VoiceParseResult>> parse({
    required String transcript,
    required List<Map<String, dynamic>> candidates,
  }) async {
    lastTranscript = transcript;
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
    required String transcript,
    required List<Map<String, dynamic>> candidates,
  }) {
    called = true;
    return completer.future;
  }
}

/// Pumps the microtask queue until [repo]'s `parse` has actually been
/// invoked -- i.e. the controller is genuinely mid-flight (phase `thinking`),
/// not merely somewhere in `recognizer.stop()`.
Future<void> _untilParseCalled(_PendingVoiceRepo repo) async {
  while (!repo.called) {
    await Future<void>.delayed(Duration.zero);
  }
}

Product _product(String id) =>
    Product(id: id, shopId: 's', name: 'Product $id');

ProviderContainer _makeContainer({
  required SpeechRecognizerPort recognizer,
  required VoiceSaleRepository repo,
  List<Product> products = const [],
}) {
  final container = ProviderContainer(
    overrides: [
      speechRecognizerProvider.overrideWithValue(recognizer),
      voiceSaleRepositoryProvider.overrideWithValue(repo),
      productsStreamProvider.overrideWith((ref) => Stream.value(products)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('recognizerLocaleFor', () {
    test('bn maps to bn_BD', () {
      expect(recognizerLocaleFor(const Locale('bn')), 'bn_BD');
    });

    test('en (and anything else) maps to en_US', () {
      expect(recognizerLocaleFor(const Locale('en')), 'en_US');
      expect(recognizerLocaleFor(const Locale('fr')), 'en_US');
    });
  });

  group('VoiceController', () {
    test('startListening: mic denied -> error micDenied', () async {
      final recognizer = _FakeRecognizer(initOk: false);
      final c = _makeContainer(
        recognizer: recognizer,
        repo: _FakeVoiceRepo(const Result.success(VoiceParseResult())),
      );

      await c.read(voiceControllerProvider.notifier).startListening();

      final state = c.read(voiceControllerProvider);
      expect(state.phase, VoicePhase.error);
      expect(state.errorMessage, 'micDenied');
    });

    test('partial results update liveTranscript while listening', () async {
      final recognizer = _FakeRecognizer();
      final c = _makeContainer(
        recognizer: recognizer,
        repo: _FakeVoiceRepo(const Result.success(VoiceParseResult())),
      );

      await c.read(voiceControllerProvider.notifier).startListening();
      expect(c.read(voiceControllerProvider).phase, VoicePhase.listening);
      expect(recognizer.capturedLocale, 'en_US');

      recognizer.emit('sold two');
      expect(c.read(voiceControllerProvider).liveTranscript, 'sold two');

      recognizer.emit('sold two pepsi', isFinal: true);
      expect(c.read(voiceControllerProvider).liveTranscript, 'sold two pepsi');
    });

    test(
      'stopAndParse: empty/whitespace transcript -> error noSpeech',
      () async {
        final recognizer = _FakeRecognizer();
        final c = _makeContainer(
          recognizer: recognizer,
          repo: _FakeVoiceRepo(const Result.success(VoiceParseResult())),
        );

        await c.read(voiceControllerProvider.notifier).startListening();
        recognizer.emit('   ');
        await c.read(voiceControllerProvider.notifier).stopAndParse();

        final state = c.read(voiceControllerProvider);
        expect(state.phase, VoicePhase.error);
        expect(state.errorMessage, 'noSpeech');
        expect(recognizer.stopped, isTrue);
      },
    );

    test('stopAndParse happy path: reviewing with lines and a clear winner is '
        'addable', () async {
      final recognizer = _FakeRecognizer();
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
        recognizer: recognizer,
        repo: _FakeVoiceRepo(Result.success(parsed)),
        products: [_product('p1')],
      );

      await c.read(voiceControllerProvider.notifier).startListening();
      recognizer.emit('sold 2 pepsi', isFinal: true);
      await c.read(voiceControllerProvider.notifier).stopAndParse();

      final state = c.read(voiceControllerProvider);
      expect(state.phase, VoicePhase.reviewing);
      expect(state.heardText, 'sold 2 pepsi');
      expect(state.lines, hasLength(1));
      expect(state.lines.single.chosenProductId, 'p1');
      expect(state.canAdd, isTrue);
      expect(state.errorMessage, isNull);
    });

    test('stopAndParse: zero lines -> error noMatch', () async {
      final recognizer = _FakeRecognizer();
      final c = _makeContainer(
        recognizer: recognizer,
        repo: _FakeVoiceRepo(const Result.success(VoiceParseResult(items: []))),
      );

      await c.read(voiceControllerProvider.notifier).startListening();
      recognizer.emit('gibberish', isFinal: true);
      await c.read(voiceControllerProvider.notifier).stopAndParse();

      final state = c.read(voiceControllerProvider);
      expect(state.phase, VoicePhase.error);
      expect(state.errorMessage, 'noMatch');
      expect(state.lines, isEmpty);
    });

    test(
      'stopAndParse: repository failure surfaces the failure message',
      () async {
        final recognizer = _FakeRecognizer();
        const failure = NetworkFailure(
          'No internet connection. Please try again.',
        );
        final c = _makeContainer(
          recognizer: recognizer,
          repo: _FakeVoiceRepo(const Result.failure(failure)),
        );

        await c.read(voiceControllerProvider.notifier).startListening();
        recognizer.emit('sold 2 pepsi', isFinal: true);
        await c.read(voiceControllerProvider.notifier).stopAndParse();

        final state = c.read(voiceControllerProvider);
        expect(state.phase, VoicePhase.error);
        expect(state.errorMessage, failure.message);
      },
    );

    test('choose/setQuantity/removeLine mutate the right line; reset returns '
        'to idle empty state', () async {
      final recognizer = _FakeRecognizer();
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
        recognizer: recognizer,
        repo: _FakeVoiceRepo(Result.success(parsed)),
        products: [_product('p1'), _product('p2')],
      );

      await c.read(voiceControllerProvider.notifier).startListening();
      recognizer.emit('pepsi', isFinal: true);
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
      expect(state.liveTranscript, isEmpty);
      expect(state.heardText, isNull);
      expect(state.errorMessage, isNull);
    });

    test('reset() during an in-flight parse discards the stale result -- final '
        'state stays idle/empty', () async {
      final recognizer = _FakeRecognizer();
      final repo = _PendingVoiceRepo();
      final c = _makeContainer(recognizer: recognizer, repo: repo);
      final notifier = c.read(voiceControllerProvider.notifier);

      await notifier.startListening();
      recognizer.emit('sold 2 pepsi', isFinal: true);
      final pending = notifier.stopAndParse(); // not awaited: parse hangs
      await _untilParseCalled(repo); // genuinely mid-flight now
      expect(c.read(voiceControllerProvider).phase, VoicePhase.thinking);

      notifier.reset();
      expect(c.read(voiceControllerProvider).phase, VoicePhase.idle);

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

    test('a late partial after reset() does not change state, and cancel() was '
        'called on the recognizer', () async {
      final recognizer = _FakeRecognizer();
      final c = _makeContainer(
        recognizer: recognizer,
        repo: _FakeVoiceRepo(const Result.success(VoiceParseResult())),
      );
      final notifier = c.read(voiceControllerProvider.notifier);

      await notifier.startListening();
      recognizer.emit('sold two');
      expect(c.read(voiceControllerProvider).liveTranscript, 'sold two');

      notifier.reset();
      expect(recognizer.cancelled, isTrue);

      // A partial from the dead session must be ignored.
      recognizer.emit('sold two pepsi');
      final state = c.read(voiceControllerProvider);
      expect(state.phase, VoicePhase.idle);
      expect(state.liveTranscript, isEmpty);
    });

    test(
      'startListening() for a new session while an old parse is in flight: '
      'the old result is discarded and the new session is unaffected',
      () async {
        final recognizer = _FakeRecognizer();
        final repo = _PendingVoiceRepo();
        final c = _makeContainer(recognizer: recognizer, repo: repo);
        final notifier = c.read(voiceControllerProvider.notifier);

        await notifier.startListening();
        recognizer.emit('sold 2 pepsi', isFinal: true);
        final pending = notifier.stopAndParse(); // session 1, hangs
        await _untilParseCalled(repo); // genuinely mid-flight now

        // The user starts over before the first parse ever resolves.
        await notifier.startListening();
        expect(c.read(voiceControllerProvider).phase, VoicePhase.listening);
        expect(c.read(voiceControllerProvider).liveTranscript, isEmpty);

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
      final recognizer = _FakeRecognizer();
      final c = _makeContainer(
        recognizer: recognizer,
        repo: _FakeVoiceRepo(const Result.success(VoiceParseResult())),
      );

      final before = c.read(voiceControllerProvider);
      await c.read(voiceControllerProvider.notifier).stopAndParse();

      expect(c.read(voiceControllerProvider).phase, before.phase);
      expect(c.read(voiceControllerProvider).phase, VoicePhase.idle);
      expect(recognizer.stopped, isFalse);
    });

    test(
      'an isFinal: true result updates the transcript actually sent to parse',
      () async {
        final recognizer = _FakeRecognizer();
        final repo = _FakeVoiceRepo(const Result.success(VoiceParseResult()));
        final c = _makeContainer(recognizer: recognizer, repo: repo);

        await c.read(voiceControllerProvider.notifier).startListening();
        recognizer.emit('sold two'); // partial
        recognizer.emit('sold two pepsi', isFinal: true); // final
        await c.read(voiceControllerProvider.notifier).stopAndParse();

        expect(repo.lastTranscript, 'sold two pepsi');
      },
    );
  });
}
