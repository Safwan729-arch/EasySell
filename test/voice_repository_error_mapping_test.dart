import 'dart:io';

import 'package:ai_shopkeeper/core/error/failure.dart';
import 'package:ai_shopkeeper/features/voice/data/voice_sale_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('mapVoiceFailure', () {
    test('a function error becomes a friendly DatabaseFailure', () {
      final f = mapVoiceFailure(const FunctionException(status: 502));
      expect(f, isA<DatabaseFailure>());
      expect(f.message, isNot(contains('502')));
    });

    test('a socket error becomes a NetworkFailure', () {
      expect(
        mapVoiceFailure(const SocketException('no route')),
        isA<NetworkFailure>(),
      );
    });

    test('anything else becomes an UnexpectedFailure', () {
      expect(mapVoiceFailure(Exception('boom')), isA<UnexpectedFailure>());
    });
  });
}
