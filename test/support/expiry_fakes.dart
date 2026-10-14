import 'package:ai_shopkeeper/features/cart/domain/cart_line.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/expiry_gate.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/expiry_reconciler.dart';

/// A reconcile that does nothing and succeeds -- for tests whose subject is
/// not expiry but whose code path triggers a reconcile.
class NoopReconciler implements ExpiryReconciler {
  int runs = 0;

  @override
  Future<ReconcileOutcome> run() async {
    runs++;
    return const ReconcileOutcome.ok({});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Lets every checkout through.
class PassingExpiryGate implements ExpiryGate {
  const PassingExpiryGate();

  @override
  Future<GateResult> check(List<CartLine> lines) async => const GatePass();
}

/// Always answers [result].
class FixedGate implements ExpiryGate {
  const FixedGate(this.result);
  final GateResult result;

  @override
  Future<GateResult> check(List<CartLine> lines) async => result;
}
