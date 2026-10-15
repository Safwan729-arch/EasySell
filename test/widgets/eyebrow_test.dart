import 'package:ai_shopkeeper/core/config/theme.dart';
import 'package:ai_shopkeeper/core/widgets/section_bits.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('hasBangla spots Bengali script only', () {
    expect(hasBangla('সেরা বিক্রেতা'), isTrue);
    expect(hasBangla('Top performer'), isFalse);
    expect(hasBangla('৳600'), isTrue); // the taka sign is in the block
  });

  Future<double?> spacingOf(WidgetTester tester, String text) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: Eyebrow(text)),
      ),
    );
    return tester.widget<Text>(find.byType(Text)).style?.letterSpacing;
  }

  // Tracking pulls Bangla conjuncts apart on a real phone.
  testWidgets('Eyebrow spaces Latin caps but not Bangla', (tester) async {
    expect(await spacingOf(tester, 'Top performer'), 1.8);
    expect(await spacingOf(tester, 'সেরা বিক্রেতা'), 0);
  });
}
