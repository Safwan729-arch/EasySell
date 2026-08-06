import 'package:ai_shopkeeper/features/transactions/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

/// A discount comes out of MARGIN, not out of what was paid to the supplier.
/// So `revenue` and `profit` fall by it and `cost` does not move -- the same
/// split the SQL in 0009 makes, restated here so the Dart and the database
/// cannot drift apart.
void main() {
  const line = Transaction(
    id: 't1',
    shopId: 's1',
    productId: 'p1',
    type: 'sale',
    quantity: 2,
    buyingPrice: 30,
    sellingPrice: 45,
    discountAmount: 10,
  );

  test('revenue is net of the discount', () {
    expect(line.revenue, 80); // 45 * 2 - 10
  });

  test('cost ignores the discount', () {
    expect(line.cost, 60); // 30 * 2
  });

  test('profit absorbs the discount', () {
    expect(line.profit, 20); // 80 - 60
  });

  test('an undiscounted line is unchanged', () {
    const plain = Transaction(
      id: 't2',
      shopId: 's1',
      productId: 'p1',
      type: 'sale',
      quantity: 2,
      buyingPrice: 30,
      sellingPrice: 45,
    );
    expect(plain.discountAmount, 0);
    expect(plain.revenue, 90);
  });

  test('discount_amount is read from the row', () {
    final t = Transaction.fromJson(const {
      'id': 't3',
      'shop_id': 's1',
      'product_id': 'p1',
      'type': 'sale',
      'quantity': 2,
      'buying_price': 30,
      'selling_price': 45,
      'discount_amount': 10,
    });
    expect(t.discountAmount, 10);
    expect(t.revenue, 80);
  });
}
