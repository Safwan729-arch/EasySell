import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../expiry/domain/expiry_dates.dart';
import '../domain/transaction.dart';
import 'day_range.dart';

/// Records stock movements via the atomic Postgres RPCs. NEVER does client-side
/// stock math — `record_sale`/`record_restock` lock the row, check/adjust stock,
/// and insert the transaction with frozen prices in a single transaction.
class TransactionRepository {
  TransactionRepository(this._client);

  final SupabaseClient _client;

  /// Atomic restock via `record_restock` (0011). [restockId] is minted by the
  /// caller and re-sent on a retry: the server records a given id once and
  /// returns the existing row on a repeat, so a lost reply cannot add the
  /// stock twice. With [expiryDate] the delivery is recorded in the same
  /// transaction; [receivedOn] is the PHONE's local date (expiry spec §3.4).
  Future<Result<Transaction>> recordRestock({
    required String shopId,
    required String productId,
    required double quantity,
    required String restockId,
    String source = 'manual',
    DateTime? expiryDate,
    DateTime? receivedOn,
  }) async {
    try {
      final result = await _client.rpc(
        'record_restock',
        params: {
          'p_shop_id': shopId,
          'p_product_id': productId,
          'p_quantity': quantity,
          'p_source': source,
          'p_restock_id': restockId,
          if (expiryDate != null) 'p_expiry_date': ymd(expiryDate),
          if (receivedOn != null) 'p_received_on': ymd(receivedOn),
        },
      );
      // A function `returns transactions` yields a single composite object;
      // some setups return a single-element list. Handle both.
      final row = result is List ? result.first : result;
      return Result.success(
        Transaction.fromJson(Map<String, dynamic>.from(row as Map)),
      );
    } catch (e) {
      return Result.failure(_map(e));
    }
  }

  /// Atomic multi-item checkout: commits every cart line in one Postgres
  /// transaction via `record_sale_cart`, or none of them if any line fails
  /// (e.g. insufficient stock). Returns the inserted rows, all sharing one
  /// `sale_group_id` so History can group them into a single receipt.
  ///
  /// [saleGroupId] is minted by the caller, not the server. The server records
  /// a given id once and returns the existing rows on a repeat, so re-sending
  /// the same id after a lost reply cannot record the sale twice.
  Future<Result<List<Transaction>>> recordSaleCart({
    required String shopId,
    required List<Map<String, dynamic>> items,
    required String saleGroupId,
    String source = 'manual',
    String? customerId,
    double discount = 0,
  }) async {
    try {
      final result = await _client.rpc(
        'record_sale_cart',
        params: {
          'p_shop_id': shopId,
          'p_items': items,
          'p_source': source,
          'p_customer_id': ?customerId,
          'p_discount': discount,
          'p_sale_group_id': saleGroupId,
        },
      );
      final rows = result as List;
      return Result.success([
        for (final r in rows)
          Transaction.fromJson(Map<String, dynamic>.from(r as Map)),
      ]);
    } catch (e) {
      return Result.failure(_map(e));
    }
  }

  /// Reads recent SALE transactions for the shop, newest first. Read-only — RLS
  /// already scopes rows to the authenticated user's shop.
  ///
  /// Pass [since] to bound the window to sales at/after that instant (the Reports
  /// tab uses this to scope the category split and best sellers to the selected
  /// period; the boundary mirrors `get_dashboard_summary`'s `date_trunc`).
  Future<Result<List<Transaction>>> recentSales({
    required String shopId,
    int limit = 100,
    DateTime? since,
  }) async {
    try {
      var query = _client
          .from('transactions')
          .select()
          .eq('shop_id', shopId)
          .eq('type', 'sale');
      if (since != null) {
        query = query.gte('created_at', since.toUtc().toIso8601String());
      }
      final rows = await query
          .order('created_at', ascending: false)
          .limit(limit);
      final list = (rows as List)
          .map((r) => Transaction.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
      return Result.success(list);
    } catch (e) {
      return Result.failure(_map(e));
    }
  }

  /// All SALE transactions on [day] (the shopper's local calendar day), newest
  /// first. Unlike [recentSales] there is NO recent-N cap, so a drilled-into
  /// past day is always complete regardless of how many newer sales exist.
  Future<Result<List<Transaction>>> salesForDay({
    required String shopId,
    required DateTime day,
  }) async {
    try {
      final range = dayRangeUtc(day);
      final rows = await _client
          .from('transactions')
          .select()
          .eq('shop_id', shopId)
          .eq('type', 'sale')
          .gte('created_at', range.startUtc.toIso8601String())
          .lt('created_at', range.endUtc.toIso8601String())
          .order('created_at', ascending: false);
      final list = (rows as List)
          .map((r) => Transaction.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
      return Result.success(list);
    } catch (e) {
      return Result.failure(_map(e));
    }
  }

  /// The local calendar date of the shop's first-ever sale, or null when the
  /// shop has no sales yet. Backs the lower bound of every in-app date picker.
  Future<Result<DateTime?>> earliestSaleDate({required String shopId}) async {
    try {
      final rows = await _client
          .from('transactions')
          .select('created_at')
          .eq('shop_id', shopId)
          .eq('type', 'sale')
          .order('created_at', ascending: true)
          .limit(1);
      final list = rows as List;
      if (list.isEmpty) return const Result.success(null);
      final raw = (list.first as Map)['created_at'] as String;
      final local = DateTime.parse(raw).toLocal();
      return Result.success(DateTime(local.year, local.month, local.day));
    } catch (e) {
      return Result.failure(_map(e));
    }
  }

  /// RPC exceptions raised inside the function (e.g. "Insufficient stock for
  /// Pepsi: have 3, need 5", "Product not found") arrive as
  /// [PostgrestException]. The message is kept as an English fallback; the
  /// [Failure.code] is what the UI should render.
  Failure _map(Object e) {
    if (e is PostgrestException) {
      if (e.message.isEmpty) {
        return const DatabaseFailure(
          'Could not complete the transaction. Please try again.',
        );
      }
      final (:code, :detail) = classifyServerMessage(e.message);
      return DatabaseFailure(e.message, code: code, detail: detail);
    }
    if (e is SocketException) {
      return const NetworkFailure('No internet connection. Please try again.');
    }
    return const UnexpectedFailure('Something went wrong. Please try again.');
  }
}

final transactionRepositoryProvider = Provider<TransactionRepository>((ref) {
  return TransactionRepository(ref.watch(supabaseClientProvider));
});
