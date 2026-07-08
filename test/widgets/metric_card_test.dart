import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ai_shopkeeper/core/config/theme.dart';
import 'package:ai_shopkeeper/core/widgets/metric_card.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('filled MetricCard renders with royal-blue background', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: MetricCard(label: 'Revenue', value: r'$5,230', filled: true),
        ),
      ),
    );
    final card = tester.widget<Card>(find.byType(Card));
    expect(card.color, const Color(0xFF2563EB));
    expect(find.text(r'$5,230'), findsOneWidget);
  });
}
