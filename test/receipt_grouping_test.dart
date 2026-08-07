import 'package:ai_shopkeeper/features/transactions/domain/transaction.dart';
import 'package:ai_shopkeeper/features/transactions/presentation/history_screen.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _sale(
  String id, {
  String? group,
  double sellingPrice = 10,
  DateTime? at,
}) => Transaction(
  id: id,
  shopId: 's',
  productId: 'p-$id',
  type: 'sale',
  quantity: 1,
  sellingPrice: sellingPrice,
  saleGroupId: group,
  createdAt: at,
);

void main() {
  _discountTotals();
  group('groupSalesIntoReceipts', () {
    test('sales sharing a saleGroupId become one receipt', () {
      final sales = [
        _sale('a', group: 'g1'),
        _sale('b', group: 'g1'),
        _sale('c'),
      ];
      final receipts = groupSalesIntoReceipts(sales);
      expect(receipts, hasLength(2));
      expect(receipts.first.id, 'g1');
      expect(receipts.first.lineCount, 2);
      expect(receipts.last.lineCount, 1);
    });

    test('null saleGroupId sales never merge with each other', () {
      final sales = [_sale('a'), _sale('b')];
      final receipts = groupSalesIntoReceipts(sales);
      expect(receipts, hasLength(2));
      expect(receipts[0].id, isNot(receipts[1].id));
    });

    test('totalRevenue sums every line in the receipt', () {
      final sales = [
        _sale('a', group: 'g1', sellingPrice: 10),
        _sale('b', group: 'g1', sellingPrice: 15),
      ];
      expect(groupSalesIntoReceipts(sales).single.totalRevenue, 25);
    });

    test('preserves first-seen order of groups', () {
      final sales = [
        _sale('a', group: 'g2'),
        _sale('b', group: 'g1'),
        _sale('c', group: 'g2'),
      ];
      final receipts = groupSalesIntoReceipts(sales);
      expect(receipts.map((r) => r.id), ['g2', 'g1']);
    });
  });
}

/// The receipt-level discount.
///
/// `record_sale_cart` splits a cart discount across the sale's rows, so the
/// figure the shopkeeper actually typed exists nowhere in the database — a
/// receipt is only rows sharing a `sale_group_id`. Summing the shares
/// reproduces it exactly, which is the whole reason the split is exact to the
/// paisa. Without this, a 3-line sale with ৳7 off shows `−৳2.33` on one line's
/// detail and the ৳7 appears nowhere in History at all.
void _discountTotals() {
  Transaction line(String id, double selling, double discount) => Transaction(
    id: id,
    shopId: 's',
    productId: 'p-$id',
    type: 'sale',
    quantity: 1,
    sellingPrice: selling,
    discountAmount: discount,
    saleGroupId: 'g1',
  );

  group('SaleReceipt discount', () {
    test('sums the per-line shares back into the entered discount', () {
      // Three 100.00 lines with 7.00 off: the split floors each to 2.33 and
      // hands the stray paisa to the largest line.
      final r = groupSalesIntoReceipts([
        line('a', 100, 2.34),
        line('b', 100, 2.33),
        line('c', 100, 2.33),
      ]).single;

      expect(r.discountTotal, closeTo(7.0, 1e-9));
      expect(r.totalRevenue, closeTo(293.0, 1e-9));
      expect(r.grossRevenue, closeTo(300.0, 1e-9));
    });

    test('an undiscounted receipt reports zero, not null', () {
      final r = groupSalesIntoReceipts([
        line('a', 100, 0),
        line('b', 50, 0),
      ]).single;
      expect(r.discountTotal, 0);
      expect(r.grossRevenue, r.totalRevenue);
    });

    test('gross always reconciles with net plus discount', () {
      final r = groupSalesIntoReceipts([
        line('a', 850, 55.94),
        line('b', 45, 4.06),
      ]).single;
      expect(r.grossRevenue, closeTo(895.0, 1e-9));
      expect(r.totalRevenue, closeTo(835.0, 1e-9));
      expect(r.discountTotal, closeTo(60.0, 1e-9));
    });
  });
}
