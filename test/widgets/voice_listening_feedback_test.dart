import 'dart:async';
import 'dart:typed_data';

import 'package:ai_shopkeeper/core/config/theme.dart';
import 'package:ai_shopkeeper/core/error/failure.dart';
import 'package:ai_shopkeeper/core/error/result.dart';
import 'package:ai_shopkeeper/features/inventory/presentation/inventory_controller.dart';
import 'package:ai_shopkeeper/features/voice/data/audio_recorder.dart';
import 'package:ai_shopkeeper/features/voice/data/voice_sale_repository.dart';
import 'package:ai_shopkeeper/features/voice/domain/voice_parse_result.dart';
import 'package:ai_shopkeeper/features/voice/presentation/voice_controller.dart';
import 'package:ai_shopkeeper/features/voice/presentation/voice_sale_sheet.dart';
import 'package:ai_shopkeeper/features/transactions/presentation/sales_providers.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:ai_shopkeeper/shared/providers/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

class _FakeRecorder implements AudioRecorderPort {
  final levelController = StreamController<double>.broadcast();

  @override
  Stream<double> get levels => levelController.stream;

  @override
  Future<bool> hasPermission() async => true;
  @override
  Future<void> start() async {}
  @override
  Future<({Uint8List bytes, String mime})?> stop() async =>
      (bytes: Uint8List.fromList(const [1]), mime: 'audio/m4a');
  @override
  Future<void> cancel() async {}
  @override
  Future<void> dispose() async => levelController.close();
}

/// Fails the first audio parse (like a noisy-room timeout) and succeeds after,
/// so the "retry the same recording" path can be exercised end to end.
class _FlakyRepo implements VoiceSaleRepository {
  // Fire-and-forget optimization with no observable effect on parsing.
  @override
  Future<void> warmUp() async {}

  _FlakyRepo(this.success);

  final Result<VoiceParseResult> success;
  int audioCalls = 0;
  final audioBytesSeen = <Uint8List>[];

  @override
  Future<Result<VoiceParseResult>> parse({
    required Uint8List audioBytes,
    required String audioMime,
    required List<Map<String, dynamic>> candidates,
  }) async {
    audioBytesSeen.add(audioBytes);
    return ++audioCalls == 1
        ? const Result<VoiceParseResult>.failure(
            DatabaseFailure(
              'Could not understand that right now. Please try again.',
            ),
          )
        : success;
  }

  @override
  Future<Result<VoiceParseResult>> parseTranscript({
    required String transcript,
    required List<Map<String, dynamic>> candidates,
  }) async => success;
}

ProviderContainer _container({
  required AudioRecorderPort recorder,
  required VoiceSaleRepository repo,
  Duration cap = const Duration(seconds: 15),
  bool online = true,
}) {
  final container = ProviderContainer(
    overrides: [
      audioRecorderProvider.overrideWithValue(recorder),
      voiceSaleRepositoryProvider.overrideWithValue(repo),
      productsStreamProvider.overrideWith((ref) => Stream.value(const [])),
      recentUnitsSoldProvider.overrideWith((ref) => const <String, double>{}),
      voiceOnlineProvider.overrideWithValue(online),
      maxRecordingDurationProvider.overrideWithValue(cap),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Ends the recording inside the test body so the duration-cap Timer does not
/// outlive it -- exactly what `showVoiceSaleSheet`'s `whenComplete` does when
/// the sheet is dismissed mid-recording. Must be called in the body, not an
/// `addTearDown`: the binding's pending-timer assertion runs before teardowns.
Future<void> _endRecording(
  WidgetTester tester,
  ProviderContainer container,
) async {
  container.read(voiceControllerProvider.notifier).reset();
  await tester.pump();
}

Future<void> _pumpSheet(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('en'),
        supportedLocales: supportedAppLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const Scaffold(body: VoiceSaleSheet()),
      ),
    ),
  );
  await tester.pump();
}

final _oneLine = VoiceParseResult(
  heardText: '2 pepsi',
  items: [
    VoiceItem(
      heard: 'pepsi',
      quantity: 2,
      quantityAssumed: false,
      matches: const [VoiceMatch(productId: 'p1', confidence: 0.95)],
    ),
  ],
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('mic level meter', () {
    testWidgets('reflects what the microphone is actually hearing', (
      tester,
    ) async {
      final recorder = _FakeRecorder();
      final container = _container(
        recorder: recorder,
        repo: _FlakyRepo(Result.success(_oneLine)),
      );

      await container.read(voiceControllerProvider.notifier).startListening();
      await _pumpSheet(tester, container);

      // A silent room lights no bars.
      expect(container.read(micLevelProvider), 0);

      recorder.levelController.add(-10); // loud, clear speech
      await tester.pump();

      expect(container.read(micLevelProvider), greaterThan(0.7));

      recorder.levelController.add(-160); // digital silence
      await tester.pump();

      expect(container.read(micLevelProvider), 0);
      await _endRecording(tester, container);
    });

    testWidgets('warns the shopkeeper when nothing is reaching the mic', (
      tester,
    ) async {
      final recorder = _FakeRecorder();
      final container = _container(
        recorder: recorder,
        repo: _FlakyRepo(Result.success(_oneLine)),
      );

      await container.read(voiceControllerProvider.notifier).startListening();
      await _pumpSheet(tester, container);

      // Nothing yet: people take a beat before speaking, and an instant nag
      // would be noise.
      expect(find.textContaining('hold the phone closer'), findsNothing);

      await tester.pump(const Duration(seconds: 3));

      expect(find.textContaining('hold the phone closer'), findsOneWidget);
      await _endRecording(tester, container);
    });

    testWidgets('does not warn once real speech has been heard', (
      tester,
    ) async {
      final recorder = _FakeRecorder();
      final container = _container(
        recorder: recorder,
        repo: _FlakyRepo(Result.success(_oneLine)),
      );

      await container.read(voiceControllerProvider.notifier).startListening();
      await _pumpSheet(tester, container);

      recorder.levelController.add(-12);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));

      expect(find.textContaining('hold the phone closer'), findsNothing);
      await _endRecording(tester, container);
    });
  });

  group('auto-stop countdown', () {
    testWidgets('stays hidden for most of the recording, then counts down', (
      tester,
    ) async {
      final recorder = _FakeRecorder();
      final container = _container(
        recorder: recorder,
        repo: _FlakyRepo(Result.success(_oneLine)),
        cap: const Duration(seconds: 15),
      );

      await container.read(voiceControllerProvider.notifier).startListening();
      await _pumpSheet(tester, container);

      expect(find.textContaining('Stopping in'), findsNothing);

      // Into the warning window (15s cap, 5s warning).
      await tester.pump(const Duration(seconds: 11));
      expect(find.text('Stopping in 4s'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Stopping in 2s'), findsOneWidget);

      // Let the cap itself fire so no timer outlives the test.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });
  });

  group('retrying a failed parse', () {
    testWidgets('re-sends the same recording instead of making the shopkeeper '
        'say the sale again', (tester) async {
      final recorder = _FakeRecorder();
      final repo = _FlakyRepo(Result.success(_oneLine));
      final container = _container(recorder: recorder, repo: repo);
      final notifier = container.read(voiceControllerProvider.notifier);

      await notifier.startListening();
      await notifier.stopAndParse();
      await _pumpSheet(tester, container);

      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Record again'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(repo.audioCalls, 2);
      expect(repo.audioBytesSeen.first, repo.audioBytesSeen.last);
      expect(
        container.read(voiceControllerProvider).phase,
        VoicePhase.reviewing,
      );
    });

    testWidgets('offers only a fresh recording when nothing was captured', (
      tester,
    ) async {
      final recorder = _FakeRecorder();
      final container = _container(
        recorder: recorder,
        repo: _FlakyRepo(Result.success(_oneLine)),
        online: false,
      );

      await container.read(voiceControllerProvider.notifier).startListening();
      await _pumpSheet(tester, container);

      expect(find.textContaining("You're offline"), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      // There is no audio to re-send, so no second, confusing choice.
      expect(find.text('Record again'), findsNothing);
      await _endRecording(tester, container);
    });
  });
}
