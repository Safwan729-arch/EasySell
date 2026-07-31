import 'dart:async';
import 'dart:io';

import 'package:ai_shopkeeper/core/error/failure.dart';
import 'package:ai_shopkeeper/features/scan/data/vision_scan_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Mirrors `voice_repository_error_mapping_test.dart`. The scan path had no
/// equivalent coverage, and no client-side timeout at all -- a hung
/// `recognize-product` left the scan sheet spinning forever with no way out.
void main() {
  group('mapScanFailure', () {
    test('a function error is a retryable failure with friendly copy', () {
      final failure = mapScanFailure(
        FunctionException(status: 502, details: 'boom'),
      );
      expect(failure, isA<DatabaseFailure>());
      expect(failure.message, contains('Could not recognize'));
    });

    test('a timeout is reported as a retryable failure, not a generic '
        '"something went wrong"', () {
      final failure = mapScanFailure(TimeoutException('too slow'));
      expect(failure, isA<DatabaseFailure>());
      expect(failure.message, contains('Could not recognize'));
    });

    test('no connectivity maps to a network failure', () {
      final failure = mapScanFailure(const SocketException('offline'));
      expect(failure, isA<NetworkFailure>());
      expect(failure.message, contains('No internet'));
    });

    test('anything unrecognised stays a generic unexpected failure', () {
      expect(mapScanFailure(StateError('odd')), isA<UnexpectedFailure>());
    });

    test('never leaks raw provider detail into user-facing copy', () {
      final failure = mapScanFailure(
        FunctionException(status: 500, details: 'GEMINI_API_KEY invalid'),
      );
      expect(failure.message, isNot(contains('GEMINI')));
    });
  });

  test('the scan call is bounded, so a hung function cannot spin forever', () {
    expect(scanRequestTimeout.inSeconds, greaterThan(0));
    // Must exceed the Edge Function's own Gemini abort (20s) plus room for
    // upload and cold start, or the client would give up before the server's
    // fast, honest error could ever arrive -- the exact composition bug the
    // voice path hit at 20s/30s.
    expect(scanRequestTimeout.inSeconds, greaterThanOrEqualTo(40));
  });
}
