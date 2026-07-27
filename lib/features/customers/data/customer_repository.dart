import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../domain/customer.dart';
import '../domain/customer_balance.dart';
import '../domain/ledger_entry.dart';
import '../domain/receivables_summary.dart';

/// The only layer that touches Supabase for the customer-credit feature.
/// Balances and the overpayment guard live in Postgres RPCs (never client-side
/// money math); this maps rows to models and returns [Result]s.
class CustomerRepository {
  CustomerRepository(this._client);

  final SupabaseClient _client;

  static const _customers = 'customers';
  static const _ledger = 'customer_ledger';

  Future<Result<List<CustomerBalance>>> customerBalances(String shopId) async {
    try {
      final rows = await _client.rpc(
        'get_customer_balances',
        params: {'p_shop_id': shopId},
      );
      return Result.success([
        for (final r in rows as List)
          CustomerBalance.fromMap(Map<String, dynamic>.from(r as Map)),
      ]);
    } catch (e) {
      return Result.failure(mapError(e));
    }
  }

  Future<Result<ReceivablesSummary>> receivablesSummary(String shopId) async {
    try {
      final result = await _client.rpc(
        'get_receivables_summary',
        params: {'p_shop_id': shopId},
      );
      final row = result is List
          ? (result.isEmpty ? const {} : result.first)
          : result;
      return Result.success(
        ReceivablesSummary.fromMap(Map<String, dynamic>.from(row as Map)),
      );
    } catch (e) {
      return Result.failure(mapError(e));
    }
  }

  Future<Result<Customer>> createCustomer({
    required String shopId,
    required String name,
    required String phone,
    String? note,
  }) async {
    try {
      final row = await _client
          .from(_customers)
          .insert({
            'shop_id': shopId,
            'name': name,
            'phone': phone,
            if (note != null && note.isNotEmpty) 'note': note,
          })
          .select()
          .single();
      return Result.success(Customer.fromJson(row));
    } catch (e) {
      return Result.failure(mapError(e));
    }
  }

  Future<Result<Customer>> updateCustomer({
    required String id,
    required String name,
    required String phone,
    String? note,
  }) async {
    try {
      final row = await _client
          .from(_customers)
          .update({
            'name': name,
            'phone': phone,
            'note': (note == null || note.isEmpty) ? null : note,
          })
          .eq('id', id)
          .select()
          .single();
      return Result.success(Customer.fromJson(row));
    } catch (e) {
      return Result.failure(mapError(e));
    }
  }

  Future<Result<void>> deleteCustomer({
    required String shopId,
    required String id,
  }) async {
    try {
      await _client.rpc(
        'delete_customer',
        params: {'p_shop_id': shopId, 'p_customer_id': id},
      );
      return const Result.success(null);
    } catch (e) {
      return Result.failure(mapError(e));
    }
  }

  Future<Result<List<LedgerEntry>>> ledgerFor(String customerId) async {
    try {
      final rows = await _client
          .from(_ledger)
          .select()
          .eq('customer_id', customerId)
          .order('created_at', ascending: false);
      return Result.success([
        for (final r in rows as List)
          LedgerEntry.fromJson(Map<String, dynamic>.from(r as Map)),
      ]);
    } catch (e) {
      return Result.failure(mapError(e));
    }
  }

  Future<Result<LedgerEntry>> recordPayment({
    required String shopId,
    required String customerId,
    required double amount,
    String? note,
  }) async {
    try {
      final result = await _client.rpc(
        'record_payment',
        params: {
          'p_shop_id': shopId,
          'p_customer_id': customerId,
          'p_amount': amount,
          if (note != null && note.isNotEmpty) 'p_note': note,
        },
      );
      final row = result is List ? result.first : result;
      return Result.success(
        LedgerEntry.fromJson(Map<String, dynamic>.from(row as Map)),
      );
    } catch (e) {
      return Result.failure(mapError(e));
    }
  }

  /// RPC/Postgres exceptions carry user-meaningful messages (e.g. "Payment
  /// exceeds balance: owes 150") — surface them directly. Mirrors
  /// `TransactionRepository._map`.
  @visibleForTesting
  Failure mapError(Object e) {
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

final customerRepositoryProvider = Provider<CustomerRepository>((ref) {
  return CustomerRepository(ref.watch(supabaseClientProvider));
});
