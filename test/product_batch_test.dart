import 'package:ai_shopkeeper/features/expiry/domain/product_batch.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ProductBatch reads a product_batches row', () {
    final b = ProductBatch.fromJson({
      'id': 'b1',
      'shop_id': 's1',
      'product_id': 'p1',
      'quantity': 5,
      'buying_price': 30.5,
      'received_on': '2026-10-01',
      'expiry_date': '2026-10-20',
      'expired_qty': null,
      'closed_at': null,
      'closed_reason': null,
      'created_at': '2026-10-01T04:00:00Z',
    });
    expect(b.quantity, 5.0);
    expect(b.receivedOn, DateTime(2026, 10, 1));
    expect(b.expiryDate, DateTime(2026, 10, 20));
    expect(b.isOpen, isTrue);
  });

  test('Product carries the expiry warning override both ways', () {
    final p = Product.fromJson({
      'id': 'p1',
      'shop_id': 's1',
      'name': 'Bread',
      'expiry_warn_days': 1,
    });
    expect(p.expiryWarnDays, 1);
    expect(p.toRow()['expiry_warn_days'], 1);
    expect(
      p.copyWith(expiryWarnDays: null).toRow()['expiry_warn_days'],
      isNull,
    );
  });

  test('isLowStockAt judges a given amount, isLowStock the whole stock', () {
    const p = Product(
      id: 'p1',
      shopId: 's1',
      name: 'Pepsi',
      quantity: 6,
      reorderThreshold: 3,
    );
    expect(p.isLowStock, isFalse);
    expect(p.isLowStockAt(1), isTrue);
  });
}
