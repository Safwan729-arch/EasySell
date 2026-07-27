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
  test('buildCandidates maps id/name/brand/variant and drops nulls', () {
    final out = buildCandidates([
      _p('a', 'Pepsi 500ml', brand: 'Pepsi', variant: '500ml'),
      _p('b', 'Loose rice'),
    ]);
    expect(out, [
      {'id': 'a', 'name': 'Pepsi 500ml', 'brand': 'Pepsi', 'variant': '500ml'},
      {'id': 'b', 'name': 'Loose rice'},
    ]);
  });

  test('scan payload is unchanged -- no unit key by default', () {
    final c = buildCandidates([
      _p('a', 'Milk', unit: ProductUnit.litre),
    ]).single;
    expect(c.containsKey('unit'), isFalse);
    expect(c, {'id': 'a', 'name': 'Milk'});
  });

  test('voice opts in to unit', () {
    final c = buildCandidates([
      _p('a', 'Milk', unit: ProductUnit.litre),
    ], includeUnit: true).single;
    expect(c['unit'], 'litre');
  });
}
