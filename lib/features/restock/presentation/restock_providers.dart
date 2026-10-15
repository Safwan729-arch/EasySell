import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/refresh_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../../expiry/domain/expiry_estimate.dart';
import '../../expiry/presentation/expiry_providers.dart';
import '../../expiry/presentation/today_provider.dart';
import '../../inventory/presentation/inventory_controller.dart';
import '../data/restock_repository.dart';
import '../domain/restock_plan.dart';
import 'restock_prefs.dart';

/// Speeds by product id. Refetches after a sale or restock
/// ([dataRefreshProvider]) and when the local date changes.
///
/// No automatic retry: Riverpod's default retries ~10 times over ~40 s and
/// reports loading meanwhile, so a missing 0017 or no internet showed a
/// spinner instead of the error with its Retry button.
final restockSpeedsProvider =
    FutureProvider.autoDispose<Map<String, RestockSpeed>>(
      retry: (_, _) => null,
      (ref) async {
        ref.watch(dataRefreshProvider);
        final today = ref.watch(todayProvider);
        // Only the id: the shop record also reloads on an auth token refresh,
        // which refetched every speed. A failed lookup throws here, so it
        // shows as an error rather than as "nothing to restock".
        final shopId = await ref.watch(
          myShopProvider.selectAsync((s) => s?.id),
        );
        if (shopId == null) return const {};
        final offset = ref.read(nowProvider)().timeZoneOffset.inMinutes;
        final r = await ref
            .read(restockRepositoryProvider)
            .fetchSpeeds(shopId, today: today, utcOffsetMinutes: offset);
        return r.when(
          success: (l) => {for (final s in l) s.productId: s},
          failure: (f) => throw f,
        );
      },
    );

/// The Restock list. Days left and the suggestion use GOOD stock -- the app's
/// own expiry estimate -- so they are computed here, not in SQL (spec §5).
final restockPlanProvider = Provider.autoDispose<AsyncValue<RestockPlan>>((
  ref,
) {
  final speeds = ref.watch(restockSpeedsProvider);
  final productsAsync = ref.watch(productsStreamProvider);
  final byProduct = ref.watch(productExpiryProvider);
  final days = ref.watch(restockDaysProvider);
  // Not whenData: it turns a reload's AsyncLoading(previous) into a bare
  // AsyncLoading, so every restock blanked the list and the Home card. Keep
  // planning from the last values while new ones load.
  final s = speeds.value;
  final products = productsAsync.value;
  if (s != null && products != null) {
    return AsyncData(
      planRestock(
        products: products,
        speeds: s,
        goodStock: (p) => goodStockOf(p, byProduct),
        restockDays: days,
      ),
    );
  }
  // Nothing to plan from yet. Products still loading or failed must not read
  // as "Nothing to restock yet"; a Retry in flight shows as loading, not as
  // the old error.
  if (speeds.isLoading) return const AsyncLoading();
  if (speeds.hasError) {
    return AsyncError(speeds.error!, speeds.stackTrace ?? StackTrace.empty);
  }
  if (productsAsync.hasError) {
    return AsyncError(
      productsAsync.error!,
      productsAsync.stackTrace ?? StackTrace.empty,
    );
  }
  return const AsyncLoading();
});
