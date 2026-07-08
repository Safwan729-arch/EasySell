import 'package:ai_shopkeeper/features/analytics/domain/analytics.dart';
import 'package:ai_shopkeeper/features/analytics/presentation/analytics_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A fixed reference: Thursday, 25 June 2026, 14:30.
  final now = DateTime(2026, 6, 25, 14, 30);

  group('periodSince — mirrors get_dashboard_summary date_trunc boundaries', () {
    test('week → start of ISO week (Monday, midnight)', () {
      // 25 Jun 2026 is a Thursday (weekday 4) → back up to Mon 22 Jun.
      expect(
        periodSince(AnalyticsPeriod.week, now: now),
        DateTime(2026, 6, 22),
      );
    });

    test('month → first of the calendar month, midnight', () {
      expect(
        periodSince(AnalyticsPeriod.month, now: now),
        DateTime(2026, 6, 1),
      );
    });

    test('all → no lower bound', () {
      expect(periodSince(AnalyticsPeriod.all, now: now), isNull);
    });

    test('today → midnight of the current day', () {
      expect(
        periodSince(AnalyticsPeriod.today, now: now),
        DateTime(2026, 6, 25),
      );
    });

    test('week boundary on a Monday returns the same day at midnight', () {
      final monday = DateTime(2026, 6, 22, 9); // Monday 09:00
      expect(
        periodSince(AnalyticsPeriod.week, now: monday),
        DateTime(2026, 6, 22),
      );
    });

    test('week boundary on a Sunday backs up six days', () {
      final sunday = DateTime(2026, 6, 28, 23); // Sunday 23:00
      expect(
        periodSince(AnalyticsPeriod.week, now: sunday),
        DateTime(2026, 6, 22),
      );
    });
  });
}
