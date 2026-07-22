import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../domain/voice_parse_result.dart';

/// Maps transport errors to user-facing failures. Top-level so it is directly
/// unit-testable without constructing a Supabase client.
Failure mapVoiceFailure(Object e) {
  if (e is FunctionException || e is TimeoutException) {
    return const DatabaseFailure(
      'Could not understand that right now. Please try again.',
    );
  }
  if (e is SocketException) {
    return const NetworkFailure('No internet connection. Please try again.');
  }
  return const UnexpectedFailure('Something went wrong. Please try again.');
}

/// Calls the `parse-sale` Edge Function. The phone transcribes speech to text
/// on-device; this sends the TEXT transcript (the gateway cannot accept audio).
/// Matches transcript against the shop's own products (spec §0).
class VoiceSaleRepository {
  VoiceSaleRepository(this._client);

  final SupabaseClient _client;

  Future<Result<VoiceParseResult>> parse({
    required String transcript,
    required List<Map<String, dynamic>> candidates,
  }) async {
    try {
      final res = await _client.functions
          .invoke(
            'parse-sale',
            body: {'transcript': transcript, 'candidates': candidates},
          )
          .timeout(const Duration(seconds: 30));
      final data = res.data;
      final map = data is String ? jsonDecode(data) : data;
      return Result.success(
        VoiceParseResult.fromJson(Map<String, dynamic>.from(map as Map)),
      );
    } catch (e) {
      return Result.failure(mapVoiceFailure(e));
    }
  }
}

final voiceSaleRepositoryProvider = Provider<VoiceSaleRepository>((ref) {
  return VoiceSaleRepository(ref.watch(supabaseClientProvider));
});
