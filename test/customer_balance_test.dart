import 'package:ai_shopkeeper/features/customers/domain/customer_balance.dart';
import 'package:ai_shopkeeper/features/customers/domain/ledger_entry.dart';
import 'package:ai_shopkeeper/features/customers/domain/receivables_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CustomerBalance.fromMap', () {
    test('parses numeric balance as double and flags who owes', () {
      final b = CustomerBalance.fromMap({
        'id': 'c1',
        'name': 'Rahim',
        'phone': '01700000000',
        'note': null,
        'balance': 150, // Postgres numeric may arrive as int or double
        'last_activity_at': '2026-07-17T10:00:00Z',
      });
      expect(b.name, 'Rahim');
      expect(b.balance, 150.0);
      expect(b.owes, isTrue);
    });

    test('a zero balance does not owe and tolerates a null last activity', () {
      final b = CustomerBalance.fromMap({
        'id': 'c2',
        'name': 'Karim',
        'phone': '01800000000',
        'note': 'next door',
        'balance': 0,
        'last_activity_at': null,
      });
      expect(b.owes, isFalse);
      expect(b.lastActivityAt, isNull);
      expect(b.note, 'next door');
    });
  });

  group('ReceivablesSummary.fromMap', () {
    test('parses totals', () {
      final s = ReceivablesSummary.fromMap({
        'total_owed': 4500,
        'debtor_count': 7,
      });
      expect(s.totalOwed, 4500.0);
      expect(s.debtorCount, 7);
    });

    test('empty is zero', () {
      expect(ReceivablesSummary.empty.totalOwed, 0);
      expect(ReceivablesSummary.empty.debtorCount, 0);
    });
  });

  group('LedgerEntryType', () {
    test('round-trips the db value', () {
      expect(LedgerEntryType.fromDb('credit_sale'), LedgerEntryType.creditSale);
      expect(LedgerEntryType.fromDb('payment'), LedgerEntryType.payment);
      expect(LedgerEntryType.creditSale.dbValue, 'credit_sale');
    });
  });
}
