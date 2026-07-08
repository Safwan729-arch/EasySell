import 'package:ai_shopkeeper/features/analytics/domain/analytics.dart';
import 'package:ai_shopkeeper/features/analytics/presentation/analytics_controller.dart';
import 'package:ai_shopkeeper/features/transactions/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _sale(String id, DateTime? at) => Transaction(
  id: id,
  shopId: 's',
  productId: 'p',
  type: 'sale',
  quantity: 1,
  sellingPrice: 10,
  createdAt: at,
);

void main() {
  // Fixed reference: Thursday, 25 June 2026, 14:30 (same as periodSince tests).
  final now = DateTime(2026, 6, 25, 14, 30);

  final today = _sale('today', DateTime(2026, 6, 25, 9)); // Thu, this week
  final thisWeek = _sale('week', DateTime(2026, 6, 23, 10)); // Tue, this week
  final thisMonth = _sale('month', DateTime(2026, 6, 5, 10)); // early June
  final lastMonth = _sale('lastmonth', DateTime(2026, 5, 20, 10));
  final noDate = _sale('nulldate', null);
  final onThe20th = _sale('day20', DateTime(2026, 6, 20, 15));

  final all = [today, thisWeek, thisMonth, lastMonth, noDate, onThe20th];

  List<String> ids(List<Transaction> l) => [for (final t in l) t.id];

  group('salesInScope — client-side period/day filtering (no network)', () {
    test('today keeps only sales at/after local midnight today', () {
      expect(
        ids(salesInScope(all, period: AnalyticsPeriod.today, now: now)),
        ['today'],
      );
    });

    test('week keeps sales at/after Monday of the current ISO week', () {
      expect(
        ids(salesInScope(all, period: AnalyticsPeriod.week, now: now)),
        ['today', 'week'],
      );
    });

    test('month keeps sales at/after the 1st of the calendar month', () {
      expect(
        ids(salesInScope(all, period: AnalyticsPeriod.month, now: now)),
        ['today', 'week', 'month', 'day20'],
      );
    });

    test('all has no lower bound and keeps everything, including null dates', () {
      expect(
        ids(salesInScope(all, period: AnalyticsPeriod.all, now: now)),
        ['today', 'week', 'month', 'lastmonth', 'nulldate', 'day20'],
      );
    });

    test('a picked day keeps only that calendar day (midnight to midnight)', () {
      expect(
        ids(
          salesInScope(
            all,
            period: AnalyticsPeriod.month,
            day: DateTime(2026, 6, 20),
            now: now,
          ),
        ),
        ['day20'],
      );
    });

    test('a picked day overrides the period entirely', () {
      // period=today would normally exclude the 20th, but day wins.
      expect(
        ids(
          salesInScope(
            all,
            period: AnalyticsPeriod.today,
            day: DateTime(2026, 6, 20),
            now: now,
          ),
        ),
        ['day20'],
      );
    });

    test('null created_at is excluded from bounded scopes', () {
      final result = salesInScope(all, period: AnalyticsPeriod.today, now: now);
      expect(result.any((t) => t.id == 'nulldate'), isFalse);
    });
  });
}
