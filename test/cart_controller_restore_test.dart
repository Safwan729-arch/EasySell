// test/cart_controller_restore_test.dart
import 'package:ai_shopkeeper/features/auth/data/auth_repository.dart';
import 'package:ai_shopkeeper/features/auth/domain/shop.dart';
import 'package:ai_shopkeeper/features/cart/presentation/cart_controller.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Product _p(String id) => Product(id: id, shopId: 's', name: 'Item $id', quantity: 100);

ProviderContainer _container() => ProviderContainer(
  overrides: [
    myShopProvider.overrideWith(
      (ref) => const Shop(id: 's', ownerId: 'o', name: 'Shop', currency: 'USD'),
    ),
  ],
);

void main() {
  test('restore returns the cart to a captured snapshot', () {
    final c = _container();
    final notifier = c.read(cartControllerProvider.notifier);

    notifier.addOrIncrement(_p('a'), 2);
    final snapshot = c.read(cartControllerProvider); // [a x2]

    notifier.addOrIncrement(_p('b'), 5); // cart now [a x2, b x5]
    expect(c.read(cartControllerProvider).length, 2);

    notifier.restore(snapshot);
    expect(c.read(cartControllerProvider), equals(snapshot));
    expect(c.read(cartControllerProvider).length, 1);
    expect(c.read(cartControllerProvider).first.quantity, 2);
  });
}
