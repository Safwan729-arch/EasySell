import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../domain/category.dart';

/// CRUD + realtime access for `categories`. Like [ProductRepository], this is the
/// only layer that touches the Supabase client; everything returns a [Result]
/// (except the live stream, whose errors flow through `AsyncValue`).
class CategoryRepository {
  CategoryRepository(this._client);

  final SupabaseClient _client;

  static const _table = 'categories';

  /// Live, name-ordered list of a shop's categories. Realtime keeps the picker
  /// and the manage-categories screen current after inline adds/renames/deletes.
  Stream<List<Category>> watchCategories(String shopId) {
    return _client
        .from(_table)
        .stream(primaryKey: ['id'])
        .eq('shop_id', shopId)
        .order('name')
        .map((rows) => rows.map(Category.fromJson).toList());
  }

  /// One-shot fetch (name-ordered). Useful where a stream isn't warranted.
  Future<Result<List<Category>>> fetchCategories(String shopId) async {
    try {
      final rows = await _client
          .from(_table)
          .select()
          .eq('shop_id', shopId)
          .order('name');
      return Result.success(rows.map(Category.fromJson).toList());
    } catch (e) {
      return Result.failure(_map(e));
    }
  }

  /// Normalized find-or-create via the `upsert_category` RPC. Returns the
  /// existing row if a case/space-insensitive match already exists (dedup is
  /// enforced by the DB unique constraint), otherwise the freshly created one.
  Future<Result<Category>> upsertCategory({
    required String shopId,
    required String name,
  }) async {
    try {
      final data = await _client.rpc(
        'upsert_category',
        params: {'p_shop_id': shopId, 'p_name': name},
      );
      // The function returns a single `categories` composite row. Depending on
      // PostgREST shaping that arrives as a Map or a single-element List.
      final row = data is List ? data.first : data;
      return Result.success(
        Category.fromJson(Map<String, dynamic>.from(row as Map)),
      );
    } catch (e) {
      return Result.failure(_map(e));
    }
  }

  /// Renames a category via the `rename_category` RPC (normalizes + updates
  /// name_normalized). Rejects collisions with a friendly message from the DB.
  Future<Result<Category>> renameCategory({
    required String id,
    required String name,
  }) async {
    try {
      final data = await _client.rpc(
        'rename_category',
        params: {'p_id': id, 'p_name': name},
      );
      final row = data is List ? data.first : data;
      return Result.success(
        Category.fromJson(Map<String, dynamic>.from(row as Map)),
      );
    } catch (e) {
      return Result.failure(_map(e));
    }
  }

  /// Deletes a category. Affected products' `category_id` is set to null by the
  /// ON DELETE SET NULL FK — products are never deleted, just uncategorized.
  Future<Result<void>> deleteCategory(String id) async {
    try {
      await _client.from(_table).delete().eq('id', id);
      return const Result.success(null);
    } catch (e) {
      return Result.failure(_map(e));
    }
  }

  Failure _map(Object e) {
    if (e is PostgrestException) {
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

final categoryRepositoryProvider = Provider<CategoryRepository>((ref) {
  return CategoryRepository(ref.watch(supabaseClientProvider));
});
