import 'package:ai_shopkeeper/core/config/theme.dart';
import 'package:ai_shopkeeper/core/error/result.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/inventory/presentation/inventory_controller.dart';
import 'package:ai_shopkeeper/features/voice/data/speech_recognizer.dart';
import 'package:ai_shopkeeper/features/voice/data/voice_sale_repository.dart';
import 'package:ai_shopkeeper/features/voice/domain/voice_parse_result.dart';
import 'package:ai_shopkeeper/features/voice/presentation/voice_controller.dart';
import 'package:ai_shopkeeper/features/voice/presentation/voice_review_sheet.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:ai_shopkeeper/shared/providers/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// Fake recognizer that hands [transcript] straight to `onResult` as a final
/// result the instant `start()` is called, so `startListening()` leaves the
/// controller with a ready-to-parse transcript without any manual `emit`
/// plumbing. Trimmed from `test/voice_controller_test.dart`'s version to just
/// what this harness needs.
class _FakeRecognizer implements SpeechRecognizerPort {
  _FakeRecognizer(this.transcript);
  final String transcript;

  @override
  Future<bool> initialize() async => true;

  @override
  Future<void> start({
    required String localeId,
    required void Function(String text, bool isFinal) onResult,
  }) async => onResult(transcript, true);

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async {}
}

/// Fake repository: `implements` (not `extends`) so the real
/// [VoiceSaleRepository]'s private Supabase client field never needs
/// constructing -- same trick `test/voice_controller_test.dart` uses.
class _FakeVoiceRepo implements VoiceSaleRepository {
  _FakeVoiceRepo(this._result);
  final Result<VoiceParseResult> _result;

  @override
  Future<Result<VoiceParseResult>> parse({
    required String transcript,
    required List<Map<String, dynamic>> candidates,
  }) async => _result;
}

Product _p(String id, {required String name}) =>
    Product(id: id, shopId: 's', name: name, quantity: 10);

/// Wires a container for the voice feature (fake recognizer + repository,
/// fake products stream) and drives the REAL [VoiceController] through
/// `startListening` -> `stopAndParse`, landing on `reviewing` with exactly
/// the lines [parsed] produces. Widget tests then pump [VoiceReviewSheet]
/// against this container, so they exercise real state transitions rather
/// than a mocked controller.
Future<ProviderContainer> _reviewingContainer({
  String transcript = 'sold something',
  required VoiceParseResult parsed,
  List<Product> products = const [],
}) async {
  final container = ProviderContainer(
    overrides: [
      speechRecognizerProvider.overrideWithValue(_FakeRecognizer(transcript)),
      voiceSaleRepositoryProvider.overrideWithValue(
        _FakeVoiceRepo(Result.success(parsed)),
      ),
      productsStreamProvider.overrideWith((ref) => Stream.value(products)),
    ],
  );
  final notifier = container.read(voiceControllerProvider.notifier);
  await notifier.startListening();
  await notifier.stopAndParse();
  return container;
}

Widget _harness(ProviderContainer container) => UncontrolledProviderScope(
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
    home: const Scaffold(body: VoiceReviewSheet()),
  ),
);

bool _addToCartEnabled(WidgetTester tester) =>
    tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed !=
    null;

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('Add to cart is disabled while a line is unsettled', (
    tester,
  ) async {
    final parsed = VoiceParseResult(
      items: [
        VoiceItem(
          heard: 'pepsi',
          quantity: 2,
          quantityAssumed: false,
          matches: const [VoiceMatch(productId: 'p1', confidence: 0.93)],
        ),
        VoiceItem(
          heard: 'cola',
          quantity: 1,
          quantityAssumed: false,
          matches: const [
            VoiceMatch(productId: 'p2', confidence: 0.6),
            VoiceMatch(productId: 'p3', confidence: 0.55),
          ],
        ),
      ],
    );
    final container = await _reviewingContainer(
      parsed: parsed,
      products: [
        _p('p1', name: 'Pepsi 500ml'),
        _p('p2', name: 'Cola A'),
        _p('p3', name: 'Cola B'),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container));
    await tester.pumpAndSettle();

    // One resolved line (p1) plus one still-ambiguous line (p2/p3) must keep
    // the button disabled.
    expect(_addToCartEnabled(tester), isFalse);
  });

  testWidgets('choosing a candidate settles the line and enables the button', (
    tester,
  ) async {
    final parsed = VoiceParseResult(
      items: [
        VoiceItem(
          heard: 'pepsi',
          quantity: 1,
          quantityAssumed: true,
          matches: const [
            VoiceMatch(productId: 'p1', confidence: 0.6),
            VoiceMatch(productId: 'p2', confidence: 0.55),
          ],
        ),
      ],
    );
    final container = await _reviewingContainer(
      parsed: parsed,
      products: [
        _p('p1', name: 'Pepsi 500ml'),
        _p('p2', name: 'Pepsi 1L'),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container));
    await tester.pumpAndSettle();

    expect(_addToCartEnabled(tester), isFalse);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Pepsi 1L'));
    await tester.pumpAndSettle();

    expect(_addToCartEnabled(tester), isTrue);
    expect(
      container.read(voiceControllerProvider).lines.single.chosenProductId,
      'p2',
    );
  });

  testWidgets('removing a not-found line unblocks the rest', (tester) async {
    final parsed = VoiceParseResult(
      items: [
        VoiceItem(
          heard: 'pepsi',
          quantity: 2,
          quantityAssumed: false,
          matches: const [VoiceMatch(productId: 'p1', confidence: 0.93)],
        ),
        VoiceItem(
          heard: 'something weird',
          quantity: 1,
          quantityAssumed: false,
          matches: const [],
        ),
      ],
    );
    final container = await _reviewingContainer(
      parsed: parsed,
      products: [_p('p1', name: 'Pepsi 500ml')],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container));
    await tester.pumpAndSettle();

    expect(_addToCartEnabled(tester), isFalse);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(_addToCartEnabled(tester), isTrue);
    expect(container.read(voiceControllerProvider).lines, hasLength(1));
  });

  testWidgets('assumed-quantity caption shows only for quantityAssumed lines', (
    tester,
  ) async {
    final parsed = VoiceParseResult(
      items: [
        VoiceItem(
          heard: 'pepsi',
          quantity: 1,
          quantityAssumed: true,
          matches: const [VoiceMatch(productId: 'p1', confidence: 0.95)],
        ),
        VoiceItem(
          heard: 'cola',
          quantity: 3,
          quantityAssumed: false,
          matches: const [VoiceMatch(productId: 'p2', confidence: 0.95)],
        ),
      ],
    );
    final container = await _reviewingContainer(
      parsed: parsed,
      products: [
        _p('p1', name: 'Pepsi 500ml'),
        _p('p2', name: 'Cola'),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container));
    await tester.pumpAndSettle();

    expect(find.text('Assumed 1 — check this'), findsOneWidget);
  });

  testWidgets('the transcript renders', (tester) async {
    final parsed = VoiceParseResult(
      items: [
        VoiceItem(
          heard: 'pepsi',
          quantity: 2,
          quantityAssumed: false,
          matches: const [VoiceMatch(productId: 'p1', confidence: 0.93)],
        ),
      ],
    );
    final container = await _reviewingContainer(
      transcript: 'sold 2 pepsi',
      parsed: parsed,
      products: [_p('p1', name: 'Pepsi 500ml')],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container));
    await tester.pumpAndSettle();

    expect(find.textContaining('sold 2 pepsi'), findsOneWidget);
  });
}
