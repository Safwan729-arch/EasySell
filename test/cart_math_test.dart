import 'package:ai_shopkeeper/features/cart/domain/cart_line.dart';
import 'package:ai_shopkeeper/features/cart/domain/cart_math.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:flutter_test/flutter_test.dart';

Product _p(
  String id, {
  double quantity = 10,
  double sellingPrice = 5,
  ProductUnit unit = ProductUnit.pcs,
}) => Product(
  id: id,
  shopId: 's',
  name: 'Item $id',
  quantity: quantity,
  sellingPrice: sellingPrice,
  unit: unit,
);

void main() {
  group('addOrIncrementLine', () {
    test('adds a new line for a product not yet in the cart', () {
      final lines = addOrIncrementLine(const [], _p('a'), 2);
      expect(lines, hasLength(1));
      expect(lines.single.product.id, 'a');
      expect(lines.single.quantity, 2);
    });

    test('merges into the existing line for the same product', () {
      final first = addOrIncrementLine(const [], _p('a'), 2);
      final second = addOrIncrementLine(first, _p('a'), 3);
      expect(second, hasLength(1));
      expect(second.single.quantity, 5);
    });

    test('clamps the merged quantity to current stock', () {
      final first = addOrIncrementLine(const [], _p('a', quantity: 4), 3);
      final second = addOrIncrementLine(first, _p('a', quantity: 4), 5);
      expect(second.single.quantity, 4);
    });

    test('adding to an out-of-stock product adds nothing', () {
      final lines = addOrIncrementLine(const [], _p('a', quantity: 0), 2);
      expect(lines, isEmpty);
    });
  });

  group('remainingStockForLines', () {
    test('returns full stock when nothing is staged', () {
      expect(remainingStockForLines(const [], _p('a', quantity: 4)), 4);
    });

    test('subtracts what is already staged for that product', () {
      final lines = addOrIncrementLine(const [], _p('a', quantity: 4), 3);
      expect(remainingStockForLines(lines, _p('a', quantity: 4)), 1);
    });

    test('never goes negative', () {
      final lines = [CartLine(product: _p('a', quantity: 2), quantity: 5)];
      expect(remainingStockForLines(lines, _p('a', quantity: 2)), 0);
    });
  });

  group('updateLineQuantity', () {
    test('sets the quantity, clamped to stock', () {
      final lines = addOrIncrementLine(const [], _p('a', quantity: 4), 1);
      final updated = updateLineQuantity(lines, 'a', 10);
      expect(updated.single.quantity, 4);
    });

    test('a quantity at/below zero removes the line', () {
      final lines = addOrIncrementLine(const [], _p('a'), 1);
      expect(updateLineQuantity(lines, 'a', 0), isEmpty);
    });

    test('a missing product id is a no-op', () {
      final lines = addOrIncrementLine(const [], _p('a'), 1);
      expect(updateLineQuantity(lines, 'missing', 5), lines);
    });
  });

  group('removeLine', () {
    test('drops only the matching product', () {
      final lines = addOrIncrementLine(
        addOrIncrementLine(const [], _p('a'), 1),
        _p('b'),
        1,
      );
      final result = removeLine(lines, 'a');
      expect(result, hasLength(1));
      expect(result.single.product.id, 'b');
    });
  });

  group('cartTotal', () {
    test('sums quantity times selling price across lines', () {
      final lines = [
        CartLine(product: _p('a', sellingPrice: 10), quantity: 2),
        CartLine(product: _p('b', sellingPrice: 5), quantity: 3),
      ];
      expect(cartTotal(lines), 35);
    });

    test('an empty cart totals zero', () {
      expect(cartTotal(const []), 0);
    });
  });

  group('cartItemsPayload', () {
    test('maps lines to the RPC wire shape', () {
      final lines = [CartLine(product: _p('a'), quantity: 2.5)];
      expect(cartItemsPayload(lines), [
        {'product_id': 'a', 'quantity': 2.5},
      ]);
    });
  });

  group('stepForUnit', () {
    test('whole units for pieces, fractional for weight/volume', () {
      expect(stepForUnit(ProductUnit.pcs), 1);
      expect(stepForUnit(ProductUnit.kg), 0.5);
      expect(stepForUnit(ProductUnit.g), 50);
      expect(stepForUnit(ProductUnit.litre), 0.5);
      expect(stepForUnit(ProductUnit.ml), 50);
    });
  });
}
