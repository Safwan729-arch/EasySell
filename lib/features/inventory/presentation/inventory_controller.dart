import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../auth/data/auth_repository.dart';
import '../data/product_repository.dart';
import '../domain/product.dart';

/// Live list of the current shop's products (Supabase Realtime). The list UI
/// watches this; CRUD goes through [InventoryController], and realtime reflects
/// the change back automatically.
final productsStreamProvider = StreamProvider.autoDispose<List<Product>>((ref) {
  final shop = ref.watch(myShopProvider).value;
  if (shop == null) return Stream.value(const <Product>[]);
  return ref.watch(productRepositoryProvider).watchProducts(shop.id);
});

/// One-shot list of the current shop's *archived* (soft-deleted) products. Backs
/// the Archived products screen in Settings; restoring moves a product back into
/// [productsStreamProvider]. A plain fetch (not a stream) — see
/// [ProductRepository.fetchArchivedProducts] for why. Invalidate to refetch.
final archivedProductsProvider = FutureProvider.autoDispose<List<Product>>((
  ref,
) {
  final shop = ref.watch(myShopProvider).value;
  if (shop == null) return const <Product>[];
  return ref.watch(productRepositoryProvider).fetchArchivedProducts(shop.id);
});

/// Handles add/edit/delete actions. Models *actions*, so `build` returns void;
/// screens watch `isLoading` and listen for `AsyncError`.
class InventoryController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  ProductRepository get _repo => ref.read(productRepositoryProvider);
  String? get _shopId => ref.read(myShopProvider).value?.id;

  /// Saves a product. `draft` carries the form values; the shop id is injected
  /// here so the form never has to know it. Returns true on success.
  Future<bool> save(Product draft, {required bool isNew}) async {
    final shopId = _shopId;
    if (shopId == null) {
      state = AsyncError(
        const AuthFailure('No shop found for this account.'),
        StackTrace.current,
      );
      return false;
    }

    state = const AsyncLoading();
    final result = isNew
        ? await _repo.addProduct(draft.copyWith(shopId: shopId))
        : await _repo.updateProduct(draft);

    return result.when(
      success: (_) {
        // Refresh the list immediately. Realtime normally pushes this change,
        // but invalidating guarantees the user's own write is reflected even if
        // realtime is momentarily unavailable or not yet enabled on the table.
        ref.invalidate(productsStreamProvider);
        state = const AsyncData(null);
        return true;
      },
      failure: (f) {
        state = AsyncError(f, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> delete(String productId) async {
    state = const AsyncLoading();
    final result = await _repo.deleteProduct(productId);
    return result.when(
      success: (_) {
        ref.invalidate(productsStreamProvider);
        ref.invalidate(archivedProductsProvider);
        state = const AsyncData(null);
        return true;
      },
      failure: (f) {
        state = AsyncError(f, StackTrace.current);
        return false;
      },
    );
  }

  /// Restores an archived product back into the active inventory.
  Future<bool> restore(String productId) async {
    state = const AsyncLoading();
    final result = await _repo.restoreProduct(productId);
    return result.when(
      success: (_) {
        ref.invalidate(productsStreamProvider);
        ref.invalidate(archivedProductsProvider);
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

final inventoryControllerProvider =
    AsyncNotifierProvider<InventoryController, void>(InventoryController.new);
