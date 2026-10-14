import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../cart/domain/cart_line.dart';
import '../domain/cart_expiry.dart';
import '../domain/expiry_estimate.dart';
import 'expiry_reconciler.dart';

sealed class GateResult {
  const GateResult();
}

final class GatePass extends GateResult {
  const GatePass([this.byProduct = const {}]);

  /// The estimate the check was made on, fresh from the reconcile. Checkout
  /// splits the cart into deliveries from this, not from the screen's copy.
  final Map<String, ProductExpiry> byProduct;
}

final class GateBlocked extends GateResult {
  const GateBlocked(this.productIds);
  final List<String> productIds;
}

final class GateFailed extends GateResult {
  const GateFailed(this.failure);
  final Failure failure;
}

/// Runs before checkout records a sale (spec §4.2, §5 Cart): stores any
/// pending expired-count locks, then refuses a cart that would sell expired
/// units. The block lives in the app; `record_sale_cart` does not know about
/// expiry.
abstract class ExpiryGate {
  Future<GateResult> check(List<CartLine> lines);
}

class ReconcilingExpiryGate implements ExpiryGate {
  const ReconcilingExpiryGate(this._reconciler);

  final ExpiryReconciler _reconciler;

  @override
  Future<GateResult> check(List<CartLine> lines) async {
    final outcome = await _reconciler.run();
    if (outcome.failure case final failure?) return GateFailed(failure);
    final blocked = expiredBlockedProductIds(lines, outcome.byProduct);
    return blocked.isEmpty ? GatePass(outcome.byProduct) : GateBlocked(blocked);
  }
}

final expiryGateProvider = Provider<ExpiryGate>(
  (ref) => ReconcilingExpiryGate(ref.watch(expiryReconcilerProvider)),
);
