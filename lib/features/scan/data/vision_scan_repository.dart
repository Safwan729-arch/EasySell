import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../domain/recognition_result.dart';

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
      final res = await _client.functions.invoke(
        'recognize-product',
        body: {
          'image_base64': base64Encode(imageBytes),
          'candidates': candidates,
        },
      );
      final data = res.data;
      final map = data is String ? jsonDecode(data) : data;
      return Result.success(
        RecognitionResult.fromJson(Map<String, dynamic>.from(map as Map)),
      );
    } catch (e) {
      return Result.failure(_map(e));
    }
  }

  Failure _map(Object e) {
    if (e is FunctionException) {
      return const DatabaseFailure(
        'Could not recognize the product. Please try again.',
      );
    }
    if (e is SocketException) {
      return const NetworkFailure('No internet connection. Please try again.');
    }
    return const UnexpectedFailure('Something went wrong. Please try again.');
  }
}

final visionScanRepositoryProvider = Provider<VisionScanRepository>((ref) {
  return VisionScanRepository(ref.watch(supabaseClientProvider));
});
