import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../shared/providers/refresh_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../../inventory/presentation/inventory_controller.dart';
import '../../transactions/data/transaction_repository.dart';
import '../domain/cart_math.dart';
import 'cart_controller.dart';

/// Drives the checkout action. Mirrors `TransactionController`: the cart's
/// contents live in [CartController] (always synchronously available so the
/// Cart screen can render the line list); this controller only models the
/// in-flight checkout call, so a loading/error state never hides the cart
/// itself.
class CartCheckoutController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<bool> checkout({String source = 'manual'}) async {
    final shopId = ref.read(myShopProvider).value?.id;
    final lines = ref.read(cartControllerProvider);
    if (shopId == null) {
      state = AsyncError(
        const AuthFailure('No shop found for this account.'),
        StackTrace.current,
      );
      return false;
    }
    if (lines.isEmpty) return false;

    state = const AsyncLoading();
    final result = await ref
        .read(transactionRepositoryProvider)
        .recordSaleCart(
          shopId: shopId,
          items: cartItemsPayload(lines),
          source: source,
        );
    return result.when(
      success: (_) {
        ref.read(cartControllerProvider.notifier).clear();
        ref.invalidate(productsStreamProvider);
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

final cartCheckoutControllerProvider =
    AsyncNotifierProvider<CartCheckoutController, void>(
      CartCheckoutController.new,
    );
