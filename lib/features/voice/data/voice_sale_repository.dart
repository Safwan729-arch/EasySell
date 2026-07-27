import 'dart:async';
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

/// Calls the `parse-sale` Edge Function with recorded audio. The gateway now
/// transcribes (Gemini) and parses (GPT) server-side, so the phone just ships
/// the raw recording (spec §0.1) plus the shop's own products as matching
/// candidates -- no on-device transcription happens anymore.
class VoiceSaleRepository {
  VoiceSaleRepository(this._client);

  final SupabaseClient _client;

  Future<Result<VoiceParseResult>> parse({
    required Uint8List audioBytes,
    required String audioMime,
    required List<Map<String, dynamic>> candidates,
  }) async {
    try {
      final res = await _client.functions
          .invoke(
            'parse-sale',
            body: {
              'audio_base64': base64Encode(audioBytes),
              'audio_mime': audioMime,
              'candidates': candidates,
            },
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

  /// Re-parses an edited transcript through the same `parse-sale` function,
  /// using its text path instead of audio. Lets the shopkeeper fix a mishear
  /// and get freshly matched line items without re-recording.
  Future<Result<VoiceParseResult>> parseTranscript({
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
