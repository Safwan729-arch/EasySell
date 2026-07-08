import 'package:ai_shopkeeper/features/scan/domain/recognition_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RecognitionResult.fromJson', () {
    test('parses a strong single match', () {
      final r = RecognitionResult.fromJson({
        'status': 'match',
        'read_brand': 'Pepsi',
        'read_name': 'Pepsi',
        'read_size': '500ml',
        'matches': [
          {'product_id': 'a1', 'confidence': 0.94},
        ],
      });
      expect(r.status, RecognitionStatus.match);
      expect(r.readBrand, 'Pepsi');
      expect(r.matches.single.productId, 'a1');
      expect(r.matches.single.confidence, closeTo(0.94, 1e-9));
    });

    test('parses none with empty matches', () {
      final r = RecognitionResult.fromJson({'status': 'none', 'matches': []});
      expect(r.status, RecognitionStatus.none);
      expect(r.matches, isEmpty);
      expect(r.readBrand, isNull);
    });

    test('unknown/missing status falls back to none', () {
      final r = RecognitionResult.fromJson({'matches': []});
      expect(r.status, RecognitionStatus.none);
    });

    test('integer confidence is coerced to double', () {
      final r = RecognitionResult.fromJson({
        'status': 'multiple',
        'matches': [
          {'product_id': 'a1', 'confidence': 1},
          {'product_id': 'a2', 'confidence': 0},
        ],
      });
      expect(r.matches.first.confidence, 1.0);
      expect(r.matches.last.confidence, 0.0);
    });
  });
}
