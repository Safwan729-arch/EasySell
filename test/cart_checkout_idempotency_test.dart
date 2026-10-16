import 'package:ai_shopkeeper/core/error/failure.dart';
import 'package:ai_shopkeeper/core/error/result.dart';
import 'package:ai_shopkeeper/features/cart/presentation/cart_checkout_controller.dart';
import 'package:ai_shopkeeper/features/cart/presentation/cart_controller.dart';
import 'package:ai_shopkeeper/features/cart/presentation/cart_discount_controller.dart';
import 'package:ai_shopkeeper/features/transactions/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/cart_harness.dart';

/// Fails every call while [fail] is set, so a "sale saved but the reply was
/// lost" retry can be staged: from the app's side the two look identical.
class _FlakyRepo extends CapturingTransactionRepository {
  bool fail = true;
  final sentIds = <String>[];

  @override
  Future<Result<List<Transaction>>> recordSaleCart({
    required String shopId,
    required List<Map<String, dynamic>> items,
    required String saleGroupId,
    String source = 'manual',
    String? customerId,
    double discount = 0,
    bool digital = false,
  }) async {
    sentIds.add(saleGroupId);
    if (fail) return const Result.failure(NetworkFailure('timed out'));
    return const Result.success(<Transaction>[]);
  }
}

void main() {
  group('checkout sale id', () {
    test('a retry of the same cart reuses the sale id', () async {
      // The server records a given id once. Re-sending the id is what stops a
      // sale whose reply was lost from being recorded a second time.
      final repo = _FlakyRepo();
      final c = await cartContainer(repo: repo);
      c.read(cartControllerProvider.notifier).addOrIncrement(kOil, 1);
      final checkout = c.read(cartCheckoutControllerProvider.notifier);

      expect(await checkout.checkout(), isFalse);
      repo.fail = false;
      expect(await checkout.checkout(), isTrue);

      expect(repo.sentIds, hasLength(2));
      expect(repo.sentIds[1], repo.sentIds[0]);
    });

    test('changing the cart after a failure gets a new sale id', () async {
      // Reusing the id here would make the server hand back the OLD sale (if
      // the first attempt did save) and silently drop the new line.
      final repo = _FlakyRepo();
      final c = await cartContainer(repo: repo);
      final cart = c.read(cartControllerProvider.notifier);
      cart.addOrIncrement(kOil, 1);
      final checkout = c.read(cartCheckoutControllerProvider.notifier);

      await checkout.checkout();
      cart.addOrIncrement(kPepsi, 1);
      await checkout.checkout();

      expect(repo.sentIds[1], isNot(repo.sentIds[0]));
    });

    test('changing the discount after a failure gets a new sale id', () async {
      final repo = _FlakyRepo();
      final c = await cartContainer(repo: repo);
      c.read(cartControllerProvider.notifier).addOrIncrement(kOil, 1);
      final checkout = c.read(cartCheckoutControllerProvider.notifier);

      await checkout.checkout();
      c.read(cartDiscountControllerProvider.notifier).setAmount(50);
      await checkout.checkout();

      expect(repo.sentIds[1], isNot(repo.sentIds[0]));
    });

    test('changing the customer after a failure gets a new sale id', () async {
      final repo = _FlakyRepo();
      final c = await cartContainer(repo: repo);
      c.read(cartControllerProvider.notifier).addOrIncrement(kOil, 1);
      final checkout = c.read(cartCheckoutControllerProvider.notifier);

      await checkout.checkout();
      await checkout.checkout(customerId: 'c1');

      expect(repo.sentIds[1], isNot(repo.sentIds[0]));
    });

    test('the next sale after a success gets a new sale id', () async {
      // An identical next sale (same item, same quantity) is a real second
      // sale. Reusing the id would make the server drop it as a duplicate.
      final repo = _FlakyRepo()..fail = false;
      final c = await cartContainer(repo: repo);
      final cart = c.read(cartControllerProvider.notifier);
      final checkout = c.read(cartCheckoutControllerProvider.notifier);

      cart.addOrIncrement(kOil, 1);
      await checkout.checkout();
      cart.addOrIncrement(kOil, 1);
      await checkout.checkout();

      expect(repo.sentIds[1], isNot(repo.sentIds[0]));
    });
  });
}
