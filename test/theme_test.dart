import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ai_shopkeeper/core/config/theme.dart';
import 'package:ai_shopkeeper/core/widgets/app_backdrop.dart';
import 'package:ai_shopkeeper/core/widgets/segment_pills.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Prevent google_fonts from making network requests during unit tests.
    // Falls back to system font; the theme structure is still correct.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('light theme: Pastel glass canvas and primary blue', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    final t = AppTheme.light;
    expect(t.brightness, Brightness.light);
    // Scaffolds are transparent; each page's AppBackdrop paints the canvas.
    expect(t.scaffoldBackgroundColor, Colors.transparent);
    expect(t.extension<AppColors>()!.background, const Color(0xFFF3F4FE));
    expect(t.colorScheme.primary, const Color(0xFF2668F9));
    expect(t.colorScheme.onPrimary, Colors.white);
  });

  testWidgets('dark theme: Neon glass navy, bright blue, dark text on it', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    final t = AppTheme.dark;
    expect(t.extension<AppColors>()!.background, const Color(0xFF07112E));
    expect(t.colorScheme.primary, const Color(0xFF4D92FE));
    expect(t.colorScheme.onPrimary, const Color(0xFF06102A));
    expect(t.extension<AppColors>()!.positive, const Color(0xFF3FE6C4));
  });

  testWidgets('AppColors exposes green positive and orange warning', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    final c = AppTheme.light.extension<AppColors>()!;
    expect(c.positive, const Color(0xFF16A34A));
    expect(c.warning, const Color(0xFFF2600C));
  });

  Gradient? buttonGradient(WidgetTester tester) {
    final inks = tester.widgetList<Ink>(
      find.descendant(
        of: find.byType(FilledButton),
        matching: find.byType(Ink),
      ),
    );
    for (final ink in inks) {
      final d = ink.decoration;
      if (d is ShapeDecoration && d.gradient != null) return d.gradient;
    }
    return null;
  }

  // Built lazily inside each test: building a theme at load time, outside a
  // test zone, makes google_fonts reach for the network.
  for (final (name, themeOf) in [
    ('light', () => AppTheme.light),
    ('dark', () => AppTheme.dark),
  ]) {
    testWidgets('$name: an enabled FilledButton wears the brand gradient', (
      tester,
    ) async {
      final theme = themeOf();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: FilledButton(onPressed: () {}, child: const Text('Go')),
          ),
        ),
      );
      expect(
        buttonGradient(tester),
        theme.extension<AppColors>()!.brandGradient,
      );
    });

    testWidgets('$name: a disabled FilledButton has no gradient', (
      tester,
    ) async {
      final theme = themeOf();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: FilledButton(onPressed: null, child: Text('Go')),
          ),
        ),
      );
      expect(buttonGradient(tester), isNull);
    });

    testWidgets('$name: AppBackdrop paints the canvas behind its child', (
      tester,
    ) async {
      final theme = themeOf();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const AppBackdrop(child: Scaffold(body: Text('page'))),
        ),
      );
      expect(find.text('page'), findsOneWidget);
      final box = tester.widget<ColoredBox>(
        find
            .descendant(
              of: find.byType(AppBackdrop),
              matching: find.byType(ColoredBox),
            )
            .first,
      );
      expect(box.color, theme.extension<AppColors>()!.background);
    });

    // Regression: a pill animating between the gradient (selected) and the
    // idle fill once held a color and a gradient at once mid-tween, which
    // ShapeDecoration asserts against.
    testWidgets('$name: switching a SegmentPills selection animates cleanly', (
      tester,
    ) async {
      final theme = themeOf();
      var selected = 'A';
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SegmentPills<String>(
                values: const ['A', 'B', 'C'],
                selected: selected,
                labelOf: (v) => v,
                onChanged: (v) => setState(() => selected = v),
                expand: true,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('B'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(selected, 'B');
    });
  }
}
