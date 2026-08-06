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

/// A one-line cart whose subtotal is exactly [subtotal].
List<CartLine> _cart(double subtotal) => [
  _line(selling: subtotal, buying: 0, qty: 1),
];

void main() {
  group('maxDiscount', () {
    test('an ordinary 2-decimal cart is just its total', () {
      final lines = [
        _line(selling: 45, buying: 30, qty: 2), // 90
        _line(selling: 850, buying: 700, qty: 1), // 850
      ];
      expect(maxDiscount(lines), 940);
    });

    test('an empty cart allows nothing', () {
      expect(maxDiscount(const []), 0);
    });

    // The case that forced the cap to change shape. Each line is 45.00 x 2.501
    // = 112.545, so the subtotal is exactly 225.09 and floor(subtotal) would
    // permit all of it -- but each line's share floors to 112.54 and neither
    // has the headroom for the leftover paisa, so `record_sale_cart` would
    // store 225.08 against an entered 225.09. Capping at the SUM OF THE
    // PER-LINE FLOORS makes the maximum exactly allocatable.
    test(
      'caps at the sum of the per-line floors, not the floor of the sum',
      () {
        final lines = [
          _line(selling: 45, buying: 0, qty: 2.501),
          _line(selling: 45, buying: 0, qty: 2.501),
        ];
        expect(maxDiscount(lines), 225.08);
      },
    );

    test('a single fractional line floors to its own paisa', () {
      expect(maxDiscount([_line(selling: 45, buying: 0, qty: 2.501)]), 112.54);
    });
  });

  group('clampDiscount', () {
    test('passes a discount that fits', () {
      expect(clampDiscount(entered: 60, lines: _cart(1360)), 60);
    });

    test('never exceeds the bill', () {
      // The reason this exists: the cart can SHRINK after a discount is set.
      expect(clampDiscount(entered: 60, lines: _cart(50)), 50);
    });

    test('a discount equal to the bill is allowed', () {
      expect(clampDiscount(entered: 50, lines: _cart(50)), 50);
    });

    test('negatives collapse to zero', () {
      expect(clampDiscount(entered: -5, lines: _cart(100)), 0);
    });

    test('an empty cart takes no discount', () {
      expect(clampDiscount(entered: 60, lines: const []), 0);
    });

    // The next three exist because `record_sale_cart` REJECTS anything above
    // its own maximum. Clamping to the raw subtotal would let the UI offer a
    // discount the database then refuses, failing the checkout.
    test('caps at the floored bill, not the raw one', () {
      // 45.00 x 2.501 = 112.545; the payable maximum is 112.54.
      expect(
        clampDiscount(
          entered: 112.545,
          lines: [_line(selling: 45, buying: 0, qty: 2.501)],
        ),
        112.54,
      );
    });

    test('caps a multi-line fractional cart at what the split can place', () {
      final lines = [
        _line(selling: 45, buying: 0, qty: 2.501),
        _line(selling: 45, buying: 0, qty: 2.501),
      ];
      // 225.09 is the true subtotal and the OLD cap; only 225.08 is reachable.
      expect(clampDiscount(entered: 225.09, lines: lines), 225.08);
      expect(clampDiscount(entered: 225.08, lines: lines), 225.08);
    });

    test('floors the entered amount to whole paisa', () {
      // discount_amount is numeric(10,2); a third decimal cannot be stored,
      // so the sum would not match what was asked for.
      expect(clampDiscount(entered: 7.005, lines: _cart(200)), 7);
    });

    test('binary floating point does not eat a paisa', () {
      // 0.29 * 100 is 28.999999999999996 in IEEE 754. A naive floor returns
      // 0.28 and quietly short-changes the customer on a very ordinary amount.
      expect(clampDiscount(entered: 0.29, lines: _cart(100)), 0.29);
      expect(clampDiscount(entered: 1.15, lines: _cart(100)), 1.15);
      expect(clampDiscount(entered: 8.07, lines: _cart(100)), 8.07);
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
