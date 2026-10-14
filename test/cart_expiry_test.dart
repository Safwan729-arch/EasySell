import 'package:ai_shopkeeper/features/cart/domain/cart_line.dart';
import 'package:ai_shopkeeper/features/expiry/domain/cart_expiry.dart';
import 'package:ai_shopkeeper/features/expiry/domain/expiry_estimate.dart';
import 'package:ai_shopkeeper/features/expiry/domain/product_batch.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const pepsi = Product(id: 'pepsi', shopId: 's1', name: 'Pepsi', quantity: 6);
  final expired = ProductBatch(
    id: 'old',
    shopId: 's1',
    productId: 'pepsi',
    quantity: 5,
    receivedOn: DateTime(2026, 9, 1),
    expiryDate: DateTime(2026, 10, 20),
    expiredQty: 5,
  );
  final byProduct = estimateAll(
    products: [pepsi],
    openBatches: [expired],
    today: DateTime(2026, 10, 21),
    shopWarnDays: 7,
  );

  test('a line within good stock raises no notice', () {
    final lines = [CartLine(product: pepsi, quantity: 1)];
    expect(
      cartLineNotices(
        lines: lines,
        liveProducts: {'pepsi': pepsi},
        byProduct: byProduct,
      ),
      isEmpty,
    );
    expect(expiredBlockedProductIds(lines, byProduct), isEmpty);
  });

  test('a line above good stock with expired units is blocked', () {
    final lines = [CartLine(product: pepsi, quantity: 2)];
    final n = cartLineNotices(
      lines: lines,
      liveProducts: {'pepsi': pepsi},
      byProduct: byProduct,
    )['pepsi'];
    expect(n, isA<ExpiredStockNotice>());
    n as ExpiredStockNotice;
    expect(n.good, 1);
    expect(n.expired, 5);
    expect(n.expiredBatchIds, ['old']);
    expect(expiredBlockedProductIds(lines, byProduct), ['pepsi']);
  });

  test('a line above live stock with no expired units says only X left', () {
    const soap = Product(id: 'soap', shopId: 's1', name: 'Soap', quantity: 2);
    final lines = [CartLine(product: soap.copyWith(quantity: 9), quantity: 4)];
    final n = cartLineNotices(
      lines: lines,
      liveProducts: {'soap': soap},
      byProduct: const {},
    )['soap'];
    expect(n, isA<OverStockNotice>());
    expect((n as OverStockNotice).stock, 2);
    expect(expiredBlockedProductIds(lines, const {}), isEmpty);
  });
}
