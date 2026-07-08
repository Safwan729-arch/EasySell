import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ai_shopkeeper/core/config/theme.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Prevent google_fonts from making network requests during unit tests.
    // Falls back to system font; the theme structure is still correct.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('light theme uses gray-blue scaffold and royal-blue primary', (
    tester,
  ) async {
    // Pump a minimal widget so the binding is fully ready.
    await tester.pumpWidget(const SizedBox());
    final t = AppTheme.light;
    expect(t.brightness, Brightness.light);
    expect(t.scaffoldBackgroundColor, const Color(0xFFEEF2F7));
    expect(t.colorScheme.primary, const Color(0xFF2563EB));
  });

  testWidgets('AppColors exposes green positive and amber warning', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    final c = AppTheme.light.extension<AppColors>()!;
    expect(c.positive, const Color(0xFF16A34A));
    expect(c.warning, const Color(0xFFEA580C));
  });
}
