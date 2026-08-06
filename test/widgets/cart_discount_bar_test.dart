import 'package:ai_shopkeeper/features/cart/presentation/cart_controller.dart';
import 'package:ai_shopkeeper/features/cart/presentation/cart_discount_controller.dart';
import 'package:ai_shopkeeper/features/cart/presentation/cart_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import '../support/cart_harness.dart';

Future<ProviderContainer> _cartScreen(WidgetTester tester) async {
  final c = await cartContainer();
  c.read(cartControllerProvider.notifier).addOrIncrement(kOil, 1); // 850
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

  testWidgets('the remove button clears the discount', (tester) async {
    final c = await _cartScreen(tester);
    c.read(cartDiscountControllerProvider.notifier).setAmount(60);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Remove discount'));
    await tester.pumpAndSettle();

    expect(c.read(cartDiscountControllerProvider), 0);
    expect(find.text('Discount'), findsNothing);
  });
}
