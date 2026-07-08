import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ai_shopkeeper/core/config/theme.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets(
    'a bare FilledButton next to an Expanded sibling in a Row does not '
    'starve the sibling of width',
    (tester) async {
      // Regression test: AppTheme's FilledButton default is
      // `minimumSize: Size.fromHeight(52)`, i.e. an unbounded (infinite)
      // minimum width. Any FilledButton placed directly in a Row (not
      // wrapped in Expanded/a fixed-width box) forces
      // "BoxConstraints forces an infinite width" during layout, which
      // starves sibling Expanded children to ~0 width and makes their text
      // wrap one character per line. This exact shape shipped in
      // CartScreen's checkout bar (Total column + Checkout button) and was
      // only caught on a physical device, not by static analysis or the
      // per-task code review. The button style must explicitly reset
      // `minimumSize` to width 0 (see dashboard_screen.dart's Restock chip
      // for the established pattern) whenever it isn't Expanded itself.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: const SizedBox(),
            bottomNavigationBar: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        key: const Key('totalColumn'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text('Total'),
                          Text(
                            r'$70.00',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    FilledButton(
                      key: const Key('checkoutButton'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 52),
                      ),
                      onPressed: () {},
                      child: const Text('Checkout'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final totalColumnWidth = tester
          .getSize(find.byKey(const Key('totalColumn')))
          .width;

      expect(
        totalColumnWidth,
        greaterThan(60),
        reason:
            'Expanded Total column must get a real share of the row width, '
            'not be starved by an unbounded-width sibling button.',
      );
    },
  );
}
