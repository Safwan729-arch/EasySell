import 'package:flutter_test/flutter_test.dart';
import 'package:ai_shopkeeper/shared/extensions/format.dart';

void main() {
  group('Qty.format (trailing-zero trimming — the one shared quantity helper)', () {
    test('whole numbers drop the decimal', () {
      expect(Qty.format(12), '12');
      expect(Qty.format(0), '0');
      expect(Qty.format(4.0), '4');
    });

    test('fractional values keep only the needed digits', () {
      expect(Qty.format(2.5), '2.5');
      expect(Qty.format(0.5), '0.5');
      expect(Qty.format(1.25), '1.25');
    });
  });

  group('Money.compact (Conservative, threshold 100,000)', () {
    test('below threshold shows full digits, no cents', () {
      expect(Money.compact(430), r'$430');
      expect(Money.compact(1284), r'$1,284');
      expect(Money.compact(99999), r'$99,999');
    });

    test('100K..999K shows K form', () {
      expect(Money.compact(100000), r'$100K');
      expect(Money.compact(452180), r'$452K');
      expect(Money.compact(999499), r'$999K');
    });

    test('millions show M form', () {
      expect(Money.compact(1284500), r'$1.28M');
      expect(Money.compact(19260000), r'$19.3M'); // 1 dp at >= 10M
    });

    test('negatives keep their sign', () {
      expect(Money.compact(-430), r'-$430');
      expect(Money.compact(-452180), r'-$452K');
    });
  });

  group('Money.compactCount', () {
    test('below threshold shows full integer', () {
      expect(Money.compactCount(86), '86');
      expect(Money.compactCount(12480), '12,480');
    });

    test('at/above threshold compacts', () {
      expect(Money.compactCount(100000), '100K');
      expect(Money.compactCount(250000), '250K');
    });
  });
}
