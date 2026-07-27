import 'dart:io';

import 'package:ai_shopkeeper/core/error/failure.dart';
import 'package:ai_shopkeeper/features/customers/data/customer_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final repo = CustomerRepository(SupabaseClient('http://localhost', 'anon'));

  group('CustomerRepository.mapError', () {
    test('an RPC exception surfaces its message as DatabaseFailure', () {
      final f = repo.mapError(
        const PostgrestException(message: 'Payment exceeds balance: owes 150'),
      );
      expect(f, isA<DatabaseFailure>());
      expect(f.message, 'Payment exceeds balance: owes 150');
    });

    test('a SocketException maps to NetworkFailure', () {
      expect(
        repo.mapError(const SocketException('no route')),
        isA<NetworkFailure>(),
      );
    });

    test('anything else maps to UnexpectedFailure', () {
      expect(repo.mapError(Exception('boom')), isA<UnexpectedFailure>());
    });
  });
}
