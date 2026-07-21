import 'package:flutter_test/flutter_test.dart';
import 'package:ai_shopkeeper/features/voice/domain/voice_decision.dart';
import 'package:ai_shopkeeper/features/voice/domain/voice_parse_result.dart';

VoiceMatch m(String id, double c) => VoiceMatch(productId: id, confidence: c);

void main() {
  test('a clear winner resolves to that product', () {
    // "pepsi 1 litre" -> 1L is far ahead.
    final d = decideVoiceLine([m('1L', 0.95), m('500ml', 0.20)]);
    expect(d.status, VoiceLineStatus.resolved);
    expect(d.choices.single.productId, '1L');
  });

  test('two near-identical scores are a coin flip and must ask', () {
    // "pepsi 1 piece" with both variants in stock -> ask, never guess.
    final d = decideVoiceLine([m('500ml', 0.55), m('1L', 0.52)]);
    expect(d.status, VoiceLineStatus.ambiguous);
    expect(d.choices.map((c) => c.productId), containsAll(['500ml', '1L']));
  });

  test('high confidence without a clear lead still asks', () {
    final d = decideVoiceLine([m('a', 0.91), m('b', 0.88)]);
    expect(d.status, VoiceLineStatus.ambiguous);
  });

  test('no matches at all is notFound', () {
    final d = decideVoiceLine([]);
    expect(d.status, VoiceLineStatus.notFound);
    expect(d.choices, isEmpty);
  });

  test('only weak matches is notFound', () {
    final d = decideVoiceLine([m('a', 0.30), m('b', 0.10)]);
    expect(d.status, VoiceLineStatus.notFound);
  });

  test('a lone match above the strong bar resolves', () {
    final d = decideVoiceLine([m('a', 0.84)]);
    expect(d.status, VoiceLineStatus.resolved);
  });

  test('a lone weak-but-plausible match asks rather than resolving', () {
    final d = decideVoiceLine([m('a', 0.60)]);
    expect(d.status, VoiceLineStatus.ambiguous);
  });

  test('choices are ranked and capped', () {
    final d = decideVoiceLine([
      m('a', 0.60),
      m('b', 0.59),
      m('c', 0.58),
      m('d', 0.57),
      m('e', 0.56),
      m('f', 0.55),
    ], thresholds: const VoiceThresholds(maxChoices: 3));
    expect(d.choices, hasLength(3));
    expect(d.choices.first.productId, 'a');
  });
}
