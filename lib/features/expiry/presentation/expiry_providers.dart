import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../../cart/presentation/cart_controller.dart';
import '../../inventory/domain/product.dart';
import '../../inventory/presentation/inventory_controller.dart';
import '../data/batch_repository.dart';
import '../domain/cart_expiry.dart';
import '../domain/expiry_alerts.dart';
import '../domain/expiry_estimate.dart';
import '../domain/product_batch.dart';
import '../domain/removal_loss.dart';
import 'expiry_prefs.dart';
import 'expiry_reconciler.dart';
import 'today_provider.dart';

/// The shop's open deliveries. Initial rows only (no realtime publication) --
/// invalidate after a write, as with `productsStreamProvider`.
final batchesStreamProvider = StreamProvider.autoDispose<List<ProductBatch>>((
  ref,
) {
  final shop = ref.watch(myShopProvider).value;
  if (shop == null) return Stream.value(const <ProductBatch>[]);
  return ref.watch(batchRepositoryProvider).watchOpenBatches(shop.id);
});

/// The estimate for every product with open deliveries, for DISPLAY. Writes
/// never come from here -- see `ExpiryReconciler`. While either stream is
/// loading or has failed (offline, or tests without a backend) this is empty,
/// which means "no expiry information": everything behaves as before.
final productExpiryProvider = Provider.autoDispose<Map<String, ProductExpiry>>((
  ref,
) {
  final products = ref.watch(productsStreamProvider).value ?? const <Product>[];
  final batches =
      ref.watch(batchesStreamProvider).value ?? const <ProductBatch>[];
  if (batches.isEmpty) return const {};
  return estimateAll(
    products: products,
    openBatches: batches,
    today: ref.watch(todayProvider),
    shopWarnDays: ref.watch(expiryPrefsProvider.select((p) => p.warnDays)),
  );
});

/// Units of a product that may be sold (stock minus expired units).
final goodStockProvider = Provider.autoDispose.family<double, Product>(
  (ref, product) => goodStockOf(product, ref.watch(productExpiryProvider)),
);

final expiryAlertsProvider = Provider.autoDispose<List<ExpiryAlert>>((ref) {
  final byProduct = ref.watch(productExpiryProvider);
  // No deliveries, no alerts -- and no reason to start `todayProvider`'s
  // midnight timer for a shop that never records an expiry date.
  if (byProduct.isEmpty) return const <ExpiryAlert>[];
  return buildExpiryAlerts(
    products: ref.watch(productsStreamProvider).value ?? const <Product>[],
    byProduct: byProduct,
    today: ref.watch(todayProvider),
  );
});

/// A product's stock lost to removals, for the Deliveries "Thrown away" line.
final removalLossProvider = FutureProvider.autoDispose
    .family<RemovalLoss, String>((ref, productId) async {
      final r = await ref
          .watch(batchRepositoryProvider)
          .fetchRemovalLoss(productId);
      return r.valueOrNull ?? RemovalLoss.none;
    });

final latestRestockDateProvider = FutureProvider.autoDispose
    .family<DateTime?, String>((ref, productId) async {
      final r = await ref
          .watch(batchRepositoryProvider)
          .latestRestockDate(productId);
      return r.valueOrNull;
    });

/// Why each cart line cannot go through as it stands, keyed by product id.
final cartLineNoticesProvider =
    Provider.autoDispose<Map<String, CartLineNotice>>((ref) {
      final products =
          ref.watch(productsStreamProvider).value ?? const <Product>[];
      return cartLineNotices(
        lines: ref.watch(cartControllerProvider),
        liveProducts: {for (final p in products) p.id: p},
        byProduct: ref.watch(productExpiryProvider),
      );
    });

/// Runs a reconcile when the shop loads, when the date changes and when the
/// app returns to the foreground. Kept alive by `App`.
final expiryAutoReconcileProvider = Provider<void>((ref) {
  final reconciler = ref.watch(expiryReconcilerProvider);
  void run() => unawaited(reconciler.run());

  ref.listen(todayProvider, (_, _) => run());
  ref.listen(myShopProvider, (prev, next) {
    final id = next.value?.id;
    if (id != null && id != prev?.value?.id) run();
  }, fireImmediately: true);
  final lifecycle = AppLifecycleListener(onResume: run);
  ref.onDispose(lifecycle.dispose);
});
