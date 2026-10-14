import 'package:ai_shopkeeper/core/error/failure.dart';
import 'package:ai_shopkeeper/features/cart/presentation/cart_checkout_controller.dart';
import 'package:ai_shopkeeper/features/cart/presentation/cart_controller.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/expiry_gate.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/cart_harness.dart';
import 'support/expiry_fakes.dart';

void main() {
  test(
    'a cart that would sell expired units is refused before the sale',
    () async {
      final repo = CapturingTransactionRepository();
      final c = await cartContainer(
        repo: repo,
        gate: const FixedGate(GateBlocked(['p2'])),
      );
      c.read(cartControllerProvider.notifier).addOrIncrement(kOil, 1);

      final ok = await c
          .read(cartCheckoutControllerProvider.notifier)
          .checkout();

      expect(ok, isFalse);
      expect(repo.calls, 0);
      final error = c.read(cartCheckoutControllerProvider).error;
      expect(error, isA<Failure>());
      expect((error as Failure).code, ServerErrorCodes.expiredStockInCart);
      // The cart is kept so the shopkeeper can fix it.
      expect(c.read(cartControllerProvider), isNotEmpty);
    },
  );

  test('a failed expiry check stops checkout with that failure', () async {
    final repo = CapturingTransactionRepository();
    final c = await cartContainer(
      repo: repo,
      gate: const FixedGate(GateFailed(NetworkFailure('offline'))),
    );
    c.read(cartControllerProvider.notifier).addOrIncrement(kOil, 1);

    final ok = await c.read(cartCheckoutControllerProvider.notifier).checkout();

    expect(ok, isFalse);
    expect(repo.calls, 0);
    expect(c.read(cartCheckoutControllerProvider).error, isA<NetworkFailure>());
  });

  test('a passing check records the sale as before', () async {
    final repo = CapturingTransactionRepository();
    final c = await cartContainer(repo: repo);
    c.read(cartControllerProvider.notifier).addOrIncrement(kOil, 1);

    expect(
      await c.read(cartCheckoutControllerProvider.notifier).checkout(),
      isTrue,
    );
    expect(repo.calls, 1);
  });
}
