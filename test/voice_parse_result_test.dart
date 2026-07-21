import 'package:flutter_test/flutter_test.dart';
import 'package:ai_shopkeeper/features/voice/domain/voice_parse_result.dart';

void main() {
  test('parses transcript, items, quantity and ranked matches', () {
    final r = VoiceParseResult.fromJson({
      'heard_text': 'sold 2 pepsi and 3 chips',
      'items': [
        {
          'heard': 'pepsi',
          'quantity': 2,
          'unit_heard': 'piece',
          'matches': [
            {'product_id': 'a', 'confidence': 0.55},
            {'product_id': 'b', 'confidence': 0.52},
          ],
        },
      ],
    });

    expect(r.heardText, 'sold 2 pepsi and 3 chips');
    expect(r.items, hasLength(1));
    expect(r.items.first.heard, 'pepsi');
    expect(r.items.first.quantity, 2);
    expect(r.items.first.unitHeard, 'piece');
    expect(r.items.first.quantityAssumed, isFalse);
    expect(r.items.first.matches.map((m) => m.productId), ['a', 'b']);
  });

  test('empty items parses to an empty list, not an error', () {
    final r = VoiceParseResult.fromJson({'heard_text': 'hello', 'items': []});
    expect(r.items, isEmpty);
  });

  test('missing quantity defaults to 1 and is flagged as assumed', () {
    final r = VoiceParseResult.fromJson({
      'items': [
        {'heard': 'pepsi', 'matches': []},
      ],
    });
    expect(r.items.first.quantity, 1);
    expect(r.items.first.quantityAssumed, isTrue);
  });

  test('a size word is never folded into quantity', () {
    // "1 litre" is a SIZE: it belongs in `heard`, and quantity stays 1.
    final r = VoiceParseResult.fromJson({
      'items': [
        {
          'heard': 'pepsi 1 litre',
          'quantity': 1,
          'unit_heard': null,
          'matches': [],
        },
      ],
    });
    expect(r.items.first.quantity, 1);
    expect(r.items.first.heard, contains('litre'));
    expect(r.items.first.unitHeard, isNull);
  });

  test('non-positive or non-numeric quantities fall back to 1 (assumed)', () {
    final r = VoiceParseResult.fromJson({
      'items': [
        {'heard': 'a', 'quantity': 0, 'matches': []},
        {'heard': 'b', 'quantity': 'two', 'matches': []},
      ],
    });
    expect(r.items[0].quantity, 1);
    expect(r.items[0].quantityAssumed, isTrue);
    expect(r.items[1].quantity, 1);
    expect(r.items[1].quantityAssumed, isTrue);
  });

  test('malformed payload yields an empty result rather than throwing', () {
    final r = VoiceParseResult.fromJson({'nonsense': true});
    expect(r.items, isEmpty);
    expect(r.heardText, isNull);
  });

  test('wrong-typed items field does not throw', () {
    // items is a string, not a list
    final r = VoiceParseResult.fromJson({'items': 'oops'});
    expect(r.items, isEmpty);
  });

  test('wrong-typed matches field does not throw', () {
    // matches is a string, not a list
    final r = VoiceParseResult.fromJson({
      'items': [
        {'heard': 'pepsi', 'matches': 'oops'},
      ],
    });
    expect(r.items, hasLength(1));
    expect(r.items.first.matches, isEmpty);
  });

  test('wrong-typed heard field does not throw', () {
    // heard is a number, not a string
    final r = VoiceParseResult.fromJson({
      'items': [
        {'heard': 123, 'matches': []},
      ],
    });
    expect(r.items, hasLength(1));
    expect(r.items.first.heard, '');
  });

  test('wrong-typed product_id in match is skipped', () {
    // product_id is a number, not a string
    final r = VoiceParseResult.fromJson({
      'items': [
        {
          'heard': 'pepsi',
          'matches': [
            {'product_id': 5, 'confidence': 0.9},
            {'product_id': 'valid', 'confidence': 0.8},
          ],
        },
      ],
    });
    expect(r.items.first.matches, hasLength(1));
    expect(r.items.first.matches.first.productId, 'valid');
  });
}
