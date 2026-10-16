import 'package:ai_shopkeeper/core/error/failure.dart';
import 'package:ai_shopkeeper/core/error/result.dart';
import 'package:ai_shopkeeper/features/cart/presentation/cart_checkout_controller.dart';
import 'package:ai_shopkeeper/features/cart/presentation/cart_controller.dart';
import 'package:ai_shopkeeper/features/transactions/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/cart_harness.dart';

/// Fails while [fail] is set, so a retry after a lost reply can be staged.
class _FlakyRepo extends CapturingTransactionRepository {
  bool fail = true;

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
    await super.recordSaleCart(
      shopId: shopId,
      items: items,
      saleGroupId: saleGroupId,
      digital: digital,
    );
    if (fail) return const Result.failure(NetworkFailure('timed out'));
    return const Result.success(<Transaction>[]);
  }
}

void main() {
  test('a cash sale is sent as not digital', () async {
    final repo = CapturingTransactionRepository();
    final c = await cartContainer(repo: repo);
    c.read(cartControllerProvider.notifier).addOrIncrement(kOil, 1);

    await c.read(cartCheckoutControllerProvider.notifier).checkout();

    expect(repo.sentDigital, isFalse);
  });

  test('a digital sale is sent as digital', () async {
    final repo = CapturingTransactionRepository();
    final c = await cartContainer(repo: repo);
    c.read(cartControllerProvider.notifier).addOrIncrement(kOil, 1);

    await c
        .read(cartCheckoutControllerProvider.notifier)
        .checkout(digital: true);

    expect(repo.sentDigital, isTrue);
  });

  test(
    'switching cash to digital after a failure gets a new sale id',
    () async {
      // Same rule as a changed customer: re-sending the old id would make the
      // server hand back the first attempt (if it did save) as a cash sale and
      // drop the switch to digital.
      final repo = _FlakyRepo();
      final c = await cartContainer(repo: repo);
      c.read(cartControllerProvider.notifier).addOrIncrement(kOil, 1);
      final checkout = c.read(cartCheckoutControllerProvider.notifier);

      await checkout.checkout();
      await checkout.checkout(digital: true);

      expect(repo.sentGroupIds, hasLength(2));
      expect(repo.sentGroupIds[1], isNot(repo.sentGroupIds[0]));
    },
  );
}
