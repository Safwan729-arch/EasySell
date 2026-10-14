import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../inventory/domain/product.dart';
import '../domain/expiry_dates.dart';
import '../domain/expiry_estimate.dart';
import '../domain/product_batch.dart';

/// Open deliveries and the products they belong to, read together.
typedef ExpirySnapshot = ({List<ProductBatch> batches, List<Product> products});

/// Reads and writes `product_batches` (migration 0011). RLS scopes every row
/// to the signed-in shop.
///
/// No table is in the `supabase_realtime` publication, so [watchOpenBatches]
/// delivers the initial rows only -- callers invalidate the stream provider
/// after their own writes, the same way the products stream works.
class BatchRepository {
  BatchRepository(this._client);

  final SupabaseClient _client;
  static const _table = 'product_batches';

  /// The shop's OPEN deliveries, filtered on the server. A one-shot read
  /// wrapped as a stream rather than `.stream()`: no table is in the realtime
  /// publication anyway, and `.stream()` allows a single filter, so it pulled
  /// every CLOSED delivery too. Daily bread and milk close ~1,000 a year --
  /// past PostgREST's default row cap, which then returns an arbitrary subset
  /// and open deliveries silently drop out of alerts and reminders.
  Stream<List<ProductBatch>> watchOpenBatches(String shopId) async* {
    final rows = await _client
        .from(_table)
        .select()
        .eq('shop_id', shopId)
        .isFilter('closed_at', null);
    yield _parse(rows);
  }

  /// The shop's open deliveries WITH their products' stock, in ONE request:
  /// one SQL statement, so both come from the same moment. Two reads let a
  /// sale land between them; a sale picked from one delivery (migration
  /// 0012) then shows as lower stock but not yet as a pick, the estimate
  /// pins the shortfall on the oldest delivery and the reconcile closes it as
  /// sold out -- or locks it too low -- while its units are on the shelf.
  /// Archived products and their deliveries are left out; only products that
  /// have deliveries come back, so a big shop stays under the 1000-row cap.
  Future<Result<ExpirySnapshot>> fetchExpirySnapshot(String shopId) async {
    try {
      final rows = await _client
          .from(_table)
          .select('*, products!inner(*)')
          .eq('shop_id', shopId)
          .isFilter('closed_at', null)
          .eq('products.is_archived', false);
      final batches = <ProductBatch>[];
      final products = <String, Product>{};
      for (final r in rows as List) {
        final row = Map<String, dynamic>.from(r as Map);
        final p = Map<String, dynamic>.from(row.remove('products') as Map);
        products[p['id'] as String] = Product.fromJson(p);
        batches.add(ProductBatch.fromJson(row));
      }
      return Result.success((
        batches: batches,
        products: products.values.toList(),
      ));
    } catch (e) {
      return Result.failure(_map(e));
    }
  }

  Future<Result<List<ProductBatch>>> fetchClosedBatches(
    String productId, {
    int limit = 10,
  }) async {
    try {
      final rows = await _client
          .from(_table)
          .select()
          .eq('product_id', productId)
          .not('closed_at', 'is', null)
          .order('closed_at', ascending: false)
          .limit(limit);
      return Result.success(_parse(rows));
    } catch (e) {
      return Result.failure(_map(e));
    }
  }

  Future<Result<ProductBatch>> addBatch({
    required String shopId,
    required String productId,
    required double quantity,
    required double buyingPrice,
    required DateTime receivedOn,
    required DateTime expiryDate,
  }) async {
    try {
      final row = await _client
          .from(_table)
          .insert({
            'shop_id': shopId,
            'product_id': productId,
            'quantity': quantity,
            'buying_price': buyingPrice,
            'received_on': ymd(receivedOn),
            'expiry_date': ymd(expiryDate),
          })
          .select()
          .single();
      return Result.success(ProductBatch.fromJson(row));
    } catch (e) {
      return Result.failure(_map(e));
    }
  }

  /// Edits an OPEN delivery. [clearLock] removes a locked expired count -- used
  /// when a mistyped date is corrected to today or later (spec §3.3).
  /// [lockedQty] lowers a lock that stays, when the amount is corrected below
  /// it.
  Future<Result<void>> updateBatch({
    required String batchId,
    required double quantity,
    required DateTime expiryDate,
    required bool clearLock,
    double? lockedQty,
  }) async {
    try {
      await _client
          .from(_table)
          .update({
            'quantity': quantity,
            'expiry_date': ymd(expiryDate),
            if (clearLock) 'expired_qty': null else 'expired_qty': ?lockedQty,
          })
          .eq('id', batchId)
          .isFilter('closed_at', null);
      return const Result.success(null);
    } catch (e) {
      return Result.failure(_map(e));
    }
  }

  Future<Result<void>> closeBatch(String batchId, String reason) async {
    try {
      await _close(batchId, reason);
      return const Result.success(null);
    } catch (e) {
      return Result.failure(_map(e));
    }
  }

  /// Stores reconcile writes. Each update only touches a still-open row (and a
  /// lock only a still-unlocked one), so when two phones race the first
  /// writer wins and the second write changes nothing.
  Future<Result<void>> applyReconcile(List<ReconcileWrite> writes) async {
    try {
      for (final w in writes) {
        switch (w) {
          case LockExpired(:final batchId, :final quantity):
            await _client
                .from(_table)
                .update({'expired_qty': quantity})
                .eq('id', batchId)
                .isFilter('closed_at', null)
                .isFilter('expired_qty', null);
          case CloseSoldOut(:final batchId):
            await _close(batchId, BatchCloseReason.soldOut);
        }
      }
      return const Result.success(null);
    } catch (e) {
      return Result.failure(_map(e));
    }
  }

  /// `remove_expired_stock` (0011): lowers stock by the locked expired count,
  /// records the loss as an `adjustment`, closes the delivery. Safe to retry.
  Future<Result<void>> removeExpiredStock({
    required String shopId,
    required String batchId,
  }) async {
    try {
      await _client.rpc(
        'remove_expired_stock',
        params: {'p_shop_id': shopId, 'p_batch_id': batchId},
      );
      return const Result.success(null);
    } catch (e) {
      return Result.failure(_map(e));
    }
  }

  /// Local date of the product's latest restock, or null if never restocked.
  /// The default "date added" for stock already on the shelf (spec §4.3).
  Future<Result<DateTime?>> latestRestockDate(String productId) async {
    try {
      final rows = await _client
          .from('transactions')
          .select('created_at')
          .eq('product_id', productId)
          .eq('type', 'restock')
          .order('created_at', ascending: false)
          .limit(1);
      final list = rows as List;
      if (list.isEmpty) return const Result.success(null);
      final raw = (list.first as Map)['created_at'] as String;
      return Result.success(dateOnly(DateTime.parse(raw).toLocal()));
    } catch (e) {
      return Result.failure(_map(e));
    }
  }

  Future<void> _close(String batchId, String reason) => _client
      .from(_table)
      .update({
        'closed_at': DateTime.now().toUtc().toIso8601String(),
        'closed_reason': reason,
      })
      .eq('id', batchId)
      .isFilter('closed_at', null);

  List<ProductBatch> _parse(Object? rows) => [
    for (final r in rows as List)
      ProductBatch.fromJson(Map<String, dynamic>.from(r as Map)),
  ];

  Failure _map(Object e) {
    if (e is PostgrestException) {
      return DatabaseFailure(
        e.message.isEmpty ? 'Could not save the delivery.' : e.message,
      );
    }
    if (e is SocketException) {
      return const NetworkFailure('No internet connection. Please try again.');
    }
    return const UnexpectedFailure('Something went wrong. Please try again.');
  }
}

final batchRepositoryProvider = Provider<BatchRepository>((ref) {
  return BatchRepository(ref.watch(supabaseClientProvider));
});
