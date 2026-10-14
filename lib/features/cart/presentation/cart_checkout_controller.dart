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
import '../../expiry/domain/batch_pick.dart';
import '../../expiry/domain/expiry_estimate.dart';
import '../../expiry/presentation/expiry_gate.dart';
import '../../expiry/presentation/expiry_reconciler.dart';
import '../../inventory/presentation/inventory_controller.dart';
import '../../transactions/data/transaction_repository.dart';
import '../../transactions/domain/transaction.dart';
import '../domain/cart_line.dart';
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

  /// The pending sale was SENT and no answer came back (a lost reply, a
  /// timeout), so it may already be saved. False when the gate stopped it
  /// before sending, or when the server answered with a refusal -- then the
  /// sale was certainly not recorded.
  bool _pendingUnacknowledged = false;

  /// The cart as the shopkeeper set it up (lines, chosen deliveries, discount,
  /// customer), and the items that were sent for it. A retry of an
  /// unacknowledged sale re-sends [_pendingItems] as they are: re-splitting
  /// the lines into deliveries from the refreshed estimate -- which already
  /// counts the saved sale -- would name other deliveries, make a different
  /// request with a new id, and record the sale twice.
  String? _pendingCart;
  String? _pendingLines;
  List<Map<String, dynamic>>? _pendingItems;

  @override
  FutureOr<void> build() {
    // A rebuilt notifier has no call in flight; stale `true` would wedge
    // checkout permanently.
    _inFlight = false;
  }

  String _linesKey(List<CartLine> lines) => jsonEncode([
    for (final l in lines) [l.product.id, l.quantity, l.batchId],
  ]);

  /// [lines] are exactly a sale that was sent and never acknowledged. After a
  /// lost reply the refreshed stock can make the SAME cart look too big or
  /// expired; the cart must still let it be retried, because the server
  /// replays a saved sale and editing the cart instead (a new request, a new
  /// sale id) would record it twice (expiry review #1, migration 0010).
  bool hasUnacknowledgedSale(List<CartLine> lines) =>
      _pendingUnacknowledged && _pendingLines == _linesKey(lines);

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

    final cart = jsonEncode({
      'shop': shopId,
      'lines': _linesKey(lines),
      'source': source,
      'customer': customerId,
      'discount': discount,
    });
    // An identical retry of a sale that may already be saved: the server will
    // replay it, so neither the expiry block nor a fresh split into
    // deliveries may stand in its way.
    final isUnacknowledgedRetry =
        cart == _pendingCart && _pendingUnacknowledged;

    state = const AsyncLoading();
    _inFlight = true;
    final Result<List<Transaction>> result;
    try {
      // Expiry gate BEFORE the sale (expiry spec §4.2, §5 Cart): it first
      // stores any pending expired-count locks -- otherwise this sale would
      // shrink the expired count -- then refuses a cart that would sell
      // expired units. With no signal the gate fails, and the sale could not
      // have reached the server either.
      final Map<String, ProductExpiry> byProduct;
      switch (await ref.read(expiryGateProvider).check(lines)) {
        case GateFailed(:final failure):
          state = AsyncError(failure, StackTrace.current);
          return false;
        case GateBlocked() when isUnacknowledgedRetry:
          byProduct = const {};
        case GateBlocked():
          state = AsyncError(
            const DatabaseFailure(
              'Expired stock in the cart.',
              code: ServerErrorCodes.expiredStockInCart,
            ),
            StackTrace.current,
          );
          return false;
        case GatePass(byProduct: final fresh):
          byProduct = fresh;
      }

      final List<Map<String, dynamic>> items;
      if (isUnacknowledgedRetry) {
        items = _pendingItems!;
      } else {
        // Split from the gate's FRESH estimate: the screen's copy can be a
        // sale or a restock behind.
        final split = resolveSaleItems(lines, byProduct);
        if (split.unchosen.isNotEmpty) {
          state = AsyncError(
            const DatabaseFailure(
              'Choose a batch for each marked item.',
              code: ServerErrorCodes.batchNotChosen,
            ),
            StackTrace.current,
          );
          return false;
        }
        if (split.short.isNotEmpty) {
          state = AsyncError(
            const DatabaseFailure(
              'A chosen delivery has too few left.',
              code: ServerErrorCodes.batchShortInCart,
            ),
            StackTrace.current,
          );
          return false;
        }
        items = split.items;
        final request = jsonEncode({'cart': cart, 'items': items});
        if (request != _pendingRequest) {
          _pendingSaleId = const Uuid().v4();
          _pendingRequest = request;
        }
        _pendingCart = cart;
        _pendingLines = _linesKey(lines);
        _pendingItems = items;
      }
      // From here the outcome is unknown until an answer arrives.
      _pendingUnacknowledged = true;
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
        _pendingCart = null;
        _pendingLines = null;
        _pendingItems = null;
        _pendingUnacknowledged = false;
        ref.read(cartControllerProvider.notifier).clear();
        ref.read(cartDiscountControllerProvider.notifier).clear();
        ref.invalidate(productsStreamProvider);
        ref.read(dataRefreshProvider.notifier).bump();
        // Stock went down: a delivery may now be sold out (spec §4.2).
        unawaited(ref.read(expiryReconcilerProvider).run());
        if (customerId != null) {
          ref.invalidate(customersControllerProvider);
          ref.invalidate(receivablesControllerProvider);
        }
        state = const AsyncData(null);
        return true;
      },
      failure: (f) {
        // The server answered with a refusal (stock, discount ...): the RPC is
        // atomic, so nothing was recorded. Only a missing answer leaves the
        // sale possibly saved.
        if (f is DatabaseFailure) _pendingUnacknowledged = false;
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
