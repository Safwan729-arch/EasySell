import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../domain/recognition_result.dart';

/// Backstop for a `recognize-product` call that never comes back.
///
/// Must sit comfortably above the Edge Function's own Gemini abort so the
/// server's fast, honest 502 always arrives before the client gives up --
/// otherwise the client timeout masks it and the user sees a generic hang
/// instead of a real error. Larger than the voice budget because a JPEG is a
/// much bigger upload than 15 seconds of 32kbps mono audio.
const scanRequestTimeout = Duration(seconds: 45);

/// Maps transport errors to user-facing failures. Top-level (not a private
/// method) so it is directly unit-testable without constructing a Supabase
/// client -- the same reasoning as `mapVoiceFailure`.
Failure mapScanFailure(Object e) {
  // TimeoutException covers both our own [scanRequestTimeout] and the Edge
  // Function aborting its Gemini call: both mean "no answer this time, try
  // again", which is exactly what a FunctionException means to the user.
  if (e is FunctionException || e is TimeoutException) {
    return const DatabaseFailure(
      'Could not recognize the product. Please try again.',
    );
  }
  if (e is SocketException) {
    return const NetworkFailure('No internet connection. Please try again.');
  }
  return const UnexpectedFailure('Something went wrong. Please try again.');
}

/// Calls the `recognize-product` Edge Function, which holds the API keys and
/// picks the vision provider server-side. Returns a normalized result.
class VisionScanRepository {
  VisionScanRepository(this._client);

  final SupabaseClient _client;

  Future<Result<RecognitionResult>> recognize({
    required Uint8List imageBytes,
    required List<Map<String, dynamic>> candidates,
  }) async {
    try {
      final res = await _client.functions
          .invoke(
            'recognize-product',
            body: {
              'image_base64': base64Encode(imageBytes),
              'candidates': candidates,
            },
          )
          .timeout(scanRequestTimeout);
      final data = res.data;
      final map = data is String ? jsonDecode(data) : data;
      return Result.success(
        RecognitionResult.fromJson(Map<String, dynamic>.from(map as Map)),
      );
    } catch (e) {
      return Result.failure(mapScanFailure(e));
    }
  }
}

final visionScanRepositoryProvider = Provider<VisionScanRepository>((ref) {
  return VisionScanRepository(ref.watch(supabaseClientProvider));
});
