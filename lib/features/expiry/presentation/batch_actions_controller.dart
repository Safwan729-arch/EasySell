import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../../shared/providers/refresh_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../../inventory/domain/product.dart';
import '../../inventory/presentation/inventory_controller.dart';
import '../data/batch_repository.dart';
import '../domain/expiry_dates.dart';
import '../domain/product_batch.dart';
import 'expiry_prefs.dart';
import 'expiry_providers.dart';
import 'expiry_reconciler.dart';
import 'today_provider.dart';

/// The shopkeeper's actions on deliveries (spec §3.3, §3.2). Models the
/// in-flight action only; screens watch `isLoading` and listen for errors.
class BatchActionsController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  BatchRepository get _repo => ref.read(batchRepositoryProvider);

  Future<bool> addBatch({
    required Product product,
    required double quantity,
    required DateTime expiryDate,
    required DateTime receivedOn,
  }) async {
    final ok = await _run(() async {
      final r = await _repo.addBatch(
        shopId: product.shopId,
        productId: product.id,
        quantity: quantity,
        buyingPrice: product.buyingPrice,
        receivedOn: receivedOn,
        expiryDate: expiryDate,
      );
      return r.when(
        success: (_) => const Result<void>.success(null),
        failure: (f) => Result<void>.failure(f),
      );
    });
    if (ok) {
      unawaited(ref.read(expiryPrefsProvider.notifier).askPermissionOnce());
    }
    return ok;
  }

  /// Moving a locked delivery's date to today or later clears the lock -- the
  /// lock came from a mistyped date (spec §3.3). A lock that stays is capped
  /// at the corrected amount: an amount typed as 50 instead of 5 was locked at
  /// 50, and "Remove from stock" would otherwise remove 50.
  Future<bool> editBatch(
    ProductBatch batch, {
    required double quantity,
    required DateTime expiryDate,
  }) {
    final today = ref.read(todayProvider);
    final locked = batch.expiredQty;
    final clearLock = locked != null && !today.isAfter(dateOnly(expiryDate));
    final lowerLock = locked != null && !clearLock && quantity < locked;
    return _run(
      () => _repo.updateBatch(
        batchId: batch.id,
        quantity: quantity,
        expiryDate: expiryDate,
        clearLock: clearLock,
        lockedQty: lowerLock ? quantity : null,
      ),
    );
  }

  /// The escape hatch when the estimate is wrong: the expired deliveries are
  /// closed, so their units count as good stock again.
  Future<bool> markNotExpired(List<String> batchIds) => _run(() async {
    for (final id in batchIds) {
      final r = await _repo.closeBatch(id, BatchCloseReason.notExpired);
      if (r.isFailure) return r;
    }
    return const Result.success(null);
  });

  Future<bool> removeExpired(List<String> batchIds) {
    final shopId = ref.read(myShopProvider).value?.id;
    if (shopId == null) {
      state = AsyncError(
        const AuthFailure('No shop found for this account.'),
        StackTrace.current,
      );
      return Future.value(false);
    }
    return _run(stockChanged: true, () async {
      // A delivery shown as expired by its date may not be locked yet (just
      // added with a past date, just after midnight, or a reconcile that
      // failed); the server refuses to remove an unlocked one. Store the
      // pending locks first. A failed reconcile is not fatal here -- the
      // removal then reports the server's answer.
      await ref.read(expiryReconcilerProvider).run();
      for (final id in batchIds) {
        final r = await _repo.removeStock(shopId: shopId, batchId: id);
        if (r.isFailure) return r;
      }
      return const Result.success(null);
    });
  }

  /// The removal id of the last removal that got no answer, and the request
  /// it was for -- the restock pattern (0011). A partial removal leaves the
  /// delivery open, so "already closed" cannot catch a retry; the server
  /// records an id once instead. Anything changed is a new removal.
  String? _pendingRemovalId;
  String? _pendingRemovalRequest;

  /// Throws away (or returns) [quantity] of one delivery that has not
  /// expired: stock goes down, the loss is recorded. Removing all of what is
  /// [left] closes the delivery; removing part keeps it open with the rest.
  ///
  /// There is no "None left": a delivery whose units were sold closes by
  /// itself, and closing one WITHOUT lowering stock left thrown-away units
  /// counted as good, sellable stock with no date.
  Future<bool> removeBatch(
    String batchId, {
    required double quantity,
    required double left,
  }) async {
    final shopId = ref.read(myShopProvider).value?.id;
    if (shopId == null) {
      state = AsyncError(
        const AuthFailure('No shop found for this account.'),
        StackTrace.current,
      );
      return false;
    }
    final close = quantity >= left - 1e-9;
    final request = jsonEncode({
      'batch': batchId,
      'quantity': quantity,
      'close': close,
      // A retry is the same day; the same removal days later is a new one.
      'day': ymd(ref.read(todayProvider)),
    });
    if (request != _pendingRemovalRequest) {
      _pendingRemovalId = const Uuid().v4();
      _pendingRemovalRequest = request;
    }
    final ok = await _run(
      stockChanged: true,
      () => _repo.removeStock(
        shopId: shopId,
        batchId: batchId,
        quantity: quantity,
        close: close,
        removalId: _pendingRemovalId,
      ),
    );
    // Recorded, or refused by the server (so certainly not recorded): the
    // next removal is a new one.
    if (ok || state.error is DatabaseFailure) {
      _pendingRemovalId = null;
      _pendingRemovalRequest = null;
    }
    return ok;
  }

  Future<bool> _run(
    Future<Result<void>> Function() action, {
    bool stockChanged = false,
  }) async {
    state = const AsyncLoading();
    final result = await action();
    switch (result) {
      case ResultFailure(:final failure):
        state = AsyncError(failure, StackTrace.current);
        return false;
      case Success():
        ref.invalidate(batchesStreamProvider);
        ref.invalidate(closedBatchesProvider);
        if (stockChanged) {
          ref.invalidate(productsStreamProvider);
          ref.read(dataRefreshProvider.notifier).bump();
        }
        unawaited(ref.read(expiryReconcilerProvider).run());
        state = const AsyncData(null);
        return true;
    }
  }
}

final batchActionsControllerProvider =
    AsyncNotifierProvider<BatchActionsController, void>(
      BatchActionsController.new,
    );
