import 'dart:async';
import 'dart:typed_data';

import 'package:ai_shopkeeper/core/error/failure.dart';
import 'package:ai_shopkeeper/core/error/result.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/inventory/presentation/inventory_controller.dart';
import 'package:ai_shopkeeper/features/transactions/presentation/sales_providers.dart';
import 'package:ai_shopkeeper/features/voice/data/audio_recorder.dart';
import 'package:ai_shopkeeper/features/voice/data/voice_sale_repository.dart';
import 'package:ai_shopkeeper/features/voice/domain/voice_parse_result.dart';
import 'package:ai_shopkeeper/features/voice/presentation/voice_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers letting a slow parse finish after its sheet is gone.
///
/// The point of the feature is that a shopkeeper can speak a sale, close the
/// sheet, and go back to serving the customer while the parse runs. So the
/// behaviour worth pinning down is precisely that dismissal does NOT cancel the
/// work -- the old `whenComplete(reset)` did exactly that, and reinstating it
/// would silently throw away a sale the shopkeeper had already spoken.

final _recording = (
  bytes: Uint8List.fromList(const [1, 2, 3]),
  mime: 'audio/m4a',
);

class _FakeRecorder implements AudioRecorderPort {
  final _levels = StreamController<double>.broadcast();
  bool cancelled = false;

  @override
  Stream<double> get levels => _levels.stream;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> start() async {}

  @override
  Future<({Uint8List bytes, String mime})?> stop() async => _recording;

  @override
  Future<void> cancel() async => cancelled = true;

  @override
  Future<void> dispose() async => _levels.close();
}

/// A repository whose parse never resolves until the test says so, so the
/// controller can be held in `thinking` across a sheet dismissal.
class _PendingRepo implements VoiceSaleRepository {
  final completer = Completer<Result<VoiceParseResult>>();
  bool parseCalled = false;
  int warmUpCalls = 0;

  @override
  Future<void> warmUp() async => warmUpCalls++;

  @override
  Future<Result<VoiceParseResult>> parse({
    required Uint8List audioBytes,
    required String audioMime,
    required List<Map<String, dynamic>> candidates,
  }) {
    parseCalled = true;
    return completer.future;
  }

  @override
  Future<Result<VoiceParseResult>> parseTranscript({
    required String transcript,
    required List<Map<String, dynamic>> candidates,
  }) {
    parseCalled = true;
    return completer.future;
  }
}

class _FakeHaptics extends VoiceHaptics {
  const _FakeHaptics(this.log);

  final List<String> log;

  @override
  void recordingStarted() => log.add('start');

  @override
  void recordingStopped() => log.add('stop');

  @override
  void resultReady() => log.add('ready');
}

ProviderContainer _container({
  required AudioRecorderPort recorder,
  required VoiceSaleRepository repo,
  required List<String> hapticLog,
}) {
  final container = ProviderContainer(
    overrides: [
      audioRecorderProvider.overrideWithValue(recorder),
      voiceSaleRepositoryProvider.overrideWithValue(repo),
      productsStreamProvider.overrideWith(
        (ref) =>
            Stream.value([const Product(id: 'p1', shopId: 's', name: 'Pepsi')]),
      ),
      voiceOnlineProvider.overrideWithValue(true),
      recentUnitsSoldProvider.overrideWith((ref) => const <String, double>{}),
      autoStopOnSilenceProvider.overrideWithValue(false),
      voiceHapticsProvider.overrideWithValue(_FakeHaptics(hapticLog)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Runs the controller up to the point where `parse` is genuinely in flight.
Future<VoiceController> _upToThinking(
  ProviderContainer container,
  _PendingRepo repo,
) async {
  final notifier = container.read(voiceControllerProvider.notifier);
  await notifier.startListening();
  // Deliberately NOT awaited: `stopAndParse` only completes once the parse
  // does, and holding it pending across the dismissal is the whole scenario.
  unawaited(notifier.stopAndParse());
  while (!repo.parseCalled) {
    await Future<void>.delayed(Duration.zero);
  }
  return notifier;
}

const _parsed = VoiceParseResult(
  heardText: 'two pepsi',
  items: [
    VoiceItem(
      heard: 'pepsi',
      quantity: 2,
      quantityAssumed: false,
      matches: [VoiceMatch(productId: 'p1', confidence: 0.95)],
    ),
  ],
);

void main() {
  test('dismissing the sheet mid-parse keeps the parse running', () async {
    final repo = _PendingRepo();
    final log = <String>[];
    final container = _container(
      recorder: _FakeRecorder(),
      repo: repo,
      hapticLog: log,
    );
    final notifier = await _upToThinking(container, repo);
    expect(container.read(voiceControllerProvider).phase, VoicePhase.thinking);

    // The shopkeeper swipes the sheet away to serve the customer.
    notifier.releaseSheet();
    expect(
      container.read(voiceControllerProvider).phase,
      VoicePhase.thinking,
      reason: 'dismissal must not cancel a sale already spoken',
    );
    expect(container.read(voiceControllerProvider).background, isTrue);

    // The result lands with nobody watching.
    repo.completer.complete(const Result.success(_parsed));
    await Future<void>.delayed(Duration.zero);

    final state = container.read(voiceControllerProvider);
    expect(state.phase, VoicePhase.reviewing);
    expect(state.lines, hasLength(1));
    expect(state.hasBackgroundResult, isTrue);
    expect(log, contains('ready'), reason: 'the buzz is the only notification');
  });

  test('a failed background parse still asks to be claimed', () async {
    final repo = _PendingRepo();
    final log = <String>[];
    final container = _container(
      recorder: _FakeRecorder(),
      repo: repo,
      hapticLog: log,
    );
    final notifier = await _upToThinking(container, repo);
    notifier.releaseSheet();

    repo.completer.complete(
      const Result.failure(NetworkFailure('no internet')),
    );
    await Future<void>.delayed(Duration.zero);

    final state = container.read(voiceControllerProvider);
    expect(state.phase, VoicePhase.error);
    expect(state.hasBackgroundResult, isTrue);
    expect(log, contains('ready'));
  });

  test('dismissing outside the thinking phase still resets', () async {
    final repo = _PendingRepo();
    final recorder = _FakeRecorder();
    final container = _container(recorder: recorder, repo: repo, hapticLog: []);
    final notifier = container.read(voiceControllerProvider.notifier);
    await notifier.startListening();
    expect(container.read(voiceControllerProvider).phase, VoicePhase.listening);

    notifier.releaseSheet();

    final state = container.read(voiceControllerProvider);
    expect(state.phase, VoicePhase.idle);
    expect(state.background, isFalse);
    expect(recorder.cancelled, isTrue, reason: 'a live mic must be released');
  });

  test(
    'resuming from the banner clears the flag but keeps the lines',
    () async {
      final repo = _PendingRepo();
      final container = _container(
        recorder: _FakeRecorder(),
        repo: repo,
        hapticLog: [],
      );
      final notifier = await _upToThinking(container, repo);
      notifier.releaseSheet();
      repo.completer.complete(const Result.success(_parsed));
      await Future<void>.delayed(Duration.zero);

      notifier.resumeFromBackground();

      final state = container.read(voiceControllerProvider);
      expect(state.background, isFalse);
      expect(state.hasBackgroundResult, isFalse);
      expect(state.phase, VoicePhase.reviewing);
      expect(state.lines, hasLength(1), reason: 'the parsed sale must survive');
    },
  );

  test('starting a new sale clears a stale background flag', () async {
    final repo = _PendingRepo();
    final container = _container(
      recorder: _FakeRecorder(),
      repo: repo,
      hapticLog: [],
    );
    final notifier = await _upToThinking(container, repo);
    notifier.releaseSheet();
    repo.completer.complete(const Result.success(_parsed));
    await Future<void>.delayed(Duration.zero);
    expect(container.read(voiceControllerProvider).background, isTrue);

    await notifier.startListening();

    expect(
      container.read(voiceControllerProvider).background,
      isFalse,
      reason: 'the banner must not linger over a fresh recording',
    );
  });

  test('recording start warms the Edge Function', () async {
    final repo = _PendingRepo();
    final container = _container(
      recorder: _FakeRecorder(),
      repo: repo,
      hapticLog: [],
    );
    await container.read(voiceControllerProvider.notifier).startListening();
    await Future<void>.delayed(Duration.zero);

    expect(
      repo.warmUpCalls,
      1,
      reason: 'the cold start must overlap the seconds spent speaking',
    );
  });
}
