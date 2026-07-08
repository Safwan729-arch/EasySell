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
  group('groupSalesIntoReceipts', () {
    test('sales sharing a saleGroupId become one receipt', () {
      final sales = [_sale('a', group: 'g1'), _sale('b', group: 'g1'), _sale('c')];
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
