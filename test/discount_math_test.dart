import 'package:ai_shopkeeper/features/cart/domain/cart_line.dart';
import 'package:ai_shopkeeper/features/cart/domain/discount_math.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:flutter_test/flutter_test.dart';

CartLine _line({
  required double selling,
  required double buying,
  required double qty,
}) => CartLine(
  product: Product(
    id: 'p${selling.toInt()}',
    shopId: 's1',
    name: 'x',
    sellingPrice: selling,
    buyingPrice: buying,
    quantity: 100,
  ),
  quantity: qty,
);

void main() {
  group('clampDiscount', () {
    test('passes a discount that fits', () {
      expect(clampDiscount(entered: 60, subtotal: 1360), 60);
    });

    test('never exceeds the bill', () {
      // The reason this exists: the cart can SHRINK after a discount is set.
      expect(clampDiscount(entered: 60, subtotal: 50), 50);
    });

    test('a discount equal to the bill is allowed', () {
      expect(clampDiscount(entered: 50, subtotal: 50), 50);
    });

    test('negatives collapse to zero', () {
      expect(clampDiscount(entered: -5, subtotal: 100), 0);
    });

    test('an empty cart takes no discount', () {
      expect(clampDiscount(entered: 60, subtotal: 0), 0);
    });

    // The next three exist because `record_sale_cart` REJECTS anything above
    // floor(subtotal * 100) / 100. Clamping to the raw subtotal would let the
    // UI offer a discount the database then refuses, failing the checkout.
    test('caps at the floored bill, not the raw one', () {
      // 45.00 x 2.501 = 112.545; the payable maximum is 112.54.
      expect(clampDiscount(entered: 112.545, subtotal: 112.545), 112.54);
    });

    test('floors the entered amount to whole paisa', () {
      // discount_amount is numeric(10,2); a third decimal cannot be stored,
      // so the sum would not match what was asked for.
      expect(clampDiscount(entered: 7.005, subtotal: 200), 7);
    });

    test('binary floating point does not eat a paisa', () {
      // 0.29 * 100 is 28.999999999999996 in IEEE 754. A naive floor returns
      // 0.28 and quietly short-changes the customer on a very ordinary amount.
      expect(clampDiscount(entered: 0.29, subtotal: 100), 0.29);
      expect(clampDiscount(entered: 1.15, subtotal: 100), 1.15);
      expect(clampDiscount(entered: 8.07, subtotal: 100), 8.07);
    });
  });

  group('cartCost', () {
    test('sums buying price times quantity', () {
      final lines = [
        _line(selling: 45, buying: 30, qty: 2), // 60
        _line(selling: 850, buying: 700, qty: 1), // 700
      ];
      expect(cartCost(lines), 760);
    });

    test('an empty cart costs nothing', () {
      expect(cartCost(const []), 0);
    });
  });

  group('lossFromDiscount', () {
    test('is zero while the sale still profits', () {
      // 1000 bill, 800 cost => 200 profit. 150 off still profits.
      expect(lossFromDiscount(subtotal: 1000, cost: 800, discount: 150), 0);
    });

    test('is zero exactly at break-even', () {
      expect(lossFromDiscount(subtotal: 1000, cost: 800, discount: 200), 0);
    });

    test('reports how much is lost past break-even', () {
      expect(lossFromDiscount(subtotal: 1000, cost: 800, discount: 212), 12);
    });
  });
}
