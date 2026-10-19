import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../expiry/domain/expiry_dates.dart';
import '../domain/cash_flow_alerts.dart';
import '../domain/finance_health.dart';

/// Reads `get_finance_health` (0019). The sums need the transaction and
/// khata history, so they are computed in Postgres; the judging is Dart.
class FinanceRepository {
  FinanceRepository(this._client);

  final SupabaseClient _client;

  Future<Result<FinanceHealth>> fetchHealth(
    String shopId, {
    required DateTime today,
    required int utcOffsetMinutes,
  }) async {
    try {
      final result = await _client.rpc(
        'get_finance_health',
        params: {
          'p_shop_id': shopId,
          'p_today': ymd(today),
          'p_utc_offset_minutes': utcOffsetMinutes,
          'p_overdue_days': overdueDays,
        },
      );
      final row = result is List
          ? (result.isEmpty ? const {} : result.first)
          : result;
      return Result.success(
        FinanceHealth.fromMap(Map<String, dynamic>.from(row as Map)),
      );
    } catch (e) {
      return Result.failure(_map(e));
    }
  }

  Failure _map(Object e) {
    if (e is PostgrestException) return DatabaseFailure(e.message);
    if (e is SocketException) {
      return const NetworkFailure('No internet connection. Please try again.');
    }
    return const UnexpectedFailure('Something went wrong. Please try again.');
  }
}

final financeRepositoryProvider = Provider<FinanceRepository>(
  (ref) => FinanceRepository(ref.watch(supabaseClientProvider)),
);
