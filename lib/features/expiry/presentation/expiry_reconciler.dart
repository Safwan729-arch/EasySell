import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../auth/data/auth_repository.dart';
import '../../inventory/data/product_repository.dart';
import '../../inventory/domain/product.dart';
import '../data/batch_repository.dart';
import '../domain/expiry_estimate.dart';
import '../domain/product_batch.dart';
import 'expiry_prefs.dart';
import 'expiry_providers.dart';
import 'today_provider.dart';

class ReconcileOutcome {
  const ReconcileOutcome.ok(this.byProduct) : failure = null;
  const ReconcileOutcome.failed(Failure this.failure) : byProduct = const {};

  final Failure? failure;

  /// The estimate after this run's writes were stored.
  final Map<String, ProductExpiry> byProduct;

  bool get ok => failure == null;
}

/// Stores the estimate's reconcile writes (spec §4.2): locks expired counts
/// and closes sold-out deliveries.
///
/// Computed from a FRESH read, never from the screen streams, and the read
/// order matters: deliveries first, then stock. The streams refresh
/// independently, so a restock's new delivery can arrive before its new stock;
/// estimating from that pair hands the old stock to the new delivery and
/// closes the old one as "sold out" while its units are still on the shelf.
/// Reading deliveries first means anything that changes between the two reads
/// shows up as NEWER stock, which can only give old deliveries more.
class ExpiryReconciler {
  ExpiryReconciler(this._ref);

  final Ref _ref;
  Future<void> _tail = Future.value();

  /// Serialised: each call waits for the one before, so a checkout always
  /// gets a result computed after any reconcile already running.
  Future<ReconcileOutcome> run() {
    final next = _tail.then((_) => _runOnce());
    _tail = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<ReconcileOutcome> _runOnce() async {
    try {
      final shopId = _ref.read(myShopProvider).value?.id;
      if (shopId == null) return const ReconcileOutcome.ok({});
      final batchRepo = _ref.read(batchRepositoryProvider);

      final List<ProductBatch> batches;
      switch (await batchRepo.fetchOpenBatches(shopId)) {
        case ResultFailure(:final failure):
          return ReconcileOutcome.failed(failure);
        case Success(:final value):
          batches = value;
      }
      if (batches.isEmpty) return const ReconcileOutcome.ok({});

      final List<Product> products;
      switch (await _ref
          .read(productRepositoryProvider)
          .fetchActiveProducts(shopId)) {
        case ResultFailure(:final failure):
          return ReconcileOutcome.failed(failure);
        case Success(:final value):
          products = value;
      }

      final today = _ref.read(todayProvider);
      final warnDays = _ref.read(expiryPrefsProvider).warnDays;
      final byProduct = estimateAll(
        products: products,
        openBatches: batches,
        today: today,
        shopWarnDays: warnDays,
      );
      final writes = [for (final e in byProduct.values) ...e.writes];
      if (writes.isEmpty) return ReconcileOutcome.ok(byProduct);

      if (await batchRepo.applyReconcile(writes) case ResultFailure(
        :final failure,
      )) {
        return ReconcileOutcome.failed(failure);
      }
      _ref.invalidate(batchesStreamProvider);
      return ReconcileOutcome.ok(
        estimateAll(
          products: products,
          openBatches: applyReconcileWrites(batches, writes),
          today: today,
          shopWarnDays: warnDays,
        ),
      );
    } catch (_) {
      // Never let a reconcile crash its caller; checkout treats this as a
      // failure and stops, everyone else simply tries again later.
      return const ReconcileOutcome.failed(
        UnexpectedFailure('Could not check expiry dates.'),
      );
    }
  }
}

final expiryReconcilerProvider = Provider<ExpiryReconciler>(
  ExpiryReconciler.new,
);
