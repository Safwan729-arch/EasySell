import 'package:ai_shopkeeper/features/cart/presentation/cart_controller.dart';
import 'package:ai_shopkeeper/features/cart/presentation/cart_discount_controller.dart';
import 'package:ai_shopkeeper/features/cart/presentation/discount_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import '../support/cart_harness.dart';

/// Opens the sheet over a cart holding one 850-sell / 700-buy line, so the
/// sale carries exactly 150 profit and a 162 discount lands 12 below cost.
/// [seedDiscount], if given, is staged on the controller before the sheet is
/// built, so the field's initial text can be inspected.
Future<ProviderContainer> _openSheet(
  WidgetTester tester, {
  double seedDiscount = 0,
}) async {
  final c = await cartContainer();
  c.read(cartControllerProvider.notifier).addOrIncrement(kOil, 1);
  if (seedDiscount > 0) {
    c.read(cartDiscountControllerProvider.notifier).setAmount(seedDiscount);
  }
  await tester.pumpWidget(
    cartApp(
      c,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDiscountSheet(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return c;
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('applying an amount stages it on the controller', (tester) async {
    final c = await _openSheet(tester);
    await tester.enterText(find.byType(TextField), '60');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(c.read(cartDiscountControllerProvider), 60);
  });

  testWidgets('an amount over the bill is clamped, not rejected', (
    tester,
  ) async {
    final c = await _openSheet(tester);
    await tester.enterText(find.byType(TextField), '9000');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(c.read(cartDiscountControllerProvider), 850);
  });

  testWidgets('warns when the sale would go below cost', (tester) async {
    await _openSheet(tester);
    await tester.enterText(find.byType(TextField), '162');
    await tester.pump();
    expect(find.textContaining('lose'), findsOneWidget);
  });

  testWidgets('the below-cost warning does not disable Apply', (tester) async {
    await _openSheet(tester);
    await tester.enterText(find.byType(TextField), '162');
    await tester.pump();
    final apply = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(
      apply.onPressed,
      isNotNull,
      reason: 'clearing stock at a loss is deliberate, not a mistake',
    );
  });

  testWidgets('no warning while the sale still profits', (tester) async {
    await _openSheet(tester);
    await tester.enterText(find.byType(TextField), '100');
    await tester.pump();
    expect(find.textContaining('lose'), findsNothing);
  });

  testWidgets(
    'reopening with an existing discount seeds a plain amount, not "60.0"',
    (tester) async {
      await _openSheet(tester, seedDiscount: 60);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, '60');
      expect(find.text('60.0'), findsNothing);
    },
  );

  testWidgets(
    'an unparseable amount disables Apply and shows the invalid message',
    (tester) async {
      await _openSheet(tester);
      await tester.enterText(find.byType(TextField), '1.2.3');
      await tester.pump();
      final apply = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(apply.onPressed, isNull);
      expect(find.text('Enter a valid amount'), findsOneWidget);
    },
  );

  testWidgets('correcting an unparseable amount re-enables Apply', (
    tester,
  ) async {
    await _openSheet(tester);
    await tester.enterText(find.byType(TextField), '1.2.3');
    await tester.pump();
    await tester.enterText(find.byType(TextField), '1.23');
    await tester.pump();
    final apply = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(apply.onPressed, isNotNull);
    expect(find.text('Enter a valid amount'), findsNothing);
  });

  testWidgets(
    'an empty field leaves Apply enabled so a discount can be cleared',
    (tester) async {
      await _openSheet(tester, seedDiscount: 60);
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      final apply = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(apply.onPressed, isNotNull);
    },
  );
}
