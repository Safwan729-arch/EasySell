import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_shopkeeper/shared/providers/connectivity_provider.dart';

void main() {
  group('isOnlineFromResults', () {
    test('wifi is online', () {
      expect(isOnlineFromResults([ConnectivityResult.wifi]), isTrue);
    });

    test('mobile is online', () {
      expect(isOnlineFromResults([ConnectivityResult.mobile]), isTrue);
    });

    test('none-only is offline', () {
      expect(isOnlineFromResults([ConnectivityResult.none]), isFalse);
    });

    test('empty list is offline', () {
      expect(isOnlineFromResults([]), isFalse);
    });

    test('mixed none + wifi is online', () {
      expect(
        isOnlineFromResults([ConnectivityResult.none, ConnectivityResult.wifi]),
        isTrue,
      );
    });
  });
}
