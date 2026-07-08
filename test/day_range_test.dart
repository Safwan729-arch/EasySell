import 'package:ai_shopkeeper/features/transactions/data/day_range.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dayRangeUtc — local calendar day to UTC half-open range', () {
    final range = dayRangeUtc(DateTime(2026, 6, 20));

    test('start is local midnight of the day', () {
      expect(range.startUtc, DateTime(2026, 6, 20).toUtc());
    });

    test('end is local midnight of the next day', () {
      expect(range.endUtc, DateTime(2026, 6, 21).toUtc());
    });

    test('a sale at 23:59:59 local sits inside the range', () {
      final at = DateTime(2026, 6, 20, 23, 59, 59).toUtc();
      expect(!at.isBefore(range.startUtc) && at.isBefore(range.endUtc), isTrue);
    });

    test('midnight of the next day is excluded (half-open)', () {
      final at = DateTime(2026, 6, 21).toUtc();
      expect(at.isBefore(range.endUtc), isFalse);
    });

    test('ignores the time component of the input day', () {
      final withTime = dayRangeUtc(DateTime(2026, 6, 20, 17, 45));
      expect(withTime.startUtc, range.startUtc);
      expect(withTime.endUtc, range.endUtc);
    });
  });
}
