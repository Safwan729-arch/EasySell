import 'package:ai_shopkeeper/features/transactions/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

/// History reads each sale with its delivery embedded
/// (`batch:product_batches(expiry_date)`), so the sale detail can show the
/// expiry date of the delivery the units came from.
void main() {
  const row = {
    'id': 't1',
    'shop_id': 's1',
    'product_id': 'p1',
    'type': 'sale',
    'quantity': 2,
  };

  test('the delivery and its expiry date are read from the row', () {
    final t = Transaction.fromJson({
      ...row,
      'batch_id': 'b1',
      'batch': {'expiry_date': '2026-11-20'},
    });
    expect(t.batchId, 'b1');
    expect(t.batchExpiry, DateTime(2026, 11, 20));
  });

  test('a sale from undated stock has no expiry date', () {
    final t = Transaction.fromJson({...row, 'batch_id': null, 'batch': null});
    expect(t.batchId, isNull);
    expect(t.batchExpiry, isNull);
  });

  test('a row read without the embed has no expiry date', () {
    final t = Transaction.fromJson({...row, 'batch_id': 'b1'});
    expect(t.batchExpiry, isNull);
  });

  test('the embedded date is never written back as a column', () {
    final json = Transaction.fromJson({
      ...row,
      'batch': {'expiry_date': '2026-11-20'},
    }).toJson();
    expect(json.containsKey('batch'), isFalse);
    expect(json.containsKey('batch_expiry'), isFalse);
  });
}
