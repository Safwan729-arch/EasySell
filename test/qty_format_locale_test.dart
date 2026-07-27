import 'package:ai_shopkeeper/shared/extensions/format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

void main() {
  tearDown(() => Intl.defaultLocale = null);

  test('Qty.format uses Bengali digits under bn locale', () {
    Intl.defaultLocale = 'bn';
    expect(Qty.format(1234), '১,২৩৪');
    expect(Qty.format(2.5), '২.৫');
  });

  test('Qty.format uses Western digits under en locale', () {
    Intl.defaultLocale = 'en';
    expect(Qty.format(1234), '1,234');
    expect(Qty.format(2.5), '2.5');
  });
}
