import 'package:ai_shopkeeper/features/cart/presentation/cart_checkout_controller.dart';
import 'package:ai_shopkeeper/features/cart/presentation/cart_controller.dart';
import 'package:ai_shopkeeper/features/cart/presentation/cart_discount_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/cart_harness.dart';

void main() {
  test('checkout sends the staged discount', () async {
    final repo = CapturingTransactionRepository();
    final c = await cartContainer(repo: repo);
    c.read(cartControllerProvider.notifier).addOrIncrement(kOil, 1); // 850
    c.read(cartDiscountControllerProvider.notifier).setAmount(60);

    final ok = await c.read(cartCheckoutControllerProvider.notifier).checkout();

    expect(ok, isTrue);
    expect(repo.sentDiscount, 60);
  });

  test('an undiscounted checkout sends zero', () async {
    final repo = CapturingTransactionRepository();
    final c = await cartContainer(repo: repo);
    c.read(cartControllerProvider.notifier).addOrIncrement(kOil, 1);

    await c.read(cartCheckoutControllerProvider.notifier).checkout();

    expect(repo.sentDiscount, 0);
  });

  test('a successful checkout clears the discount', () async {
    // The cart is already cleared on success; a discount that survived would
    // silently apply itself to the NEXT customer's sale.
    final repo = CapturingTransactionRepository();
    final c = await cartContainer(repo: repo);
    c.read(cartControllerProvider.notifier).addOrIncrement(kOil, 1);
    c.read(cartDiscountControllerProvider.notifier).setAmount(60);

    await c.read(cartCheckoutControllerProvider.notifier).checkout();

    expect(c.read(cartDiscountControllerProvider), 0);
    expect(c.read(cartControllerProvider), isEmpty);
  });
}
