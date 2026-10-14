import 'package:ai_shopkeeper/features/expiry/domain/expiry_estimate.dart';
import 'package:ai_shopkeeper/features/expiry/domain/product_batch.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:flutter_test/flutter_test.dart';

ProductBatch b(
  String id, {
  required double qty,
  required DateTime received,
  required DateTime expiry,
  double? locked,
  DateTime? created,
}) => ProductBatch(
  id: id,
  shopId: 's1',
  productId: 'p1',
  quantity: qty,
  receivedOn: received,
  expiryDate: expiry,
  expiredQty: locked,
  createdAt: created ?? received,
);

ProductExpiry est(
  double stock,
  List<ProductBatch> batches,
  DateTime today, {
  int shopWarnDays = 7,
  int? override,
}) => estimateProductExpiry(
  productId: 'p1',
  stock: stock,
  openBatches: batches,
  today: today,
  shopWarnDays: shopWarnDays,
  productWarnDays: override,
);

BatchEstimate of(ProductExpiry e, String id) =>
    e.batches.firstWhere((x) => x.batch.id == id);

void main() {
  final oldPepsi = b(
    'old',
    qty: 5,
    received: DateTime(2026, 10, 1),
    expiry: DateTime(2026, 10, 20),
  );
  final newPepsi = b(
    'new',
    qty: 10,
    received: DateTime(2026, 10, 10),
    expiry: DateTime(2026, 12, 15),
  );

  group('the Pepsi case (spec §4.4)', () {
    test('on 21 Oct the old delivery is expired and gets locked at 5', () {
      final e = est(15, [oldPepsi, newPepsi], DateTime(2026, 10, 21));
      expect(of(e, 'old').left, 5);
      expect(of(e, 'old').status, BatchStatus.expired);
      expect(of(e, 'new').left, 10);
      expect(e.good, 10);
      expect(e.expired, 5);
      expect(e.writes, [const LockExpired('old', 5)]);
    });

    test('a sale before removal is counted against good stock only', () {
      final locked = oldPepsi.copyWith(expiredQty: 5);
      final e = est(12, [locked, newPepsi], DateTime(2026, 10, 21));
      expect(of(e, 'old').left, 5);
      expect(of(e, 'new').left, 7);
      expect(e.good, 7);
      expect(e.expired, 5);
      expect(e.writes, isEmpty);
    });
  });

  test('a lock is capped by stock lowered by hand', () {
    final e = est(3, [
      oldPepsi.copyWith(expiredQty: 5),
    ], DateTime(2026, 10, 21));
    expect(e.expired, 3);
    expect(e.good, 0);
  });

  test('two locked expiries with too little stock keep the earliest', () {
    final a = b(
      'a',
      qty: 4,
      received: DateTime(2026, 10, 1),
      expiry: DateTime(2026, 10, 18),
      locked: 4,
    );
    final c = b(
      'c',
      qty: 3,
      received: DateTime(2026, 10, 2),
      expiry: DateTime(2026, 10, 19),
      locked: 3,
    );
    final e = est(5, [c, a], DateTime(2026, 10, 21));
    expect(of(e, 'a').left, 4);
    expect(of(e, 'c').left, 1);
  });

  test('stock beyond the deliveries is untracked and good', () {
    final e = est(20, [newPepsi], DateTime(2026, 10, 21));
    expect(of(e, 'new').left, 10);
    expect(e.good, 20);
    expect(e.expired, 0);
  });

  test('older deliveries are sold first', () {
    final e = est(12, [oldPepsi, newPepsi], DateTime(2026, 10, 15));
    expect(of(e, 'new').left, 10);
    expect(of(e, 'old').left, 2);
  });

  test(
    'a sold-out delivery is closed so an undated restock cannot revive it',
    () {
      final bread = b(
        'mon',
        qty: 10,
        received: DateTime(2026, 10, 13),
        expiry: DateTime(2026, 10, 18),
      );
      final soldOut = est(0, [bread], DateTime(2026, 10, 15));
      expect(of(soldOut, 'mon').status, BatchStatus.soldOut);
      expect(soldOut.writes, [const CloseSoldOut('mon')]);

      // After the close is applied, 10 undated loaves raise nothing.
      final after = applyReconcileWrites([bread], soldOut.writes);
      const product = Product(
        id: 'p1',
        shopId: 's1',
        name: 'Bread',
        quantity: 10,
      );
      final map = estimateAll(
        products: [product],
        openBatches: after,
        today: DateTime(2026, 10, 19),
        shopWarnDays: 7,
      );
      expect(map, isEmpty);
    },
  );

  test(
    'an expired delivery that sold out first is closed, not shown as expired 0',
    () {
      final e = est(10, [oldPepsi, newPepsi], DateTime(2026, 10, 21));
      expect(of(e, 'old').status, BatchStatus.soldOut);
      expect(e.writes, [const CloseSoldOut('old')]);
      expect(e.expired, 0);
    },
  );

  test('a newer delivery that expires sooner is warned on its own date', () {
    final longLife = b(
      'long',
      qty: 10,
      received: DateTime(2026, 10, 1),
      expiry: DateTime(2026, 12, 30),
    );
    final shortLife = b(
      'short',
      qty: 10,
      received: DateTime(2026, 10, 10),
      expiry: DateTime(2026, 10, 25),
    );
    final e = est(15, [longLife, shortLife], DateTime(2026, 10, 22));
    expect(of(e, 'short').left, 10);
    expect(of(e, 'short').status, BatchStatus.expiringSoon);
    expect(of(e, 'long').left, 5);
    expect(of(e, 'long').status, BatchStatus.good);
  });

  group('warning window (spec §4.3)', () {
    // Bread added Monday 13 Oct, expires Saturday 18 Oct: shelf 5 -> w 1.
    final bread = b(
      'bread',
      qty: 10,
      received: DateTime(2026, 10, 13),
      expiry: DateTime(2026, 10, 18),
    );

    test('bread is good two days out', () {
      expect(
        of(est(10, [bread], DateTime(2026, 10, 16)), 'bread').status,
        BatchStatus.good,
      );
    });
    test('bread is expiring soon the day before and on the day', () {
      expect(
        of(est(10, [bread], DateTime(2026, 10, 17)), 'bread').status,
        BatchStatus.expiringSoon,
      );
      expect(
        of(est(10, [bread], DateTime(2026, 10, 18)), 'bread').status,
        BatchStatus.expiringSoon,
      );
    });
    test('bread is expired the day after', () {
      expect(
        of(est(10, [bread], DateTime(2026, 10, 19)), 'bread').status,
        BatchStatus.expired,
      );
    });

    test('yogurt (14 days) warns 4 days ahead, rice (a year) 7', () {
      expect(
        warningDays(
          receivedOn: DateTime(2026, 10, 1),
          expiryDate: DateTime(2026, 10, 15),
          shopWarnDays: 7,
        ),
        4,
      );
      expect(
        warningDays(
          receivedOn: DateTime(2026, 1, 1),
          expiryDate: DateTime(2027, 1, 1),
          shopWarnDays: 7,
        ),
        7,
      );
    });

    test('the shop setting caps the automatic window', () {
      expect(
        warningDays(
          receivedOn: DateTime(2026, 1, 1),
          expiryDate: DateTime(2027, 1, 1),
          shopWarnDays: 3,
        ),
        3,
      );
    });

    test('a date already passed at entry still warns at least a day', () {
      expect(
        warningDays(
          receivedOn: DateTime(2026, 10, 14),
          expiryDate: DateTime(2026, 10, 10),
          shopWarnDays: 7,
        ),
        1,
      );
    });

    test('override of 0 warns on the expiry day only', () {
      expect(
        of(
          est(10, [bread], DateTime(2026, 10, 17), override: 0),
          'bread',
        ).status,
        BatchStatus.good,
      );
      expect(
        of(
          est(10, [bread], DateTime(2026, 10, 18), override: 0),
          'bread',
        ).status,
        BatchStatus.expiringSoon,
      );
    });

    test('an override wins over the automatic rule', () {
      expect(
        warningDays(
          receivedOn: DateTime(2026, 1, 1),
          expiryDate: DateTime(2027, 1, 1),
          shopWarnDays: 7,
          productWarnDays: 30,
        ),
        30,
      );
    });
  });

  test('fractional stock does not trip float error', () {
    final a = b(
      'a',
      qty: 0.1,
      received: DateTime(2026, 10, 1),
      expiry: DateTime(2026, 12, 1),
    );
    final c = b(
      'c',
      qty: 0.2,
      received: DateTime(2026, 10, 2),
      expiry: DateTime(2026, 12, 1),
    );
    final e = est(0.1 + 0.2, [a, c], DateTime(2026, 10, 14));
    expect(of(e, 'a').left, 0.1);
    expect(of(e, 'c').left, 0.2);
    expect(e.writes, isEmpty);
  });

  test('negative stock is treated as zero', () {
    final e = est(-2, [newPepsi], DateTime(2026, 10, 14));
    expect(e.stock, 0);
    expect(e.good, 0);
  });

  test('batches come back earliest expiry first', () {
    final e = est(15, [newPepsi, oldPepsi], DateTime(2026, 10, 15));
    expect(e.batches.map((x) => x.batch.id), ['old', 'new']);
  });

  test(
    'goodStockOf falls back to the whole stock when a product has no deliveries',
    () {
      const p = Product(id: 'p9', shopId: 's1', name: 'Soap', quantity: 4);
      expect(goodStockOf(p, const {}), 4);
    },
  );

  test('applyReconcileWrites locks and closes in memory', () {
    final out = applyReconcileWrites(
      [oldPepsi, newPepsi],
      const [LockExpired('old', 5), CloseSoldOut('new')],
    );
    expect(out, hasLength(1));
    expect(out.single.expiredQty, 5);
  });
}
