import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../expiry/domain/expiry_dates.dart';
import '../domain/restock_plan.dart';

/// Reads `get_restock_speeds` (0017). The speed needs the transaction
/// history, so it is computed in Postgres (restock spec §5).
class RestockRepository {
  RestockRepository(this._client);

  final SupabaseClient _client;

  Future<Result<List<RestockSpeed>>> fetchSpeeds(
    String shopId, {
    required DateTime today,
    required int utcOffsetMinutes,
  }) async {
    try {
      final rows = await _client.rpc(
        'get_restock_speeds',
        params: {
          'p_shop_id': shopId,
          'p_today': ymd(today),
          'p_utc_offset_minutes': utcOffsetMinutes,
        },
      );
      return Result.success([
        for (final r in rows as List)
          RestockSpeed.fromMap(Map<String, dynamic>.from(r as Map)),
      ]);
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

final restockRepositoryProvider = Provider<RestockRepository>(
  (ref) => RestockRepository(ref.watch(supabaseClientProvider)),
);
