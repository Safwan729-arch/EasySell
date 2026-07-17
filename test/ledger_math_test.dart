import 'package:ai_shopkeeper/features/customers/domain/ledger_entry.dart';
import 'package:ai_shopkeeper/features/customers/domain/ledger_math.dart';
import 'package:flutter_test/flutter_test.dart';

LedgerEntry _e(LedgerEntryType type, double amount) => LedgerEntry(
  id: 'x',
  customerId: 'c',
  entryType: type,
  amount: amount,
  createdAt: DateTime(2026, 7, 17),
);

void main() {
  group('balanceOf', () {
    test('an empty ledger is zero', () {
      expect(balanceOf(const []), 0);
    });

    test('credit sales add, payments subtract', () {
      final entries = [
        _e(LedgerEntryType.creditSale, 200),
        _e(LedgerEntryType.payment, 50),
        _e(LedgerEntryType.creditSale, 30),
      ];
      expect(balanceOf(entries), 180);
    });

    test('a fully paid customer nets to zero', () {
      final entries = [
        _e(LedgerEntryType.creditSale, 100),
        _e(LedgerEntryType.payment, 100),
      ];
      expect(balanceOf(entries), 0);
    });
  });
}
