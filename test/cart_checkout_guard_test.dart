import 'dart:async';

import 'package:ai_shopkeeper/core/error/failure.dart';
import 'package:ai_shopkeeper/core/error/result.dart';
import 'package:ai_shopkeeper/features/auth/data/auth_repository.dart';
import 'package:ai_shopkeeper/features/auth/domain/shop.dart';
import 'package:ai_shopkeeper/features/cart/domain/cart_line.dart';
import 'package:ai_shopkeeper/features/cart/presentation/cart_checkout_controller.dart';
import 'package:ai_shopkeeper/features/cart/presentation/cart_controller.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/expiry_gate.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/expiry_reconciler.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/transactions/data/transaction_repository.dart';
import 'package:ai_shopkeeper/features/transactions/domain/transaction.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/expiry_fakes.dart';

class _SeededCart extends CartController {
  _SeededCart(this._seed);
  final List<CartLine> _seed;
  @override
  List<CartLine> build() => _seed;
}

/// Counts calls and stays in flight until released, so two overlapping
/// checkouts can be observed rather than inferred.
class _PendingTxRepo implements TransactionRepository {
  final completer = Completer<Result<List<Transaction>>>();
  int cartCalls = 0;

  @override
  Future<Result<List<Transaction>>> recordSaleCart({
    required String shopId,
    required List<Map<String, dynamic>> items,
    required String saleGroupId,
    String source = 'manual',
    String? customerId,
    double discount = 0,
    bool digital = false,
  }) {
    cartCalls++;
    return completer.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _line = CartLine(
  product: const Product(
    id: 'p1',
    shopId: 's',
    name: 'Rice',
    sellingPrice: 50,
    quantity: 10,
  ),
  quantity: 2,
);

ProviderContainer _container(TransactionRepository repo) {
  final container = ProviderContainer(
    overrides: [
      cartControllerProvider.overrideWith(() => _SeededCart([_line])),
      myShopProvider.overrideWith(
        (ref) => const Shop(
          id: 's',
          ownerId: 'o',
          name: 'Test Shop',
          currency: 'USD',
        ),
      ),
      transactionRepositoryProvider.overrideWithValue(repo),
      expiryGateProvider.overrideWithValue(const PassingExpiryGate()),
      expiryReconcilerProvider.overrideWithValue(NoopReconciler()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('CartCheckoutController double-submit guard', () {
    test('a second checkout while one is still in flight does not issue a '
        'second sale', () async {
      final repo = _PendingTxRepo();
      final c = _container(repo);
      await c.read(myShopProvider.future);
      final notifier = c.read(cartCheckoutControllerProvider.notifier);

      final first = notifier.checkout();
      final second = notifier.checkout(); // before the first resolves
      // Checkout awaits the expiry gate before the RPC, so let that settle;
      // the guard has already refused the second call by now.
      await Future<void>.delayed(Duration.zero);

      // One sale, not two. Without a guard both reads see a non-empty cart
      // (it is only cleared on success) and both RPCs commit -- duplicate
      // transactions and a double stock decrement.
      expect(repo.cartCalls, 1);
      expect(await second, isFalse);

      repo.completer.complete(const Result.success(<Transaction>[]));
      expect(await first, isTrue);
    });

    test('a later checkout still works once the first has finished', () async {
      final repo = _PendingTxRepo();
      final c = _container(repo);
      await c.read(myShopProvider.future);
      final notifier = c.read(cartCheckoutControllerProvider.notifier);

      final first = notifier.checkout();
      repo.completer.complete(const Result.success(<Transaction>[]));
      await first;

      // A successful checkout empties the cart, so staging a new sale is what
      // a real second checkout looks like. The guard must release, not latch.
      c.read(cartControllerProvider.notifier).addOrIncrement(_line.product, 1);
      await notifier.checkout();
      expect(repo.cartCalls, 2);
    });

    test(
      'a failed checkout releases the guard so the user can retry',
      () async {
        final repo = _PendingTxRepo();
        final c = _container(repo);
        await c.read(myShopProvider.future);
        final notifier = c.read(cartCheckoutControllerProvider.notifier);

        final first = notifier.checkout();
        repo.completer.complete(
          const Result.failure(DatabaseFailure('Insufficient stock')),
        );
        expect(await first, isFalse);

        await notifier.checkout();
        expect(repo.cartCalls, 2);
      },
    );
  });
}
