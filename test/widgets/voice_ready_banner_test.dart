import 'dart:async';
import 'dart:typed_data';

import 'package:ai_shopkeeper/core/config/theme.dart';
import 'package:ai_shopkeeper/core/error/failure.dart';
import 'package:ai_shopkeeper/core/error/result.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/inventory/presentation/inventory_controller.dart';
import 'package:ai_shopkeeper/features/transactions/presentation/sales_providers.dart';
import 'package:ai_shopkeeper/features/voice/data/audio_recorder.dart';
import 'package:ai_shopkeeper/features/voice/data/voice_sale_repository.dart';
import 'package:ai_shopkeeper/features/voice/domain/voice_parse_result.dart';
import 'package:ai_shopkeeper/features/voice/presentation/voice_controller.dart';
import 'package:ai_shopkeeper/features/voice/presentation/voice_ready_banner.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:ai_shopkeeper/shared/providers/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// The banner is the only route back to a voice sale whose sheet was dismissed
/// mid-parse, so "it appears exactly when a result is waiting, and tapping it
/// reopens the sheet" is the whole contract.

class _FakeRecorder implements AudioRecorderPort {
  @override
  Stream<double> get levels => const Stream<double>.empty();

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> start() async {}

  @override
  Future<({Uint8List bytes, String mime})?> stop() async =>
      (bytes: Uint8List.fromList(const [1, 2, 3]), mime: 'audio/m4a');

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}

class _PendingRepo implements VoiceSaleRepository {
  final completer = Completer<Result<VoiceParseResult>>();
  bool parseCalled = false;

  @override
  Future<void> warmUp() async {}

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

ProviderContainer _container(VoiceSaleRepository repo) {
  final container = ProviderContainer(
    overrides: [
      audioRecorderProvider.overrideWithValue(_FakeRecorder()),
      voiceSaleRepositoryProvider.overrideWithValue(repo),
      productsStreamProvider.overrideWith(
        (ref) =>
            Stream.value([const Product(id: 'p1', shopId: 's', name: 'Pepsi')]),
      ),
      voiceOnlineProvider.overrideWithValue(true),
      recentUnitsSoldProvider.overrideWith((ref) => const <String, double>{}),
      autoStopOnSilenceProvider.overrideWithValue(false),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Mirrors `app.dart`: the banner sits above the routed screen, so the tap
/// handler has to reach a Navigator that lives *below* it.
Widget _app(ProviderContainer container) => UncontrolledProviderScope(
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
    home: const Scaffold(
      body: Column(
        children: [
          VoiceReadyBanner(),
          Expanded(child: SizedBox()),
        ],
      ),
    ),
  ),
);

/// Drives a sale to a finished-but-unclaimed state: spoken, sheet dismissed,
/// result landed.
Future<void> _backgroundResult(
  WidgetTester tester,
  ProviderContainer container,
  _PendingRepo repo, {
  required Result<VoiceParseResult> result,
}) async {
  final notifier = container.read(voiceControllerProvider.notifier);
  await notifier.startListening();
  // Not awaited: `stopAndParse` only completes when the parse does, and the
  // dismissal has to happen while it is still pending.
  unawaited(notifier.stopAndParse());
  // `tester.pump()`, not `Future.delayed`: inside `testWidgets` time is fake,
  // so a bare delay would never fire and this would spin forever. Bounded so a
  // regression fails the expectation below instead of hanging the suite.
  for (var i = 0; i < 10 && !repo.parseCalled; i++) {
    await tester.pump();
  }
  expect(repo.parseCalled, isTrue, reason: 'parse must be genuinely in flight');

  notifier.releaseSheet();
  repo.completer.complete(result);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('nothing is shown while no result is waiting', (tester) async {
    final container = _container(_PendingRepo());
    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    expect(find.text('Your voice sale is ready'), findsNothing);
    expect(find.byKey(const ValueKey('voice-ready-banner')), findsNothing);
  });

  testWidgets('a finished background sale offers itself for review', (
    tester,
  ) async {
    final repo = _PendingRepo();
    final container = _container(repo);
    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    await _backgroundResult(
      tester,
      container,
      repo,
      result: const Result.success(_parsed),
    );

    expect(find.text('Your voice sale is ready'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
  });

  testWidgets('a failed background sale is not dressed up as good news', (
    tester,
  ) async {
    final repo = _PendingRepo();
    final container = _container(repo);
    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    await _backgroundResult(
      tester,
      container,
      repo,
      result: const Result.failure(NetworkFailure('no internet')),
    );

    expect(find.text('Your voice sale needs a look'), findsOneWidget);
    expect(find.text('Your voice sale is ready'), findsNothing);
  });

  testWidgets('tapping reopens the sheet and dismisses the banner', (
    tester,
  ) async {
    final repo = _PendingRepo();
    final container = _container(repo);
    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    await _backgroundResult(
      tester,
      container,
      repo,
      result: const Result.success(_parsed),
    );

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();

    // The review step is on screen...
    expect(find.text('Speak a sale'), findsOneWidget);
    // ...so the offer to open it must be gone.
    expect(container.read(voiceControllerProvider).background, isFalse);
    expect(find.text('Your voice sale is ready'), findsNothing);
  });
}
