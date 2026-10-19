import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../../shared/providers/supabase_provider.dart';

/// Above the function's own 20 s Gemini abort, so its fast 502 arrives first.
const moneyTipsTimeout = Duration(seconds: 30);

/// Calls the `money-tips` Edge Function (Gemini key stays server-side).
class MoneyTipsRepository {
  MoneyTipsRepository(this._client);

  final SupabaseClient _client;

  Future<Result<List<String>>> fetch({
    required String lang,
    required Map<String, dynamic> facts,
  }) async {
    try {
      final res = await _client.functions
          .invoke('money-tips', body: {'lang': lang, 'facts': facts})
          .timeout(moneyTipsTimeout);
      final data = res.data;
      final map = Map<String, dynamic>.from(
        (data is String ? jsonDecode(data) : data) as Map,
      );
      final tips = [
        for (final t in (map['tips'] as List? ?? const []))
          if (t is String && t.trim().isNotEmpty) t.trim(),
      ];
      if (tips.isEmpty) {
        return const Result.failure(
          DatabaseFailure('No advice came back. Please try again.'),
        );
      }
      return Result.success(tips);
    } catch (e) {
      if (e is SocketException) {
        return const Result.failure(
          NetworkFailure('No internet connection. Please try again.'),
        );
      }
      return const Result.failure(
        DatabaseFailure('Could not get advice. Please try again.'),
      );
    }
  }
}

final moneyTipsRepositoryProvider = Provider<MoneyTipsRepository>(
  (ref) => MoneyTipsRepository(ref.watch(supabaseClientProvider)),
);
