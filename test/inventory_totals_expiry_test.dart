import 'package:ai_shopkeeper/features/expiry/domain/expiry_estimate.dart';
import 'package:ai_shopkeeper/features/expiry/domain/product_batch.dart';
import 'package:ai_shopkeeper/features/inventory/domain/inventory_totals.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('5 expired + 1 good with a threshold of 3 counts as low stock', () {
    const pepsi = Product(
      id: 'pepsi',
      shopId: 's1',
      name: 'Pepsi',
      quantity: 6,
      reorderThreshold: 3,
    );
    final expiry = estimateAll(
      products: [pepsi],
      openBatches: [
        ProductBatch(
          id: 'old',
          shopId: 's1',
          productId: 'pepsi',
          quantity: 5,
          receivedOn: DateTime(2026, 9, 1),
          expiryDate: DateTime(2026, 10, 20),
          expiredQty: 5,
        ),
      ],
      today: DateTime(2026, 10, 21),
      shopWarnDays: 7,
    );
    expect(InventoryTotals.of([pepsi]).lowStockCount, 0);
    expect(InventoryTotals.of([pepsi], expiry: expiry).lowStockCount, 1);
  });
}
