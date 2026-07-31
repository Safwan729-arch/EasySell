import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../../shared/providers/refresh_provider.dart';
import '../../auth/data/auth_repository.dart';
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
  }) {
    return _run(
      (shopId) => _repo.recordRestock(
        shopId: shopId,
        productId: productId,
        quantity: quantity,
        source: source,
      ),
    );
  }

  Future<bool> _run(
    Future<Result<Transaction>> Function(String shopId) action,
  ) async {
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
