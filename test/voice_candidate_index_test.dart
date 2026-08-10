import 'package:ai_shopkeeper/features/voice/domain/voice_parse_result.dart';
import 'package:flutter_test/flutter_test.dart';

/// Voice keeps real product ids everywhere downstream -- the review sheet's
/// choice chips look products up by id. So the index the model echoes is
/// translated at the parse boundary and never travels further.
void main() {
  test('indices become product ids at the boundary', () {
    final parsed = VoiceParseResult.fromJson(const {
      'heard_text': 'two pepsi',
      'items': [
        {
          'heard': 'pepsi',
          'quantity': 2,
          'matches': [
            {'product_id': '0', 'confidence': 0.9},
          ],
        },
      ],
    });
    final resolved = parsed.resolveIds((s) => s == '0' ? 'uuid-pepsi' : null);
    expect(resolved.items.single.matches.single.productId, 'uuid-pepsi');
  });

  test('an unresolvable index is dropped, never passed through raw', () {
    final parsed = VoiceParseResult.fromJson(const {
      'heard_text': 'x',
      'items': [
        {
          'heard': 'x',
          'quantity': 1,
          'matches': [
            {'product_id': '99', 'confidence': 0.9},
          ],
        },
      ],
    });
    final resolved = parsed.resolveIds((_) => null);
    expect(resolved.items.single.matches, isEmpty);
  });
}
