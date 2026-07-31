import 'package:ai_shopkeeper/features/inventory/domain/inventory_totals.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:flutter_test/flutter_test.dart';

Product _p({
  required double buying,
  required double selling,
  required double qty,
  double reorder = 0,
}) => Product(
  id: 'p',
  shopId: 's',
  name: 'x',
  buyingPrice: buying,
  sellingPrice: selling,
  quantity: qty,
  reorderThreshold: reorder,
);

void main() {
  group('InventoryTotals', () {
    test('values stock at cost and at retail', () {
      final t = InventoryTotals.of([
        _p(buying: 10, selling: 15, qty: 3), // 30 cost, 45 retail
        _p(buying: 100, selling: 120, qty: 2), // 200 cost, 240 retail
      ]);
      expect(t.productCount, 2);
      expect(t.costValue, 230);
      expect(t.retailValue, 285);
      expect(t.potentialProfit, 55);
    });

    test('counts fractional stock, since weighed goods sell in halves', () {
      final t = InventoryTotals.of([_p(buying: 40, selling: 50, qty: 2.5)]);
      expect(t.costValue, 100);
      expect(t.retailValue, 125);
    });

    test('potential profit goes negative when stock is priced below cost', () {
      final t = InventoryTotals.of([_p(buying: 50, selling: 40, qty: 2)]);
      expect(t.potentialProfit, -20);
    });

    test('low stock counts only products with the alert enabled', () {
      final t = InventoryTotals.of([
        _p(buying: 1, selling: 2, qty: 0, reorder: 5), // at/below -> low
        _p(buying: 1, selling: 2, qty: 3, reorder: 3), // at threshold -> low
        _p(buying: 1, selling: 2, qty: 9, reorder: 3), // above -> not low
        // Threshold 0 disables the alert, so zero stock is NOT low here.
        _p(buying: 1, selling: 2, qty: 0),
      ]);
      expect(t.lowStockCount, 2);
      expect(t.productCount, 4);
    });

    test('an empty inventory is all zeros, not a crash or a NaN', () {
      final t = InventoryTotals.of(const []);
      expect(t.productCount, 0);
      expect(t.costValue, 0);
      expect(t.retailValue, 0);
      expect(t.potentialProfit, 0);
      expect(t.lowStockCount, 0);
    });
  });
}
