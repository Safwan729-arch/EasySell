import 'package:ai_shopkeeper/core/error/failure.dart';
import 'package:ai_shopkeeper/features/cart/domain/cart_line.dart';
import 'package:ai_shopkeeper/features/expiry/domain/expiry_estimate.dart';
import 'package:ai_shopkeeper/features/expiry/domain/product_batch.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/expiry_gate.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/expiry_reconciler.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:flutter_test/flutter_test.dart';

class _FixedReconciler implements ExpiryReconciler {
  _FixedReconciler(this.outcome);
  final ReconcileOutcome outcome;

  @override
  Future<ReconcileOutcome> run() async => outcome;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const pepsi = Product(id: 'pepsi', shopId: 's1', name: 'Pepsi', quantity: 6);
  final byProduct = estimateAll(
    products: [pepsi],
    openBatches: [
      ProductBatch(
        id: 'old',
        shopId: 's1',
        productId: 'pepsi',
        quantity: 5,
        receivedOn: DateTime(2026, 9, 1),
        expiryDate: DateTime(2026, 10, 20),
        expiredQty: 5,
      ),
    ],
    today: DateTime(2026, 10, 21),
    shopWarnDays: 7,
  );

  test('passes when every line fits in good stock', () async {
    final gate = ReconcilingExpiryGate(
      _FixedReconciler(ReconcileOutcome.ok(byProduct)),
    );
    expect(
      await gate.check([CartLine(product: pepsi, quantity: 1)]),
      isA<GatePass>(),
    );
  });

  test('blocks a line that would sell expired units', () async {
    final gate = ReconcilingExpiryGate(
      _FixedReconciler(ReconcileOutcome.ok(byProduct)),
    );
    final r = await gate.check([CartLine(product: pepsi, quantity: 3)]);
    expect(r, isA<GateBlocked>());
    expect((r as GateBlocked).productIds, ['pepsi']);
  });

  test('a failed reconcile is passed on as that failure', () async {
    final gate = ReconcilingExpiryGate(
      _FixedReconciler(
        const ReconcileOutcome.failed(NetworkFailure('offline')),
      ),
    );
    final r = await gate.check([CartLine(product: pepsi, quantity: 1)]);
    expect(r, isA<GateFailed>());
    expect((r as GateFailed).failure, isA<NetworkFailure>());
  });
}
