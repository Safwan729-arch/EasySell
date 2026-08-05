import 'dart:typed_data';

import 'package:ai_shopkeeper/core/config/theme.dart';
import 'package:ai_shopkeeper/core/error/result.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/inventory/presentation/inventory_controller.dart';
import 'package:ai_shopkeeper/features/voice/data/audio_recorder.dart';
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

class _FakeRepo implements VoiceSaleRepository {
  // Fire-and-forget optimization with no observable effect on parsing.
  @override
  Future<void> warmUp() async {}

  _FakeRepo(this.audio, this.text);
  final Result<VoiceParseResult> audio;
  final Result<VoiceParseResult> text;
  @override
  Future<Result<VoiceParseResult>> parse({
    required Uint8List audioBytes,
    required String audioMime,
    required List<Map<String, dynamic>> candidates,
  }) async => audio;
  @override
  Future<Result<VoiceParseResult>> parseTranscript({
    required String transcript,
    required List<Map<String, dynamic>> candidates,
  }) async => text;
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('editing the heard text re-parses and updates the lines', (tester) async {
    final audio = VoiceParseResult(
      heardText: 'pepci',
      items: [VoiceItem(heard: 'pepci', quantity: 1, quantityAssumed: true, matches: const [VoiceMatch(productId: 'p1', confidence: 0.4)])],
    );
    final text = VoiceParseResult(
      heardText: '2 pepsi',
      items: [VoiceItem(heard: 'pepsi', quantity: 2, quantityAssumed: false, matches: const [VoiceMatch(productId: 'p1', confidence: 0.95)])],
    );
    final container = ProviderContainer(
      overrides: [
        audioRecorderProvider.overrideWithValue(_FakeRecorder()),
        voiceSaleRepositoryProvider.overrideWithValue(_FakeRepo(Result.success(audio), Result.success(text))),
        productsStreamProvider.overrideWith(
          (ref) => Stream.value(const [Product(id: 'p1', shopId: 's', name: 'Pepsi 1L', quantity: 9)]),
        ),
      ],
    );
    final n = container.read(voiceControllerProvider.notifier);
    await n.startListening();
    await n.stopAndParse();

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
          home: const Scaffold(body: VoiceReviewSheet()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap the heard line to open the editor. Scoped to "I heard" (not just
    // "pepci") because the unsettled line below also renders its own
    // '"pepci"' text (the not-found row's raw heard text) -- a bare
    // `textContaining('pepci')` matches both and tap() rejects the ambiguity.
    await tester.tap(find.textContaining('I heard'));
    await tester.pumpAndSettle();

    // Replace the text and confirm.
    await tester.enterText(find.byType(TextField).last, '2 pepsi');
    await tester.tap(find.text('Re-check'));
    await tester.pumpAndSettle();

    // Lines rebuilt from the re-parse.
    expect(find.textContaining('2 pepsi'), findsWidgets);
    expect(container.read(voiceControllerProvider).lines.first.quantity, 2);
  });
}
