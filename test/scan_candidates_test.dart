import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/scan/domain/scan_candidates.dart';
import 'package:flutter_test/flutter_test.dart';

Product _p(String id, String name, {String? brand, String? variant}) => Product(
  id: id, shopId: 's', name: name, brand: brand, variant: variant,
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
}
