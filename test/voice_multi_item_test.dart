import 'package:ai_shopkeeper/features/voice/domain/voice_decision.dart';
import 'package:ai_shopkeeper/features/voice/domain/voice_line.dart';
import 'package:ai_shopkeeper/features/voice/domain/voice_parse_result.dart';
import 'package:flutter_test/flutter_test.dart';

/// Coverage for two things the voice path claims to support but that were never
/// asserted end to end: several items in one breath, and the fractional
/// quantities Bengali speakers use for weighed goods ("আড়াই কেজি" = 2.5 kg).
void main() {
  group('several items in one sentence', () {
    final result = VoiceParseResult.fromJson({
      'heard_text': 'two pepsi and a packet of biscuits and 3 kg rice',
      'items': [
        {
          'heard': 'pepsi',
          'quantity': 2,
          'matches': [
            {'product_id': 'pepsi-1l', 'confidence': 0.91},
          ],
        },
        {
          // No count spoken: "a packet of biscuits".
          'heard': 'biscuits',
          'matches': [
            {'product_id': 'biscuit-a', 'confidence': 0.62},
            {'product_id': 'biscuit-b', 'confidence': 0.58},
          ],
        },
        {
          'heard': 'rice',
          'quantity': 3,
          'matches': [
            {'product_id': 'unknown', 'confidence': 0.21},
          ],
        },
      ],
    });

    test('every spoken item becomes its own line, in order', () {
      expect(result.items, hasLength(3));
      expect(result.items.map((i) => i.heard), ['pepsi', 'biscuits', 'rice']);
    });

    test('each line is judged independently -- one ambiguity does not block '
        'the confident lines', () {
      final lines = buildVoiceLines(result);

      expect(lines, hasLength(3));
      expect(lines[0].status, VoiceLineStatus.resolved);
      expect(lines[0].chosenProductId, 'pepsi-1l');
      // Two plausible biscuits with no clear lead: the user must pick.
      expect(lines[1].status, VoiceLineStatus.ambiguous);
      expect(lines[1].chosenProductId, isNull);
      expect(lines[1].choices, hasLength(2));
      // Nothing in the shop plausibly matches.
      expect(lines[2].status, VoiceLineStatus.notFound);
      expect(lines[2].choices, isEmpty);
    });

    test('quantities stay attached to the right lines, including the assumed '
        'one', () {
      final lines = buildVoiceLines(result);

      expect(lines[0].quantity, 2);
      expect(lines[0].quantityAssumed, isFalse);
      expect(lines[1].quantity, 1);
      expect(lines[1].quantityAssumed, isTrue);
      expect(lines[2].quantity, 3);
    });

    test('a mixed-certainty sale cannot reach the cart until every line is '
        'settled', () {
      var lines = buildVoiceLines(result);
      expect(canAddToCart(lines), isFalse);

      // Drop the item the shop does not stock, then choose a biscuit.
      lines = removeLineAt(lines, 2);
      expect(canAddToCart(lines), isFalse);
      lines = [...lines]..[1] = lines[1].chooseProduct('biscuit-a');

      expect(canAddToCart(lines), isTrue);
    });
  });

  group('fractional quantities for weighed goods', () {
    /// "আড়াই কেজি চাল" -- two and a half kilos of rice.
    test('a half-kilo quantity survives parsing as a decimal', () {
      final r = VoiceParseResult.fromJson({
        'heard_text': 'আড়াই কেজি চাল',
        'items': [
          {
            'heard': 'চাল',
            'quantity': 2.5,
            'unit_heard': 'কেজি',
            'matches': [
              {'product_id': 'rice', 'confidence': 0.9},
            ],
          },
        ],
      });

      expect(r.items.single.quantity, 2.5);
      expect(r.items.single.quantityAssumed, isFalse);
      expect(r.items.single.unitHeard, 'কেজি');
    });

    test('a fractional quantity reaches the reviewable line unrounded', () {
      final lines = buildVoiceLines(
        VoiceParseResult.fromJson({
          'items': [
            {
              'heard': 'চাল',
              'quantity': 1.25,
              'matches': [
                {'product_id': 'rice', 'confidence': 0.95},
              ],
            },
          ],
        }),
      );

      expect(lines.single.quantity, 1.25);
      expect(lines.single.status, VoiceLineStatus.resolved);
      expect(canAddToCart(lines), isTrue);
    });

    test('editing a fractional quantity keeps it fractional and clears the '
        'assumed flag', () {
      final line = VoiceLine(
        heard: 'চাল',
        quantity: 1,
        quantityAssumed: true,
        status: VoiceLineStatus.resolved,
        choices: const [VoiceMatch(productId: 'rice', confidence: 0.95)],
        chosenProductId: 'rice',
      );

      final edited = line.withQuantity(0.5);

      expect(edited.quantity, 0.5);
      expect(edited.quantityAssumed, isFalse);
      expect(edited.chosenProductId, 'rice');
    });

    test('a zero or negative quantity is rejected and falls back to an assumed '
        '1, so a mis-transcription cannot record a nonsense sale', () {
      for (final bad in <num>[0, -3, -0.5]) {
        final r = VoiceParseResult.fromJson({
          'items': [
            {'heard': 'চাল', 'quantity': bad, 'matches': []},
          ],
        });
        expect(r.items.single.quantity, 1, reason: 'quantity $bad');
        expect(r.items.single.quantityAssumed, isTrue, reason: 'quantity $bad');
      }
    });
  });
}
