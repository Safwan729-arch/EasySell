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

  test(
    'sort is exercised: ascending-order input still resolves to highest',
    () {
      // Pass candidates in ascending order (low to high). The sort must reorder
      // them and correctly identify the winner.
      final d = decideVoiceLine([m('weak', 0.20), m('strong', 0.95)]);
      expect(d.status, VoiceLineStatus.resolved);
      expect(d.choices.single.productId, 'strong');
    },
  );

  test('sort is exercised: shuffled input still ranks correctly', () {
    // Pass candidates in random order. Ambiguous choices must be ranked
    // highest-first regardless of input order.
    final d = decideVoiceLine([
      m('third', 0.58),
      m('first', 0.60),
      m('second', 0.59),
    ], thresholds: const VoiceThresholds(maxChoices: 3));
    expect(d.status, VoiceLineStatus.ambiguous);
    expect(d.choices.map((c) => c.productId), ['first', 'second', 'third']);
  });

  test('exact boundary: top confidence exactly 0.80 with gap exactly 0.15', () {
    // 0.80 >= strong (0.80), 0.80 - 0.65 = 0.15 >= margin (0.15) → resolved.
    final d = decideVoiceLine([m('exact', 0.80), m('runner-up', 0.65)]);
    expect(d.status, VoiceLineStatus.resolved);
    expect(d.choices.single.productId, 'exact');
  });

  test('exact boundary: match at exactly 0.50 is offered as ambiguous', () {
    // Confidence exactly at ambiguous threshold → should appear as a choice.
    final d = decideVoiceLine([m('at-threshold', 0.50)]);
    expect(d.status, VoiceLineStatus.ambiguous);
    expect(d.choices.single.productId, 'at-threshold');
  });

  test(
    'tie: two identical confidences are ambiguous with a deterministic order',
    () {
      // Both at 0.70, gap = 0.70 - 0.70 = 0 < margin (0.15) → ambiguous.
      // List.sort is not stable, so equal-confidence candidates are ordered
      // by productId as a tiebreak, making the result deterministic regardless
      // of input order.
      final d = decideVoiceLine([m('tied-b', 0.70), m('tied-a', 0.70)]);
      expect(d.status, VoiceLineStatus.ambiguous);
      expect(d.choices, hasLength(2));
      expect(d.choices.map((c) => c.productId).toList(), ['tied-a', 'tied-b']);
    },
  );
}
