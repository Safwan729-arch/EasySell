import 'package:ai_shopkeeper/shared/extensions/format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

/// Every figure on a dashboard card must render in the active language's digits.
/// Values that go through `NumberFormat` already do; these cover the helpers that
/// used to build their strings by hand (`'${k}K'`, `toStringAsFixed`), which are
/// always ASCII no matter what `Intl.defaultLocale` says.
void main() {
  tearDown(() => Intl.defaultLocale = null);

  /// Guards the whole class of bug rather than one example: if any Latin digit
  /// survives into a Bengali string, the app is mixing scripts on screen.
  final asciiDigit = RegExp(r'[0-9]');

  group('Money.compact under bn', () {
    setUp(() => Intl.defaultLocale = 'bn');

    test('the dashboard hero figure carries no Latin digits or "K"', () {
      // The reported case: a month's revenue of ~121,000 rendered "৳121K".
      final s = Money.compact(121000, currencyCode: 'BDT');
      expect(s, isNot(contains(asciiDigit)));
      expect(s, isNot(contains('K')));
      expect(s, '৳১.২১ লাখ');
    });

    test('abbreviates in লাখ, the unit the bn locale already groups by', () {
      expect(Money.compact(452180, currencyCode: 'BDT'), '৳৪.৫২ লাখ');
      expect(Money.compact(999499, currencyCode: 'BDT'), '৳৯.৯৯ লাখ');
      // >= 10 লাখ drops to 1 dp, same width rule English uses at >= 10M.
      expect(Money.compact(1926000, currencyCode: 'BDT'), '৳১৯.৩ লাখ');
    });

    test('rolls up to কোটি at 1,00,00,000', () {
      expect(Money.compact(10000000, currencyCode: 'BDT'), '৳১.০০ কোটি');
      expect(Money.compact(121000000, currencyCode: 'BDT'), '৳১২.১ কোটি');
      // Rounds to "100.0 লাখ", which must read as 1 কোটি instead.
      expect(Money.compact(9999900, currencyCode: 'BDT'), '৳১.০০ কোটি');
    });

    test('below the threshold still goes through simpleCurrency', () {
      expect(
        Money.compact(99999, currencyCode: 'BDT'),
        isNot(contains(asciiDigit)),
      );
    });

    test('negatives keep their sign', () {
      expect(Money.compact(-452180, currencyCode: 'BDT'), '-৳৪.৫২ লাখ');
    });

    test('the unknown-currency fallback localizes its digits too', () {
      expect(
        Money.format(1234.5, currencyCode: 'ZZZ'),
        isNot(contains(asciiDigit)),
      );
      expect(
        Money.compact(1234, currencyCode: 'ZZZ'),
        isNot(contains(asciiDigit)),
      );
    });
  });

  group('Money.compactCount under bn', () {
    setUp(() => Intl.defaultLocale = 'bn');

    test('compacts in লাখ with Bengali digits', () {
      expect(Money.compactCount(250000), '২.৫০ লাখ');
    });
  });

  group('Money.compact under en is unchanged', () {
    setUp(() => Intl.defaultLocale = 'en');

    test('keeps K/M and Western digits', () {
      expect(Money.compact(121000), r'$121K');
      expect(Money.compact(452180), r'$452K');
      expect(Money.compact(1284500), r'$1.28M');
      expect(Money.compact(19260000), r'$19.3M');
      expect(Money.compactCount(250000), '250K');
    });
  });

  group('Pct.format', () {
    test('matches the previous hand-rolled output under en', () {
      Intl.defaultLocale = 'en';
      // Was: toStringAsFixed(1) with a trailing ".0" trimmed off.
      expect(Pct.format(22.4), '22.4%');
      expect(Pct.format(14), '14%');
      expect(Pct.format(14.04), '14%');
      expect(Pct.format(0), '0%');
      expect(Pct.format(8.25), '8.3%');
    });

    test('uses Bengali digits under bn', () {
      Intl.defaultLocale = 'bn';
      // The reported case: the hero's margin stat rendered "22.4%".
      expect(Pct.format(22.4), '২২.৪%');
      expect(Pct.format(14), '১৪%');
    });
  });
}
