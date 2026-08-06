import 'package:ai_shopkeeper/features/cart/presentation/cart_controller.dart';
import 'package:ai_shopkeeper/features/cart/presentation/cart_discount_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/cart_harness.dart';

void main() {
  test('starts at zero', () async {
    final c = await cartContainer();
    expect(c.read(cartDiscountControllerProvider), 0);
  });

  test('holds a discount that fits the cart', () async {
    final c = await cartContainer();
    c.read(cartControllerProvider.notifier).addOrIncrement(kOil, 1); // 850
    c.read(cartDiscountControllerProvider.notifier).setAmount(60);
    expect(c.read(cartDiscountControllerProvider), 60);
  });

  test('clamps down when the cart shrinks below the discount', () async {
    // The case that makes this controller necessary: the discount is entered
    // against one cart and the shopkeeper then empties most of it.
    final c = await cartContainer();
    c.read(cartControllerProvider.notifier).addOrIncrement(kOil, 1); // 850
    c.read(cartControllerProvider.notifier).addOrIncrement(kPepsi, 1); // 45
    c.read(cartDiscountControllerProvider.notifier).setAmount(300);
    expect(c.read(cartDiscountControllerProvider), 300);

    c.read(cartControllerProvider.notifier).remove('p2'); // 45 left
    expect(
      c.read(cartDiscountControllerProvider),
      45,
      reason: 'the stored value must never exceed the bill it is charged to',
    );
  });

  test('emptying the cart clears the discount', () async {
    final c = await cartContainer();
    c.read(cartControllerProvider.notifier).addOrIncrement(kOil, 1);
    c.read(cartDiscountControllerProvider.notifier).setAmount(60);
    c.read(cartControllerProvider.notifier).clear();
    expect(c.read(cartDiscountControllerProvider), 0);
  });

  test('clear() drops it', () async {
    final c = await cartContainer();
    c.read(cartControllerProvider.notifier).addOrIncrement(kOil, 1);
    c.read(cartDiscountControllerProvider.notifier).setAmount(60);
    c.read(cartDiscountControllerProvider.notifier).clear();
    expect(c.read(cartDiscountControllerProvider), 0);
  });

  test('a negative entry is refused', () async {
    final c = await cartContainer();
    c.read(cartControllerProvider.notifier).addOrIncrement(kOil, 1);
    c.read(cartDiscountControllerProvider.notifier).setAmount(-10);
    expect(c.read(cartDiscountControllerProvider), 0);
  });
}
