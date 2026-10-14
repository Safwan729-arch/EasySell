import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('saving an edited product never writes stock', () {
    // The edit form has no stock box. Writing the form's copy of the stock
    // back would undo any sale made while the form was open.
    const p = Product(id: 'p', shopId: 's', name: 'Pepsi', quantity: 30);
    final row = p.toUpdateRow();
    expect(row.containsKey('quantity'), isFalse);
    expect(row['name'], 'Pepsi');
  });
}
