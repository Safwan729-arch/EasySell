import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../../inventory/domain/product.dart';
import '../domain/cart_line.dart';
import '../domain/cart_math.dart';

/// The shopkeeper's staged cart: products + quantities not yet committed.
/// Pure in-memory state -- nothing here touches the network; see
/// [CartCheckoutController] for the commit step. Cleared on successful
/// checkout, and whenever the signed-in shop changes: build() watches
/// [myShopProvider] so Riverpod reruns it (resetting to `[]`) on sign-out/
/// sign-in as a different account.
class CartController extends Notifier<List<CartLine>> {
  @override
  List<CartLine> build() {
    // Watched only to key this notifier's lifecycle to the signed-in shop;
    // the id itself isn't otherwise needed here. See class doc.
    ref.watch(myShopProvider).value?.id;
    return const [];
  }

  void addOrIncrement(Product product, double quantity) {
    state = addOrIncrementLine(state, product, quantity);
  }

  void updateQuantity(String productId, double quantity) {
    state = updateLineQuantity(state, productId, quantity);
  }

  void remove(String productId) {
    state = removeLine(state, productId);
  }

  void clear() => state = const [];

  /// Reverts the cart to a previously captured [snapshot]. Used by the
  /// "undo last add" affordance after a scan or voice add.
  void restore(List<CartLine> snapshot) => state = snapshot;

  /// How much more of [product] can still be added right now: current stock
  /// minus whatever quantity of it is already staged.
  double remainingStockFor(Product product) =>
      remainingStockForLines(state, product);
}

final cartControllerProvider =
    NotifierProvider<CartController, List<CartLine>>(CartController.new);
