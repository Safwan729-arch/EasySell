import 'package:ai_shopkeeper/features/analytics/domain/analytics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dayParam — YYYY-MM-DD date-only formatting', () {
    test('drops the time component', () {
      expect(dayParam(DateTime(2026, 7, 2, 14, 30)), '2026-07-02');
    });

    test('zero-pads month and day', () {
      expect(dayParam(DateTime(2026, 1, 5)), '2026-01-05');
    });

    test('handles double-digit month and day', () {
      expect(dayParam(DateTime(2026, 12, 25, 23, 59)), '2026-12-25');
    });
  });
}
