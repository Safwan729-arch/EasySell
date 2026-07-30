import 'dart:typed_data';

import 'package:ai_shopkeeper/core/config/theme.dart';
import 'package:ai_shopkeeper/core/error/failure.dart';
import 'package:ai_shopkeeper/core/error/result.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/inventory/presentation/inventory_controller.dart';
import 'package:ai_shopkeeper/features/voice/data/audio_recorder.dart';
import 'package:ai_shopkeeper/features/voice/data/voice_sale_repository.dart';
import 'package:ai_shopkeeper/features/voice/domain/voice_parse_result.dart';
import 'package:ai_shopkeeper/features/voice/presentation/voice_controller.dart';
import 'package:ai_shopkeeper/features/voice/presentation/voice_sale_sheet.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:ai_shopkeeper/shared/providers/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

class _FakeRecorder implements AudioRecorderPort {
  @override
  Stream<double> get levels => const Stream<double>.empty();
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
  Future<void> dispose() async {}
}

/// Audio parse fails the way a noisy-room timeout does; the typed text path
/// then succeeds.
class _FakeRepo implements VoiceSaleRepository {
  _FakeRepo(this.text);
  final Result<VoiceParseResult> text;

  @override
  Future<Result<VoiceParseResult>> parse({
    required Uint8List audioBytes,
    required String audioMime,
    required List<Map<String, dynamic>> candidates,
  }) async => const Result<VoiceParseResult>.failure(
    DatabaseFailure('Could not understand that right now. Please try again.'),
  );

  @override
  Future<Result<VoiceParseResult>> parseTranscript({
    required String transcript,
    required List<Map<String, dynamic>> candidates,
  }) async => text;
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('the error pane can recover by typing the sale instead', (
    tester,
  ) async {
    final typed = VoiceParseResult(
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
    final container = ProviderContainer(
      overrides: [
        audioRecorderProvider.overrideWithValue(_FakeRecorder()),
        voiceSaleRepositoryProvider.overrideWithValue(
          _FakeRepo(Result.success(typed)),
        ),
        productsStreamProvider.overrideWith(
          (ref) => Stream.value(const [
            Product(id: 'p1', shopId: 's', name: 'Pepsi 1L', quantity: 9),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);

    final n = container.read(voiceControllerProvider.notifier);
    await n.startListening();
    await n.stopAndParse();
    expect(container.read(voiceControllerProvider).phase, VoicePhase.error);

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
    await tester.pumpAndSettle();

    await tester.tap(find.text('Type it instead'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, '2 pepsi');
    await tester.tap(find.text('Re-check'));
    await tester.pumpAndSettle();

    final state = container.read(voiceControllerProvider);
    expect(state.phase, VoicePhase.reviewing);
    expect(state.lines, hasLength(1));
    expect(state.lines.single.quantity, 2);
  });
}
