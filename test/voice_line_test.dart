import 'package:flutter_test/flutter_test.dart';
import 'package:ai_shopkeeper/features/voice/domain/voice_decision.dart';
import 'package:ai_shopkeeper/features/voice/domain/voice_line.dart';
import 'package:ai_shopkeeper/features/voice/domain/voice_parse_result.dart';

VoiceItem item(String heard, double qty, List<VoiceMatch> matches) => VoiceItem(
  heard: heard,
  quantity: qty,
  quantityAssumed: false,
  matches: matches,
);
VoiceMatch m(String id, double c) => VoiceMatch(productId: id, confidence: c);

void main() {
  test('a clear winner arrives already chosen', () {
    final lines = buildVoiceLines(
      VoiceParseResult(
        items: [
          item('pepsi 1 litre', 2, [m('1L', 0.95), m('500ml', 0.2)]),
        ],
      ),
    );
    expect(lines.single.status, VoiceLineStatus.resolved);
    expect(lines.single.chosenProductId, '1L');
    expect(lines.single.isSettled, isTrue);
  });

  test('a coin flip arrives unchosen with its options', () {
    final lines = buildVoiceLines(
      VoiceParseResult(
        items: [
          item('pepsi', 1, [m('500ml', 0.55), m('1L', 0.52)]),
        ],
      ),
    );
    expect(lines.single.chosenProductId, isNull);
    expect(lines.single.isSettled, isFalse);
    expect(lines.single.choices, hasLength(2));
  });

  test('choosing a product settles the line', () {
    final line = buildVoiceLines(
      VoiceParseResult(
        items: [
          item('pepsi', 1, [m('500ml', 0.55), m('1L', 0.52)]),
        ],
      ),
    ).single;
    final settled = line.chooseProduct('1L');
    expect(settled.chosenProductId, '1L');
    expect(settled.isSettled, isTrue);
  });

  test('quantity can be corrected', () {
    final line = buildVoiceLines(
      VoiceParseResult(
        items: [
          item('pepsi 1 litre', 2, [m('1L', 0.95)]),
        ],
      ),
    ).single;
    final corrected = line.withQuantity(5);
    expect(corrected.quantity, 5);
    // Verify immutability: original is unchanged
    expect(line.quantity, 2);
  });

  test(
    'withQuantity clears quantityAssumed once a human supplies the number',
    () {
      // Build from an item with no spoken count, so the starting state is
      // genuinely assumed (not just constructed with the flag set).
      final itemWithNoCount = VoiceItem(
        heard: 'pepsi',
        quantity: 1,
        quantityAssumed: true,
        matches: [m('1L', 0.95)],
      );
      final line = buildVoiceLines(
        VoiceParseResult(items: [itemWithNoCount]),
      ).single;
      expect(line.quantityAssumed, isTrue);

      final corrected = line.withQuantity(5);
      expect(corrected.quantityAssumed, isFalse);
    },
  );

  test('cannot add to cart while any line is unsettled', () {
    final lines = buildVoiceLines(
      VoiceParseResult(
        items: [
          item('pepsi 1 litre', 2, [m('1L', 0.95)]),
          item('biscuit', 1, []),
        ],
      ),
    );
    expect(canAddToCart(lines), isFalse);
  });

  test('can add once every line is settled', () {
    final lines = buildVoiceLines(
      VoiceParseResult(
        items: [
          item('pepsi 1 litre', 2, [m('1L', 0.95)]),
          item('chips', 3, [m('chips', 0.93)]),
        ],
      ),
    );
    expect(canAddToCart(lines), isTrue);
  });

  test('cannot add an empty list', () {
    expect(canAddToCart(const []), isFalse);
  });

  test('removing the unresolvable line unblocks the rest', () {
    final lines = buildVoiceLines(
      VoiceParseResult(
        items: [
          item('pepsi 1 litre', 2, [m('1L', 0.95)]),
          item('biscuit', 1, []),
        ],
      ),
    );
    expect(canAddToCart(removeLineAt(lines, 1)), isTrue);
  });

  test('buildVoiceLines on empty items returns empty lines', () {
    final lines = buildVoiceLines(VoiceParseResult(items: []));
    expect(lines, isEmpty);
    expect(canAddToCart(lines), isFalse);
  });

  test('an ambiguous line blocks canAddToCart until it is settled', () {
    final lines = buildVoiceLines(
      VoiceParseResult(
        items: [
          item('chips', 3, [m('chips', 0.93)]),
          item('pepsi', 1, [m('500ml', 0.55), m('1L', 0.52)]),
        ],
      ),
    );
    expect(lines[1].status, VoiceLineStatus.ambiguous);
    expect(canAddToCart(lines), isFalse);

    final settled = [lines[0], lines[1].chooseProduct('500ml')];
    expect(canAddToCart(settled), isTrue);
  });

  test('quantityAssumed propagates from item to line', () {
    final itemWithAssumedQty = VoiceItem(
      heard: 'pepsi',
      quantity: 1,
      quantityAssumed: true,
      matches: [m('1L', 0.95)],
    );
    final lines = buildVoiceLines(
      VoiceParseResult(items: [itemWithAssumedQty]),
    );
    expect(lines.single.quantityAssumed, isTrue);
  });
}
