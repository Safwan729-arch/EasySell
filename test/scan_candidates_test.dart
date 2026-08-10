import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/scan/domain/scan_candidates.dart';
import 'package:flutter_test/flutter_test.dart';

Product _p(
  String id,
  String name, {
  String? brand,
  String? variant,
  ProductUnit unit = ProductUnit.pcs,
}) => Product(
  id: id,
  shopId: 's',
  name: name,
  brand: brand,
  variant: variant,
  unit: unit,
);

void main() {
  test('candidates carry a list index, never the uuid', () {
    final payload = buildCandidatePayload([
      _p('uuid-a', 'Pepsi 500ml', brand: 'Pepsi', variant: '500ml'),
      _p('uuid-b', 'Loose rice'),
    ]);
    expect(payload.candidates, [
      {'i': 0, 'name': 'Pepsi 500ml', 'brand': 'Pepsi', 'variant': '500ml'},
      {'i': 1, 'name': 'Loose rice'},
    ]);
    // The whole point: a 36-char uuid is ~20 tokens of noise per candidate.
    expect(payload.candidates.first.containsKey('id'), isFalse);
  });

  test('resolve maps the echoed index back to the real product id', () {
    final payload = buildCandidatePayload([
      _p('uuid-a', 'Pepsi'),
      _p('uuid-b', 'Rice'),
    ]);
    expect(payload.resolve('0'), 'uuid-a');
    expect(payload.resolve('1'), 'uuid-b');
  });

  test('an invented identifier resolves to null, never a wrong product', () {
    final payload = buildCandidatePayload([_p('uuid-a', 'Pepsi')]);
    expect(payload.resolve('7'), isNull, reason: 'out of range');
    expect(payload.resolve('-1'), isNull);
    expect(payload.resolve('uuid-a'), isNull, reason: 'not an index');
    expect(payload.resolve(''), isNull);
  });

  test('scan omits unit by default; voice opts in', () {
    final scan = buildCandidatePayload([
      _p('a', 'Milk', unit: ProductUnit.litre),
    ]).candidates.single;
    expect(scan.containsKey('unit'), isFalse);

    final voice = buildCandidatePayload([
      _p('a', 'Milk', unit: ProductUnit.litre),
    ], includeUnit: true).candidates.single;
    expect(voice['unit'], 'litre');
  });

  test('recent units are keyed by product id, not index', () {
    final c = buildCandidatePayload(
      [_p('uuid-a', 'Pepsi'), _p('uuid-b', 'Rice')],
      recentUnits: {'uuid-b': 12.4},
    ).candidates;
    expect(c[0].containsKey('recent'), isFalse);
    expect(c[1]['recent'], 12);
  });
}
