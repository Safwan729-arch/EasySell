import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/refresh_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../../expiry/domain/expiry_estimate.dart';
import '../../expiry/presentation/expiry_providers.dart';
import '../../expiry/presentation/today_provider.dart';
import '../../inventory/domain/product.dart';
import '../../inventory/presentation/inventory_controller.dart';
import '../data/restock_repository.dart';
import '../domain/restock_plan.dart';
import 'restock_prefs.dart';

/// Speeds by product id. Refetches after a sale or restock
/// ([dataRefreshProvider]) and when the local date changes.
final restockSpeedsProvider =
    FutureProvider.autoDispose<Map<String, RestockSpeed>>((ref) async {
      ref.watch(dataRefreshProvider);
      final shop = ref.watch(myShopProvider).value;
      if (shop == null) return const {};
      final today = ref.watch(todayProvider);
      final offset = ref.read(nowProvider)().timeZoneOffset.inMinutes;
      final r = await ref
          .watch(restockRepositoryProvider)
          .fetchSpeeds(shop.id, today: today, utcOffsetMinutes: offset);
      return r.when(
        success: (l) => {for (final s in l) s.productId: s},
        failure: (f) => throw f,
      );
    });

/// The Restock list. Days left and the suggestion use GOOD stock -- the app's
/// own expiry estimate -- so they are computed here, not in SQL (spec §5).
final restockPlanProvider = Provider.autoDispose<AsyncValue<RestockPlan>>((
  ref,
) {
  final speeds = ref.watch(restockSpeedsProvider);
  final products = ref.watch(productsStreamProvider).value ?? const <Product>[];
  final byProduct = ref.watch(productExpiryProvider);
  final days = ref.watch(restockDaysProvider);
  return speeds.whenData(
    (s) => planRestock(
      products: products,
      speeds: s,
      goodStock: (p) => goodStockOf(p, byProduct),
      restockDays: days,
    ),
  );
});
