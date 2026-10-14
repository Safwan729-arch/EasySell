import 'package:ai_shopkeeper/features/expiry/domain/expiry_dates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dateOnly drops the time of day', () {
    expect(dateOnly(DateTime(2026, 10, 20, 23, 59)), DateTime(2026, 10, 20));
  });

  test('daysBetween counts calendar days and can be negative', () {
    expect(daysBetween(DateTime(2026, 10, 13), DateTime(2026, 10, 18)), 5);
    expect(
      daysBetween(DateTime(2026, 10, 18, 23), DateTime(2026, 10, 19, 1)),
      1,
    );
    expect(daysBetween(DateTime(2026, 10, 20), DateTime(2026, 10, 18)), -2);
  });

  test('ymd is the Postgres date wire format', () {
    expect(ymd(DateTime(2026, 1, 5)), '2026-01-05');
  });

  group('classifyExpiryDate', () {
    final today = DateTime(2026, 10, 14);
    test('a past date is flagged', () {
      expect(classifyExpiryDate(DateTime(2026, 10, 13), today), OddDate.past);
    });
    test('today and the near future are fine', () {
      expect(classifyExpiryDate(today, today), OddDate.none);
      expect(classifyExpiryDate(DateTime(2031, 10, 14), today), OddDate.none);
    });
    test('more than five years ahead is flagged', () {
      expect(
        classifyExpiryDate(DateTime(2031, 10, 15), today),
        OddDate.farFuture,
      );
    });
  });
}
