import 'package:ai_shopkeeper/features/expiry/domain/expiry_alerts.dart';
import 'package:ai_shopkeeper/features/expiry/domain/expiry_estimate.dart';
import 'package:ai_shopkeeper/features/expiry/domain/product_batch.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:flutter_test/flutter_test.dart';

ProductBatch b(
  String id,
  String productId,
  double qty,
  DateTime received,
  DateTime expiry, {
  double? locked,
}) => ProductBatch(
  id: id,
  shopId: 's1',
  productId: productId,
  quantity: qty,
  receivedOn: received,
  expiryDate: expiry,
  expiredQty: locked,
);

void main() {
  const pepsi = Product(id: 'pepsi', shopId: 's1', name: 'Pepsi', quantity: 15);
  const bread = Product(id: 'bread', shopId: 's1', name: 'Bread', quantity: 3);
  final today = DateTime(2026, 10, 21);

  final batches = [
    b(
      'p-old-1',
      'pepsi',
      3,
      DateTime(2026, 9, 1),
      DateTime(2026, 10, 19),
      locked: 3,
    ),
    b(
      'p-old-2',
      'pepsi',
      2,
      DateTime(2026, 9, 2),
      DateTime(2026, 10, 20),
      locked: 2,
    ),
    b('p-new', 'pepsi', 10, DateTime(2026, 10, 10), DateTime(2026, 12, 15)),
    b('bread-1', 'bread', 3, DateTime(2026, 10, 18), DateTime(2026, 10, 22)),
  ];

  List<ExpiryAlert> alerts() => buildExpiryAlerts(
    products: [pepsi, bread],
    byProduct: estimateAll(
      products: [pepsi, bread],
      openBatches: batches,
      today: today,
      shopWarnDays: 7,
    ),
    today: today,
  );

  test('expired units are summed into one alert per product', () {
    final expired = alerts()
        .where((a) => a.kind == ExpiryAlertKind.expired)
        .toList();
    expect(expired, hasLength(1));
    expect(expired.single.product.id, 'pepsi');
    expect(expired.single.quantity, 5);
    expect(expired.single.expiryDate, DateTime(2026, 10, 19));
  });

  test('expired alerts come before expiring-soon ones', () {
    final all = alerts();
    expect(all.first.kind, ExpiryAlertKind.expired);
    expect(all.last.kind, ExpiryAlertKind.expiringSoon);
    expect(all.last.product.id, 'bread');
    expect(all.last.daysLeft, 1);
  });

  test('products missing from the list (archived) raise nothing', () {
    final only = buildExpiryAlerts(
      products: [bread],
      byProduct: estimateAll(
        products: [bread],
        openBatches: batches,
        today: today,
        shopWarnDays: 7,
      ),
      today: today,
    );
    expect(only.map((a) => a.product.id), ['bread']);
  });
}
