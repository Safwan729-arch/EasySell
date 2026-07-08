import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../domain/product.dart';

/// CRUD + realtime access for `products`. Repositories are the only layer that
/// touch the Supabase client; everything returns a [Result] (except the live
/// stream, whose errors flow through `AsyncValue`).
class ProductRepository {
  ProductRepository(this._client);

  final SupabaseClient _client;

  static const _table = 'products';

  /// Live, ordered list of a shop's *active* products. Supabase Realtime pushes
  /// inserts/updates/deletes (e.g. stock changes from voice/image sale flows) so
  /// the inventory screen stays current without manual refresh. Archived products
  /// (soft-deleted) are filtered out client-side — the stream API allows only a
  /// single server-side `.eq`, so the `is_archived` filter is applied here.
  Stream<List<Product>> watchProducts(String shopId) {
    return _client
        .from(_table)
        .stream(primaryKey: ['id'])
        .eq('shop_id', shopId)
        .order('name')
        .map(
          (rows) => rows
              .where((r) => r['is_archived'] != true)
              .map(Product.fromJson)
              .toList(),
        );
  }

  Future<Result<Product>> addProduct(Product product) async {
    try {
      final row = await _client
          .from(_table)
          .insert(product.toRow())
          .select()
          .single();
      return Result.success(Product.fromJson(row));
    } catch (e) {
      return Result.failure(_map(e));
    }
  }

  Future<Result<Product>> updateProduct(Product product) async {
    try {
      final row = await _client
          .from(_table)
          .update(product.toRow())
          .eq('id', product.id)
          .select()
          .single();
      return Result.success(Product.fromJson(row));
    } catch (e) {
      return Result.failure(_map(e));
    }
  }

  /// Soft-deletes a product by archiving it. A hard DELETE would fail once the
  /// product has any transaction history (FK `transactions_product_id_fkey`, no
  /// cascade — frozen sale-time prices must survive). Archiving hides it from the
  /// inventory list (see [watchProducts]) while preserving history. Reversible.
  Future<Result<void>> deleteProduct(String id) async {
    try {
      await _client
          .from(_table)
          .update({'is_archived': true})
          .eq('id', id);
      return const Result.success(null);
    } catch (e) {
      return Result.failure(_map(e));
    }
  }

  /// One-shot, ordered list of a shop's *archived* products — the inverse of
  /// [watchProducts]. Backs the "Archived products" screen in Settings.
  ///
  /// Deliberately a plain fetch, not a `.stream()`: the live inventory list runs
  /// a realtime stream on `products` for the same shop, and Supabase derives a
  /// channel topic from table+filter — a second identical subscription collides
  /// and returns nothing. The archived list doesn't need live updates; it
  /// refetches on open and after a restore.
  Future<List<Product>> fetchArchivedProducts(String shopId) async {
    final rows = await _client
        .from(_table)
        .select()
        .eq('shop_id', shopId)
        .eq('is_archived', true)
        .order('name');
    return rows.map(Product.fromJson).toList();
  }

  /// Un-archives a product, returning it to the active inventory.
  Future<Result<void>> restoreProduct(String id) async {
    try {
      await _client
          .from(_table)
          .update({'is_archived': false})
          .eq('id', id);
      return const Result.success(null);
    } catch (e) {
      return Result.failure(_map(e));
    }
  }

  Failure _map(Object e) {
    if (e is PostgrestException) {
      // Foreign-key violation (e.g. a hard delete blocked by transaction
      // history). Surface guidance, never the raw Postgres constraint text.
      if (e.code == '23503') {
        return const DatabaseFailure(
          "This product has sales history and can't be removed.",
        );
      }
      return DatabaseFailure(
        e.message.isNotEmpty
            ? e.message
            : 'Could not complete the request. Please try again.',
      );
    }
    if (e is SocketException) {
      return const NetworkFailure('No internet connection. Please try again.');
    }
    return const UnexpectedFailure('Something went wrong. Please try again.');
  }
}

final productRepositoryProvider = Provider<ProductRepository>((ref) {
  return ProductRepository(ref.watch(supabaseClientProvider));
});
