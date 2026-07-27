import 'dart:async';
import 'dart:io';

import 'package:ai_shopkeeper/core/error/failure.dart';
import 'package:ai_shopkeeper/features/auth/data/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('mapSupabaseError', () {
    test('AuthRetryableFetchException maps to NetworkFailure', () {
      // gotrue wraps the offline SocketException as this AuthException subtype;
      // it must still be classified as a network problem, not an auth error.
      expect(
        mapSupabaseError(AuthRetryableFetchException()),
        isA<NetworkFailure>(),
      );
    });

    test('SocketException maps to NetworkFailure', () {
      expect(
        mapSupabaseError(const SocketException('no route to host')),
        isA<NetworkFailure>(),
      );
    });

    test('TimeoutException maps to NetworkFailure', () {
      expect(mapSupabaseError(TimeoutException('slow')), isA<NetworkFailure>());
    });

    test('a genuine AuthException maps to AuthFailure', () {
      final failure = mapSupabaseError(
        const AuthException('Invalid login credentials'),
      );
      expect(failure, isA<AuthFailure>());
      expect(failure.message, 'Invalid login credentials');
    });
  });
}
