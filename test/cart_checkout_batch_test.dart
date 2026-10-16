import 'package:ai_shopkeeper/core/error/failure.dart';
import 'package:ai_shopkeeper/core/error/result.dart';
import 'package:ai_shopkeeper/features/cart/domain/cart_line.dart';
import 'package:ai_shopkeeper/features/cart/presentation/cart_checkout_controller.dart';
import 'package:ai_shopkeeper/features/cart/presentation/cart_controller.dart';
import 'package:ai_shopkeeper/features/expiry/domain/batch_pick.dart';
import 'package:ai_shopkeeper/features/expiry/domain/expiry_estimate.dart';
import 'package:ai_shopkeeper/features/expiry/domain/product_batch.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/expiry_gate.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/transactions/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/cart_harness.dart';

const _brush = Product(
  id: 'brush',
  shopId: 's1',
  name: 'Toothbrush',
  sellingPrice: 5,
  quantity: 26,
);

ProductBatch _batch(String id, double qty, int expiryDay, {int created = 0}) =>
    ProductBatch(
      id: id,
      shopId: 's1',
      productId: 'brush',
      quantity: qty,
      receivedOn: DateTime(2026, 10, 15),
      expiryDate: DateTime(2026, 10, expiryDay),
      createdAt: DateTime(2026, 10, 15, 9, created),
    );

Map<String, ProductExpiry> _byProduct(double stock, List<ProductBatch> b) => {
  'brush': estimateProductExpiry(
    productId: 'brush',
    stock: stock,
    openBatches: b,
    today: DateTime(2026, 10, 15),
    shopWarnDays: 7,
  ),
};

final _both = _byProduct(26, [
  _batch('soon', 10, 16),
  _batch('fresh', 16, 21, created: 1),
]);

class _ScriptedGate implements ExpiryGate {
  _ScriptedGate(this.results);
  final List<GateResult> results;
  int _i = 0;

  @override
  Future<GateResult> check(List<CartLine> lines) async =>
      results[(_i++).clamp(0, results.length - 1)];
}

class _LosingRepo extends CapturingTransactionRepository {
  final sent = <List<Map<String, dynamic>>>[];

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
    );
    sent.add(items);
    return sent.length == 1
        ? const Result.failure(NetworkFailure('timed out'))
        : const Result.success(<Transaction>[]);
  }
}

void main() {
  test('a line with several batches and no choice is not sent', () async {
    final repo = CapturingTransactionRepository();
    final c = await cartContainer(
      repo: repo,
      gate: _ScriptedGate([GatePass(_both)]),
    );
    c.read(cartControllerProvider.notifier).addOrIncrement(_brush, 1);

    expect(
      await c.read(cartCheckoutControllerProvider.notifier).checkout(),
      isFalse,
    );
    expect(repo.calls, 0);
    final error = c.read(cartCheckoutControllerProvider).error;
    expect((error as Failure).code, ServerErrorCodes.batchNotChosen);
  });

  test('checkout sends the delivery the line sells from', () async {
    final repo = CapturingTransactionRepository();
    final c = await cartContainer(
      repo: repo,
      gate: _ScriptedGate([GatePass(_both)]),
    );
    final cart = c.read(cartControllerProvider.notifier);
    cart.addOrIncrement(_brush, 1);
    cart.setBatch('brush', 'fresh');

    expect(
      await c.read(cartCheckoutControllerProvider.notifier).checkout(),
      isTrue,
    );
    expect(repo.sentItems, [
      {'product_id': 'brush', 'quantity': 1.0, 'batch_id': 'fresh'},
    ]);
  });

  test('a chosen delivery without enough left is not sent', () async {
    final repo = CapturingTransactionRepository();
    final c = await cartContainer(
      repo: repo,
      gate: _ScriptedGate([GatePass(_both)]),
    );
    final cart = c.read(cartControllerProvider.notifier);
    cart.addOrIncrement(_brush, 11);
    cart.setBatch('brush', 'soon');

    expect(
      await c.read(cartCheckoutControllerProvider.notifier).checkout(),
      isFalse,
    );
    expect(repo.calls, 0);
    final error = c.read(cartCheckoutControllerProvider).error;
    expect((error as Failure).code, ServerErrorCodes.batchShortInCart);
  });

  test(
    'a retry after a lost reply resends the same deliveries and id',
    () async {
      // The first sale may be saved: 2 left "soon". Re-splitting from the
      // refreshed estimate would name "fresh" instead, a different request,
      // a new id -- and the sale would be recorded twice.
      final after = _byProduct(24, [
        _batch('soon', 10, 16).copyWith(pickedQty: 2),
        _batch('fresh', 16, 21, created: 1),
      ]);
      final repo = _LosingRepo();
      final c = await cartContainer(
        repo: repo,
        gate: _ScriptedGate([GatePass(_both), GatePass(after)]),
      );
      final cart = c.read(cartControllerProvider.notifier);
      cart.addOrIncrement(_brush, 12);
      cart.setBatch('brush', mixBatches);
      final checkout = c.read(cartCheckoutControllerProvider.notifier);

      expect(await checkout.checkout(), isFalse);
      expect(await checkout.checkout(), isTrue);

      expect(repo.sent[1], repo.sent[0]);
      expect(repo.sentGroupIds[1], repo.sentGroupIds[0]);
    },
  );

  test('changing the delivery is a new sale', () async {
    final repo = _LosingRepo();
    final c = await cartContainer(
      repo: repo,
      gate: _ScriptedGate([GatePass(_both)]),
    );
    final cart = c.read(cartControllerProvider.notifier);
    cart.addOrIncrement(_brush, 1);
    cart.setBatch('brush', 'soon');
    final checkout = c.read(cartCheckoutControllerProvider.notifier);

    expect(await checkout.checkout(), isFalse);
    expect(
      checkout.hasUnacknowledgedSale(c.read(cartControllerProvider)),
      isTrue,
    );
    cart.setBatch('brush', 'fresh');
    expect(
      checkout.hasUnacknowledgedSale(c.read(cartControllerProvider)),
      isFalse,
    );
    expect(await checkout.checkout(), isTrue);
    expect(repo.sentGroupIds[1], isNot(repo.sentGroupIds[0]));
  });
}
