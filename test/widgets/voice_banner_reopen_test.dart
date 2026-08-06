import 'dart:async';
import 'dart:typed_data';

import 'package:ai_shopkeeper/core/config/theme.dart';
import 'package:ai_shopkeeper/core/error/result.dart';
import 'package:ai_shopkeeper/core/router/app_router.dart';
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
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

/// Mounts the banner exactly the way `app.dart` does -- inside
/// `MaterialApp.router`'s `builder`, which sits ABOVE the router's Navigator.
///
/// `voice_ready_banner_test.dart` puts it under a plain `MaterialApp(home:)`,
/// which supplies a Navigator ancestor the real app does not have, so the tap
/// path it exercises is not the one that ships.

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

Widget _app(ProviderContainer container, {bool wireNavigatorKey = true}) {
  final router = GoRouter(
    // As in `app_router.dart`: the banner's only route to a Navigator.
    navigatorKey: wireNavigatorKey ? rootNavigatorKey : null,
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Center(child: Text('home'))),
      ),
    ],
  );
  addTearDown(router.dispose);
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      theme: AppTheme.light,
      locale: const Locale('en'),
      supportedLocales: supportedAppLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
      // Verbatim shape of app.dart's builder: banner above, screen below.
      builder: (context, child) => Column(
        children: [
          const VoiceReadyBanner(),
          Expanded(child: child!),
        ],
      ),
    ),
  );
}

/// Speaks a sale, backgrounds it, and lets it finish -- leaving the banner in
/// its "ready, tap me" state.
Future<void> _readyInBanner(
  WidgetTester tester,
  ProviderContainer container,
  _PendingRepo repo,
) async {
  final notifier = container.read(voiceControllerProvider.notifier);
  await notifier.startListening();
  unawaited(notifier.stopAndParse());
  for (var i = 0; i < 10 && !repo.parseCalled; i++) {
    await tester.pump();
  }
  notifier.releaseSheet();
  repo.completer.complete(const Result.success(_parsed));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('tapping the ready banner opens the cart, not nothing', (
    tester,
  ) async {
    final repo = _PendingRepo();
    final container = _container(repo);
    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    await _readyInBanner(tester, container, repo);

    expect(find.text('Your voice sale is ready'), findsOneWidget);

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();

    expect(
      tester.takeException(),
      isNull,
      reason: 'the banner must be able to reach a Navigator',
    );
    expect(
      find.text('Speak a sale'),
      findsOneWidget,
      reason: 'the review sheet is the whole point of tapping the banner',
    );
  });

  testWidgets('a tap that cannot open the sheet does not eat the sale', (
    tester,
  ) async {
    // The visible half of the original bug: claiming the sale ran first, so the
    // banner disappeared even though the sheet never opened, leaving a parsed
    // cart with nothing on screen pointing at it. Whatever goes wrong, the
    // handle has to survive a tap that achieved nothing.
    final repo = _PendingRepo();
    final container = _container(repo);
    await tester.pumpWidget(_app(container, wireNavigatorKey: false));
    await tester.pumpAndSettle();

    await _readyInBanner(tester, container, repo);
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(container.read(voiceControllerProvider).background, isTrue);
    expect(find.text('Your voice sale is ready'), findsOneWidget);
  });
}
