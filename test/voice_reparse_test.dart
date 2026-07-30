import 'dart:typed_data';

import 'package:ai_shopkeeper/core/error/result.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/inventory/presentation/inventory_controller.dart';
import 'package:ai_shopkeeper/features/voice/data/audio_recorder.dart';
import 'package:ai_shopkeeper/features/voice/data/voice_sale_repository.dart';
import 'package:ai_shopkeeper/features/voice/domain/voice_parse_result.dart';
import 'package:ai_shopkeeper/features/voice/presentation/voice_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
  _FakeRepo(this.audioResult, this.textResult);
  final Result<VoiceParseResult> audioResult;
  final Result<VoiceParseResult> textResult;
  @override
  Future<Result<VoiceParseResult>> parse({
    required Uint8List audioBytes,
    required String audioMime,
    required List<Map<String, dynamic>> candidates,
  }) async => audioResult;
  @override
  Future<Result<VoiceParseResult>> parseTranscript({
    required String transcript,
    required List<Map<String, dynamic>> candidates,
  }) async => textResult;
}

void main() {
  test('reparseFromText replaces lines and heardText from the edited text', () async {
    final audio = VoiceParseResult(
      heardText: 'pepci',
      items: [VoiceItem(heard: 'pepci', quantity: 1, quantityAssumed: true, matches: const [])],
    );
    final text = VoiceParseResult(
      heardText: '2 pepsi',
      items: [
        VoiceItem(
          heard: 'pepsi', quantity: 2, quantityAssumed: false,
          matches: const [VoiceMatch(productId: 'p1', confidence: 0.9)],
        ),
      ],
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
    await n.stopAndParse(); // now reviewing with the (mis-heard) audio result

    await n.reparseFromText('2 pepsi');

    final state = container.read(voiceControllerProvider);
    expect(state.phase, VoicePhase.reviewing);
    expect(state.heardText, '2 pepsi');
    expect(state.lines.length, 1);
    expect(state.lines.first.quantity, 2);
  });

  test('reparseFromText ignores empty input', () async {
    final container = ProviderContainer(
      overrides: [
        audioRecorderProvider.overrideWithValue(_FakeRecorder()),
        voiceSaleRepositoryProvider.overrideWithValue(
          _FakeRepo(Result.success(const VoiceParseResult(items: [])), Result.success(const VoiceParseResult(items: []))),
        ),
        productsStreamProvider.overrideWith((ref) => Stream.value(const <Product>[])),
      ],
    );
    final n = container.read(voiceControllerProvider.notifier);
    await n.reparseFromText('   ');
    expect(container.read(voiceControllerProvider).phase, VoicePhase.idle);
  });
}
