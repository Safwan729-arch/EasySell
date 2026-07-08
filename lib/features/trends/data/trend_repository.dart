import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../domain/trend.dart';

/// Read-only access to Member B's `trend_data` table. Missing table is treated
/// as "no trends" so the screen degrades gracefully during integration.
class TrendRepository {
  TrendRepository(this._client);

  final SupabaseClient _client;

  Future<Result<List<Trend>>> fetchTrends(String shopId) async {
    try {
      final rows = await _client
          .from('trend_data')
          .select()
          .eq('shop_id', shopId)
          .order('created_at', ascending: false);
      final list = (rows as List)
          .map((r) => Trend.fromMap(Map<String, dynamic>.from(r as Map)))
          .toList();
      return Result.success(list);
    } on PostgrestException catch (e) {
      if (_isMissingTable(e)) return const Result.success(<Trend>[]);
      return Result.failure(
        DatabaseFailure(
          e.message.isNotEmpty
              ? e.message
              : 'Could not load trends. Please try again.',
        ),
      );
    } on SocketException {
      return const Result.failure(
        NetworkFailure('No internet connection. Please try again.'),
      );
    } catch (_) {
      return const Result.failure(
        UnexpectedFailure('Something went wrong. Please try again.'),
      );
    }
  }

  static bool _isMissingTable(PostgrestException e) {
    return e.code == '42P01' ||
        e.code == 'PGRST205' ||
        e.message.toLowerCase().contains('does not exist') ||
        e.message.toLowerCase().contains('could not find the table');
  }
}

final trendRepositoryProvider = Provider<TrendRepository>((ref) {
  return TrendRepository(ref.watch(supabaseClientProvider));
});
