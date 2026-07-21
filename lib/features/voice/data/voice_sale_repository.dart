import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../domain/voice_parse_result.dart';

/// Maps transport errors to user-facing failures. Top-level so it is directly
/// unit-testable without constructing a Supabase client.
Failure mapVoiceFailure(Object e) {
  if (e is FunctionException) {
    return const DatabaseFailure(
      'Could not understand that right now. Please try again.',
    );
  }
  if (e is SocketException) {
    return const NetworkFailure('No internet connection. Please try again.');
  }
  return const UnexpectedFailure('Something went wrong. Please try again.');
}

/// Calls the `parse-sale` Edge Function, which holds the gateway key and turns
/// spoken audio into matched line items against the shop's own products.
class VoiceSaleRepository {
  VoiceSaleRepository(this._client);

  final SupabaseClient _client;

  Future<Result<VoiceParseResult>> parse({
    required Uint8List audioBytes,
    required String audioMime,
    required List<Map<String, dynamic>> candidates,
  }) async {
    try {
      final res = await _client.functions.invoke(
        'parse-sale',
        body: {
          'audio_base64': base64Encode(audioBytes),
          'audio_mime': audioMime,
          'candidates': candidates,
        },
      );
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
