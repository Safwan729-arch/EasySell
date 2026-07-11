import 'package:ai_shopkeeper/features/onboarding/domain/currency_option.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('BDT is the first (default) option and carries the ৳ symbol', () {
    expect(ShopCurrency.values.first, ShopCurrency.bdt);
    expect(ShopCurrency.bdt.code, 'BDT');
    expect(ShopCurrency.bdt.symbol, '৳');
  });

  test('USD carries the \$ symbol', () {
    expect(ShopCurrency.usd.code, 'USD');
    expect(ShopCurrency.usd.symbol, '\$');
  });

  test('fromCode maps a stored code back, falling back to BDT', () {
    expect(ShopCurrency.fromCode('USD'), ShopCurrency.usd);
    expect(ShopCurrency.fromCode('BDT'), ShopCurrency.bdt);
    expect(ShopCurrency.fromCode('EUR'), ShopCurrency.bdt); // unknown → default
  });
}
