import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../domain/analytics.dart';

/// Reads aggregated analytics from Postgres RPCs. The heavy lifting stays in the
/// database; this just maps rows into typed models.
class AnalyticsRepository {
  AnalyticsRepository(this._client);

  final SupabaseClient _client;

  Future<Result<DashboardSummary>> getSummary(
    String shopId,
    AnalyticsPeriod period, {
    DateTime? day,
  }) async {
    try {
      final result = await _client.rpc(
        'get_dashboard_summary',
        params: {
          'p_shop_id': shopId,
          'p_period': period.value,
          if (day != null) 'p_day': dayParam(day),
        },
      );
      // `returns table(...)` → a list of rows; take the single row.
      final row = result is List
          ? (result.isEmpty ? const {} : result.first)
          : result;
      return Result.success(
        DashboardSummary.fromMap(Map<String, dynamic>.from(row as Map)),
      );
    } catch (e) {
      return Result.failure(_map(e));
    }
  }

  Future<Result<List<SalesPoint>>> getSeries(
    String shopId,
    ChartBucket bucket,
  ) async {
    try {
      final result = await _client.rpc(
        'get_sales_series',
        params: {
          'p_shop_id': shopId,
          'p_bucket': bucket.value,
          'p_points': bucket.points,
        },
      );
      final rows = (result as List)
          .map((r) => SalesPoint.fromMap(Map<String, dynamic>.from(r as Map)))
          .toList();
      return Result.success(rows);
    } catch (e) {
      return Result.failure(_map(e));
    }
  }

  Failure _map(Object e) {
    if (e is PostgrestException) {
      return DatabaseFailure(
        e.message.isNotEmpty
            ? e.message
            : 'Could not load analytics. Please try again.',
      );
    }
    if (e is SocketException) {
      return const NetworkFailure('No internet connection. Please try again.');
    }
    return const UnexpectedFailure('Something went wrong. Please try again.');
  }
}

final analyticsRepositoryProvider = Provider<AnalyticsRepository>((ref) {
  return AnalyticsRepository(ref.watch(supabaseClientProvider));
});
