import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../domain/insight.dart';

/// Read-only access to Member B's `insights` table. If Member B hasn't created
/// the table yet, we treat that as "no insights" rather than an error so the
/// screen degrades gracefully during integration.
class InsightsRepository {
  InsightsRepository(this._client);

  final SupabaseClient _client;

  Future<Result<List<Insight>>> fetchInsights(String shopId) async {
    try {
      final rows = await _client
          .from('insights')
          .select()
          .eq('shop_id', shopId)
          .order('created_at', ascending: false);
      final list = (rows as List)
          .map((r) => Insight.fromMap(Map<String, dynamic>.from(r as Map)))
          .toList();
      return Result.success(list);
    } on PostgrestException catch (e) {
      if (_isMissingTable(e)) return const Result.success(<Insight>[]);
      return Result.failure(
        DatabaseFailure(
          e.message.isNotEmpty
              ? e.message
              : 'Could not load insights. Please try again.',
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

  /// Member B's table may not exist yet during integration.
  static bool _isMissingTable(PostgrestException e) {
    return e.code == '42P01' || // undefined_table
        e.code == 'PGRST205' || // table not found in schema cache
        e.message.toLowerCase().contains('does not exist') ||
        e.message.toLowerCase().contains('could not find the table');
  }
}

final insightsRepositoryProvider = Provider<InsightsRepository>((ref) {
  return InsightsRepository(ref.watch(supabaseClientProvider));
});
