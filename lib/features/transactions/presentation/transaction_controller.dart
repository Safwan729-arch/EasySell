import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../../shared/providers/refresh_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../../expiry/domain/expiry_dates.dart';
import '../../expiry/presentation/expiry_prefs.dart';
import '../../expiry/presentation/expiry_providers.dart';
import '../../expiry/presentation/expiry_reconciler.dart';
import '../../expiry/presentation/today_provider.dart';
import '../../inventory/presentation/inventory_controller.dart';
import '../data/transaction_repository.dart';
import '../domain/transaction.dart';

/// Drives sale/restock actions. Stock changes show up live via the inventory
/// realtime stream, so this controller only needs to model the action state.
class TransactionController extends AsyncNotifier<void> {
  /// Same guard, and same reasoning, as [CartCheckoutController]: the restock
  /// sheet only disables its button on [AsyncLoading], which is a widget-layer
  /// guard that lands a rebuild later. Two overlapping restocks would both
  /// commit and add the stock twice, and neither the RPC nor any constraint can
  /// tell that apart from a shopkeeper genuinely restocking the same item
  /// twice.
  bool _inFlight = false;

  /// The restock id of the last restock that did not come back as a success,
  /// and the exact request it was sent with -- the `CartCheckoutController`
  /// pattern from 0010. A failure does not prove nothing was saved, so an
  /// identical retry re-sends the id and the server records it once. Anything
  /// changed (product, quantity, date) is a different restock and gets a new
  /// id.
  String? _pendingRestockId;
  String? _pendingRestockRequest;

  @override
  FutureOr<void> build() {
    _inFlight = false;
  }

  TransactionRepository get _repo => ref.read(transactionRepositoryProvider);
  String? get _shopId => ref.read(myShopProvider).value?.id;

  Future<bool> recordRestock({
    required String productId,
    required double quantity,
    String source = 'manual',
    DateTime? expiryDate,
  }) {
    final receivedOn = dateOnly(ref.read(nowProvider)());
    final request = jsonEncode({
      'product': productId,
      'quantity': quantity,
      'source': source,
      'expiry': expiryDate == null ? null : ymd(expiryDate),
      // The controller outlives the sheet. Without the day, an identical
      // restock days after an unanswered one would replay it and be
      // swallowed; a retry is the same day.
      'day': ymd(receivedOn),
    });
    if (request != _pendingRestockRequest) {
      _pendingRestockId = const Uuid().v4();
      _pendingRestockRequest = request;
    }
    final restockId = _pendingRestockId!;
    return _run(
      (shopId) => _repo.recordRestock(
        shopId: shopId,
        productId: productId,
        quantity: quantity,
        restockId: restockId,
        source: source,
        expiryDate: expiryDate,
        receivedOn: receivedOn,
      ),
      onSuccess: () {
        _pendingRestockId = null;
        _pendingRestockRequest = null;
        if (expiryDate != null) {
          ref.invalidate(batchesStreamProvider);
          unawaited(ref.read(expiryPrefsProvider.notifier).askPermissionOnce());
        }
        unawaited(ref.read(expiryReconcilerProvider).run());
      },
    );
  }

  Future<bool> _run(
    Future<Result<Transaction>> Function(String shopId) action, {
    void Function()? onSuccess,
  }) async {
    if (_inFlight) return false;

    final shopId = _shopId;
    if (shopId == null) {
      state = AsyncError(
        const AuthFailure('No shop found for this account.'),
        StackTrace.current,
      );
      return false;
    }

    state = const AsyncLoading();
    _inFlight = true;
    final Result<Transaction> result;
    try {
      result = await action(shopId);
    } finally {
      // Released in a finally so a throw can never wedge restock shut.
      _inFlight = false;
    }
    return result.when(
      success: (_) {
        onSuccess?.call();
        // Refresh inventory immediately so the new stock level shows at once.
        // Realtime normally pushes this products-row update, but invalidating
        // guarantees it even if realtime is unavailable or not yet enabled.
        ref.invalidate(productsStreamProvider);
        // Analytics/dashboard are RPC-backed, so nudge them to recompute too.
        ref.read(dataRefreshProvider.notifier).bump();
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

final transactionControllerProvider =
    AsyncNotifierProvider<TransactionController, void>(
      TransactionController.new,
    );
