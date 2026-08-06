import 'package:ai_shopkeeper/features/cart/presentation/cart_controller.dart';
import 'package:ai_shopkeeper/features/cart/presentation/cart_discount_controller.dart';
import 'package:ai_shopkeeper/features/cart/presentation/cart_screen.dart';
import 'package:ai_shopkeeper/shared/extensions/format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import '../support/cart_harness.dart';

/// The harness shop is BDT, so the rendered strings come from [Money.format]
/// rather than a hardcoded symbol -- asserting "৳895.00" would encode intl's
/// choice of symbol into a test about arithmetic.
String _m(num v) => Money.format(v, currencyCode: 'BDT');

/// 850 + 45 = 895. TWO lines on purpose: with a single 850 line the bar's
/// subtotal is indistinguishable from the line card's own subtotal, so an
/// assertion on "850" could not tell the bar from the list and would pass on a
/// bar that rendered nothing at all.
Future<ProviderContainer> _cartScreen(WidgetTester tester) async {
  final c = await cartContainer();
  c.read(cartControllerProvider.notifier).addOrIncrement(kOil, 1); // 850
  c.read(cartControllerProvider.notifier).addOrIncrement(kPepsi, 1); // 45
  await tester.pumpWidget(cartApp(c, const CartScreen()));
  await tester.pumpAndSettle();
  return c;
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('with no discount the bar shows only the total', (tester) async {
    await _cartScreen(tester);
    expect(find.text('Add discount'), findsOneWidget);
    expect(find.text('Discount'), findsNothing);
    expect(
      find.text('Subtotal'),
      findsNothing,
      reason: 'the no-discount sale is the common case and must not gain rows',
    );
    expect(find.text(_m(895)), findsOneWidget);
  });

  testWidgets('a staged discount adds the subtotal and discount rows', (
    tester,
  ) async {
    final c = await _cartScreen(tester);
    c.read(cartDiscountControllerProvider.notifier).setAmount(60);
    await tester.pumpAndSettle();
    expect(find.text('Subtotal'), findsOneWidget);
    expect(find.text('Discount'), findsOneWidget);
    expect(find.text('Add discount'), findsNothing);
  });

  // The labels above would all pass on a bar that showed the GROSS bill as the
  // total, or rendered the discount as a positive number -- which is the exact
  // shape of the snackbar bug this branch shipped. Assert the arithmetic.
  testWidgets('the bar renders gross, discount and net as three figures', (
    tester,
  ) async {
    final c = await _cartScreen(tester);
    c.read(cartDiscountControllerProvider.notifier).setAmount(60);
    await tester.pumpAndSettle();

    expect(find.text(_m(895)), findsOneWidget, reason: 'the Subtotal row');
    expect(find.text('−${_m(60)}'), findsOneWidget, reason: 'signed, negative');
    expect(find.text(_m(835)), findsOneWidget, reason: 'the total is NET');
    expect(
      find.text(_m(60)),
      findsNothing,
      reason: 'an unsigned 60 would read as money owed, not money off',
    );
  });

  testWidgets('the remove button clears the discount', (tester) async {
    final c = await _cartScreen(tester);
    c.read(cartDiscountControllerProvider.notifier).setAmount(60);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Remove discount'));
    await tester.pumpAndSettle();

    expect(c.read(cartDiscountControllerProvider), 0);
    expect(find.text('Discount'), findsNothing);
    expect(
      find.text(_m(895)),
      findsOneWidget,
      reason: 'back to the gross bill',
    );
  });

  // Without this the sheet is reachable only from "Add discount", which exists
  // only while the discount is zero -- so an applied discount could never be
  // edited and a haggled 60-to-80 meant clearing and retyping.
  testWidgets('tapping the applied amount reopens the sheet, seeded', (
    tester,
  ) async {
    final c = await _cartScreen(tester);
    c.read(cartDiscountControllerProvider.notifier).setAmount(60);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Edit discount'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(
      field.controller!.text,
      '60',
      reason: 'the sheet must open on the current discount, not blank',
    );

    await tester.enterText(find.byType(TextField), '80');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(c.read(cartDiscountControllerProvider), 80);
    expect(find.text('−${_m(80)}'), findsOneWidget);
    expect(find.text(_m(815)), findsOneWidget, reason: '895 - 80');
  });

  testWidgets('edit and remove are separate targets', (tester) async {
    final c = await _cartScreen(tester);
    c.read(cartDiscountControllerProvider.notifier).setAmount(60);
    await tester.pumpAndSettle();

    // Merging them would make a mis-tap on the amount destroy the discount.
    expect(find.byTooltip('Edit discount'), findsOneWidget);
    expect(find.byTooltip('Remove discount'), findsOneWidget);
    expect(
      tester.getCenter(find.byTooltip('Edit discount')),
      isNot(tester.getCenter(find.byTooltip('Remove discount'))),
    );
    expect(c.read(cartDiscountControllerProvider), 60);
  });
}
