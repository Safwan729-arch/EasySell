import 'package:ai_shopkeeper/core/error/failure.dart';
import 'package:ai_shopkeeper/core/error/result.dart';
import 'package:ai_shopkeeper/features/cart/domain/cart_line.dart';
import 'package:ai_shopkeeper/features/cart/presentation/cart_checkout_controller.dart';
import 'package:ai_shopkeeper/features/cart/presentation/cart_controller.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/expiry_gate.dart';
import 'package:ai_shopkeeper/features/transactions/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/cart_harness.dart';

/// Answers each checkout from [results] in turn (the last one repeats).
class _ScriptedRepo extends CapturingTransactionRepository {
  _ScriptedRepo(this.results);
  final List<Result<List<Transaction>>> results;
  final sentIds = <String>[];

  @override
  Future<Result<List<Transaction>>> recordSaleCart({
    required String shopId,
    required List<Map<String, dynamic>> items,
    required String saleGroupId,
    String source = 'manual',
    String? customerId,
    double discount = 0,
  }) async {
    sentIds.add(saleGroupId);
    return results[(sentIds.length - 1).clamp(0, results.length - 1)];
  }
}

/// Answers each check from [results] in turn (the last one repeats).
class _ScriptedGate implements ExpiryGate {
  _ScriptedGate(this.results);
  final List<GateResult> results;
  int _i = 0;

  @override
  Future<GateResult> check(List<CartLine> lines) async =>
      results[(_i++).clamp(0, results.length - 1)];
}

const _lost = Result<List<Transaction>>.failure(NetworkFailure('timed out'));
const _ok = Result<List<Transaction>>.success(<Transaction>[]);
const _refused = Result<List<Transaction>>.failure(
  DatabaseFailure('Insufficient stock for Oil: have 0, need 1'),
);

void main() {
  // After a lost reply the sale may already be saved, and the refreshed stock
  // then makes the SAME cart look too big or expired. Blocking that retry is
  // what pushes the shopkeeper to edit the cart -- a new request, a new sale
  // id -- and the sale is recorded twice (the bug 0010 fixed).
  test(
    'an unacknowledged sale is retried even when the gate now blocks',
    () async {
      final repo = _ScriptedRepo([_lost, _ok]);
      final c = await cartContainer(
        repo: repo,
        gate: _ScriptedGate([
          const GatePass(),
          const GateBlocked(['p2']),
        ]),
      );
      c.read(cartControllerProvider.notifier).addOrIncrement(kOil, 1);
      final checkout = c.read(cartCheckoutControllerProvider.notifier);

      expect(await checkout.checkout(), isFalse);
      expect(await checkout.checkout(), isTrue);

      expect(repo.sentIds, hasLength(2));
      expect(repo.sentIds[1], repo.sentIds[0]);
    },
  );

  test('a cart that never reached the server is still blocked', () async {
    final repo = _ScriptedRepo([_ok]);
    final c = await cartContainer(
      repo: repo,
      gate: _ScriptedGate([
        const GateFailed(NetworkFailure('offline')),
        const GateBlocked(['p2']),
      ]),
    );
    c.read(cartControllerProvider.notifier).addOrIncrement(kOil, 1);
    final checkout = c.read(cartCheckoutControllerProvider.notifier);

    expect(await checkout.checkout(), isFalse);
    expect(await checkout.checkout(), isFalse);

    expect(repo.sentIds, isEmpty);
    final error = c.read(cartCheckoutControllerProvider).error;
    expect((error as Failure).code, ServerErrorCodes.expiredStockInCart);
  });

  test('a sale the server refused is not treated as a retry', () async {
    final repo = _ScriptedRepo([_refused, _ok]);
    final c = await cartContainer(
      repo: repo,
      gate: _ScriptedGate([
        const GatePass(),
        const GateBlocked(['p2']),
      ]),
    );
    c.read(cartControllerProvider.notifier).addOrIncrement(kOil, 1);
    final checkout = c.read(cartCheckoutControllerProvider.notifier);

    expect(await checkout.checkout(), isFalse);
    expect(await checkout.checkout(), isFalse);
    expect(repo.sentIds, hasLength(1));
  });

  test('the cart knows when its lines are an unacknowledged sale', () async {
    final repo = _ScriptedRepo([_lost]);
    final c = await cartContainer(repo: repo);
    final cart = c.read(cartControllerProvider.notifier);
    cart.addOrIncrement(kOil, 1);
    final checkout = c.read(cartCheckoutControllerProvider.notifier);

    expect(
      checkout.hasUnacknowledgedSale(c.read(cartControllerProvider)),
      isFalse,
    );
    await checkout.checkout();
    expect(
      checkout.hasUnacknowledgedSale(c.read(cartControllerProvider)),
      isTrue,
    );
    cart.addOrIncrement(kOil, 1);
    expect(
      checkout.hasUnacknowledgedSale(c.read(cartControllerProvider)),
      isFalse,
    );
  });
}
