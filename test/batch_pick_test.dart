import 'package:ai_shopkeeper/features/cart/domain/cart_line.dart';
import 'package:ai_shopkeeper/features/expiry/domain/batch_pick.dart';
import 'package:ai_shopkeeper/features/expiry/domain/cart_expiry.dart';
import 'package:ai_shopkeeper/features/expiry/domain/expiry_estimate.dart';
import 'package:ai_shopkeeper/features/expiry/domain/product_batch.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:flutter_test/flutter_test.dart';

const _brush = Product(id: 'brush', shopId: 's1', name: 'Toothbrush');
final _today = DateTime(2026, 10, 15);

ProductBatch _batch(
  String id, {
  required double qty,
  required DateTime expiry,
  DateTime? received,
  double picked = 0,
  double? expiredQty,
  int created = 0,
}) => ProductBatch(
  id: id,
  shopId: 's1',
  productId: 'brush',
  quantity: qty,
  receivedOn: received ?? DateTime(2026, 10, 15),
  expiryDate: expiry,
  pickedQty: picked,
  expiredQty: expiredQty,
  createdAt: DateTime(2026, 10, 15, 9, created),
);

// The screenshot's case: 10 expiring tomorrow, 16 good, both added today.
final _soon = _batch('soon', qty: 10, expiry: DateTime(2026, 10, 16));
final _fresh = _batch(
  'fresh',
  qty: 16,
  expiry: DateTime(2026, 10, 21),
  created: 1,
);

ProductExpiry _estimate(double stock, List<ProductBatch> batches) =>
    estimateProductExpiry(
      productId: 'brush',
      stock: stock,
      openBatches: batches,
      today: _today,
      shopWarnDays: 7,
    );

double _left(ProductExpiry e, String id) =>
    e.batches.firstWhere((b) => b.batch.id == id).left;

void main() {
  group('estimate with picks', () {
    test('a unit picked from the fresh delivery comes off that delivery', () {
      final e = _estimate(25, [_soon, _fresh.copyWith(pickedQty: 1)]);
      expect(_left(e, 'soon'), 10);
      expect(_left(e, 'fresh'), 15);
    });

    test('the same holds whichever delivery was entered first', () {
      final e = _estimate(25, [
        _soon.copyWith(createdAt: DateTime(2026, 10, 15, 10)),
        _fresh.copyWith(pickedQty: 1),
      ]);
      expect(_left(e, 'soon'), 10);
      expect(_left(e, 'fresh'), 15);
    });

    test('a later-received delivery that expires sooner is exact too', () {
      // FIFO alone would assume the OLDER delivery sold; the pick says which.
      final old = _batch(
        'old',
        qty: 10,
        expiry: DateTime(2026, 12, 30),
        received: DateTime(2026, 10, 1),
      );
      final newer = _batch(
        'newer',
        qty: 16,
        expiry: DateTime(2026, 10, 20),
        received: DateTime(2026, 10, 10),
        picked: 1,
      );
      final e = _estimate(25, [old, newer]);
      expect(_left(e, 'old'), 10);
      expect(_left(e, 'newer'), 15);
    });

    test('picks above the delivered amount leave it at zero', () {
      final e = _estimate(3, [_soon, _fresh.copyWith(pickedQty: 20)]);
      expect(_left(e, 'fresh'), 0);
      expect(_left(e, 'soon'), 3);
    });
  });

  group('sell options', () {
    test('soonest expiry first, then stock with no date', () {
      final e = _estimate(30, [_fresh, _soon]);
      final o = sellOptions(e);
      expect([for (final x in o) x.batchId], ['soon', 'fresh', null]);
      expect([for (final x in o) x.left], [10, 16, 4]);
      expect(needsBatchChoice(o), isTrue);
    });

    test('expired and sold-out deliveries are not offered', () {
      final expired = _batch(
        'exp',
        qty: 5,
        expiry: DateTime(2026, 10, 10),
        expiredQty: 5,
      );
      final e = _estimate(21, [expired, _fresh, _soon]);
      // 5 locked expired, 16 to fresh, nothing left for soon.
      expect([for (final x in sellOptions(e)) x.batchId], ['fresh']);
      expect(needsBatchChoice(sellOptions(e)), isFalse);
    });

    test('no deliveries, no options', () {
      expect(sellOptions(null), isEmpty);
    });
  });

  group('resolveSaleItems', () {
    final byProduct = {
      'brush': _estimate(26, [_soon, _fresh]),
    };
    CartLine line(double q, [String? batch]) =>
        CartLine(product: _brush, quantity: q, batchId: batch);

    test('a product without deliveries is sent as before', () {
      final r = resolveSaleItems([line(2)], const {});
      expect(r.items, [
        {'product_id': 'brush', 'quantity': 2.0},
      ]);
      expect(r.short, isEmpty);
    });

    test('left alone, soonest expiry sells first and spills over', () {
      final r = resolveSaleItems([line(12)], byProduct);
      expect(r.items, [
        {'product_id': 'brush', 'quantity': 10.0, 'batch_id': 'soon'},
        {'product_id': 'brush', 'quantity': 2.0, 'batch_id': 'fresh'},
      ]);
    });

    test('a chosen delivery is sent with the line', () {
      final r = resolveSaleItems([line(1, 'fresh')], byProduct);
      expect(r.items, [
        {'product_id': 'brush', 'quantity': 1.0, 'batch_id': 'fresh'},
      ]);
    });

    test('"no date" sends no delivery', () {
      final withLoose = {
        'brush': _estimate(30, [_soon, _fresh]),
      };
      final r = resolveSaleItems([line(2, noDateBatch)], withLoose);
      expect(r.items, [
        {'product_id': 'brush', 'quantity': 2.0},
      ]);
      expect(r.short, isEmpty);
    });

    test('more than the chosen delivery has is refused', () {
      final r = resolveSaleItems([line(11, 'soon')], byProduct);
      expect(r.short, ['brush']);
    });

    test('a chosen delivery that is gone is refused', () {
      final r = resolveSaleItems([line(1, 'closed-one')], byProduct);
      expect(r.short, ['brush']);
    });
  });

  test('the cart shows what a chosen delivery has left', () {
    final notices = cartLineNotices(
      lines: [CartLine(product: _brush, quantity: 11, batchId: 'soon')],
      liveProducts: {'brush': _brush.copyWith(quantity: 26)},
      byProduct: {
        'brush': _estimate(26, [_soon, _fresh]),
      },
    );
    expect(notices['brush'], isA<BatchShortNotice>());
    expect((notices['brush'] as BatchShortNotice).left, 10);
  });
}
