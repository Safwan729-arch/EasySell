import 'package:ai_shopkeeper/features/cart/domain/cart_math.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:flutter_test/flutter_test.dart';

/// `transactions.quantity` is `numeric(10,3)`, so Postgres rounds anything
/// finer when the row is written. If Dart stages a quantity it does not round
/// the same way, the two compute DIFFERENT subtotals for the same cart — and
/// since `record_sale_cart` rejects a discount above the bill it computes, a
/// near-total discount the app accepted fails the whole checkout, with no stock
/// moved and nothing on screen explaining why.
///
/// `clampCartQuantity` already rounded, but not every path goes through it:
/// the voice flow calls `cart.addOrIncrement` with a quantity straight from the
/// AI's parsed JSON. These tests pin the rounding at the domain layer, where
/// every path meets.

const _rice = Product(
  id: 'p1',
  shopId: 's1',
  name: 'Rice',
  sellingPrice: 1000,
  buyingPrice: 800,
  quantity: 100,
  unit: ProductUnit.kg,
);

void main() {
  group('addOrIncrementLine', () {
    test('rounds a new line to the 3 decimals the database stores', () {
      final lines = addOrIncrementLine(const [], _rice, 0.1234);
      expect(lines.single.quantity, 0.123);
    });

    test('rounds the merged quantity too, not just the first add', () {
      var lines = addOrIncrementLine(const [], _rice, 1);
      lines = addOrIncrementLine(lines, _rice, 0.0005);
      expect(lines.single.quantity, 1.001);
    });

    test('leaves an already-exact quantity alone', () {
      final lines = addOrIncrementLine(const [], _rice, 2.5);
      expect(lines.single.quantity, 2.5);
    });

    test('still clamps to available stock', () {
      final lines = addOrIncrementLine(const [], _rice, 500);
      expect(lines.single.quantity, 100);
    });
  });

  group('updateLineQuantity', () {
    test('rounds to 3 decimals', () {
      var lines = addOrIncrementLine(const [], _rice, 1);
      lines = updateLineQuantity(lines, 'p1', 0.1234);
      expect(lines.single.quantity, 0.123);
    });
  });

  test('a rounded cart subtotal is one the database can reproduce', () {
    // The failure this whole file exists for: at 1000/kg, an unrounded 0.1234
    // gives Dart a subtotal of 123.40 while Postgres stores 0.123 and computes
    // 123.00 -- so a 123.40 discount, which the app would have allowed, is
    // rejected by the RPC and the sale dies.
    final lines = addOrIncrementLine(const [], _rice, 0.1234);
    expect(cartTotal(lines), 123.0);
  });
}
