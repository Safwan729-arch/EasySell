import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../../shared/providers/refresh_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../../customers/presentation/customers_controller.dart';
import '../../customers/presentation/receivables_controller.dart';
import '../../inventory/presentation/inventory_controller.dart';
import '../../transactions/data/transaction_repository.dart';
import '../../transactions/domain/transaction.dart';
import '../domain/cart_math.dart';
import 'cart_controller.dart';
import 'cart_discount_controller.dart';

/// Drives the checkout action. Mirrors `TransactionController`: the cart's
/// contents live in [CartController] (always synchronously available so the
/// Cart screen can render the line list); this controller only models the
/// in-flight checkout call, so a loading/error state never hides the cart
/// itself.
class CartCheckoutController extends AsyncNotifier<void> {
  /// Guards against a second sale being committed while the first is still in
  /// flight. The Cart screen already disables the button on [AsyncLoading], but
  /// that guard lives in the widget layer and only takes effect on the next
  /// rebuild -- and this is the one call in the app that moves money and stock.
  ///
  /// Without it, two overlapping calls both read a still-unemptied cart (it is
  /// only cleared on success) and both commit: duplicate transactions under
  /// separate `sale_group_id`s and a doubled stock decrement, which no database
  /// constraint can reject because each call is individually valid.
  bool _inFlight = false;

  /// The sale id of the last checkout that did not come back as a success, and
  /// the exact request it was sent with.
  ///
  /// A failure does not prove the sale was not saved: on weak signal the server
  /// can commit and the reply can be lost. The cart is kept so the user can
  /// retry, and the retry re-sends this id, which the server records only once
  /// (migration 0010). The id is reused ONLY for an identical request. A
  /// changed cart, discount or customer is a different sale, and reusing the id
  /// would make the server hand back the old one and drop the change.
  String? _pendingSaleId;
  String? _pendingRequest;

  @override
  FutureOr<void> build() {
    // A rebuilt notifier has no call in flight; stale `true` would wedge
    // checkout permanently.
    _inFlight = false;
  }

  Future<bool> checkout({String source = 'manual', String? customerId}) async {
    if (_inFlight) return false;

    final shopId = ref.read(myShopProvider).value?.id;
    final lines = ref.read(cartControllerProvider);
    final discount = ref.read(cartDiscountControllerProvider);
    if (shopId == null) {
      state = AsyncError(
        const AuthFailure('No shop found for this account.'),
        StackTrace.current,
      );
      return false;
    }
    if (lines.isEmpty) return false;

    final items = cartItemsPayload(lines);
    final request = jsonEncode({
      'shop': shopId,
      'items': items,
      'source': source,
      'customer': customerId,
      'discount': discount,
    });
    if (request != _pendingRequest) {
      _pendingSaleId = const Uuid().v4();
      _pendingRequest = request;
    }

    state = const AsyncLoading();
    _inFlight = true;
    final Result<List<Transaction>> result;
    try {
      result = await ref
          .read(transactionRepositoryProvider)
          .recordSaleCart(
            shopId: shopId,
            items: items,
            saleGroupId: _pendingSaleId!,
            source: source,
            customerId: customerId,
            discount: discount,
          );
    } finally {
      // Released in a finally so a throw from the repository cannot wedge
      // checkout shut for the rest of the session.
      _inFlight = false;
    }
    return result.when(
      success: (_) {
        // The sale is recorded. An identical next sale is a real second sale
        // and needs its own id, or the server would drop it as a repeat.
        _pendingSaleId = null;
        _pendingRequest = null;
        ref.read(cartControllerProvider.notifier).clear();
        ref.read(cartDiscountControllerProvider.notifier).clear();
        ref.invalidate(productsStreamProvider);
        ref.read(dataRefreshProvider.notifier).bump();
        if (customerId != null) {
          ref.invalidate(customersControllerProvider);
          ref.invalidate(receivablesControllerProvider);
        }
        state = const AsyncData(null);
        return true;
      },
      failure: (f) {
        state = AsyncError(f, StackTrace.current);
        return false;
      },
    );
  }
}

final cartCheckoutControllerProvider =
    AsyncNotifierProvider<CartCheckoutController, void>(
      CartCheckoutController.new,
    );
