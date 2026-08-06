import 'package:ai_shopkeeper/features/transactions/domain/transaction.dart';
import 'package:ai_shopkeeper/features/transactions/presentation/sale_detail_screen.dart';
import 'package:ai_shopkeeper/shared/extensions/format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import '../support/cart_harness.dart';

/// The harness shop is BDT; going through [Money.format] keeps this a test of
/// the arithmetic rather than of intl's currency symbol.
String _m(num v) => Money.format(v, currencyCode: 'BDT');

/// 45.00 x 2 = 90.00 gross, 10.00 off, so 80.00 net.
const _discounted = Transaction(
  id: 't1',
  shopId: 's1',
  productId: 'p1',
  type: 'sale',
  quantity: 2,
  buyingPrice: 30,
  sellingPrice: 45,
  discountAmount: 10,
);

const _plain = Transaction(
  id: 't2',
  shopId: 's1',
  productId: 'p1',
  type: 'sale',
  quantity: 2,
  buyingPrice: 30,
  sellingPrice: 45,
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('a discounted line shows subtotal, discount and total', (
    tester,
  ) async {
    final c = await cartContainer();
    await tester.pumpWidget(
      cartApp(c, const SaleDetailScreen(sale: _discounted)),
    );
    await tester.pumpAndSettle();

    // Without these rows the screen reads as broken arithmetic: "45 each",
    // "quantity 2", "total 80".
    expect(find.text('Subtotal'), findsOneWidget);
    expect(find.text('Discount'), findsOneWidget);

    // The labels alone would pass on a screen that put the gross in the Total
    // row or printed the discount unsigned, so assert the figures too. 90.00
    // must appear exactly once -- as the Subtotal, never as the Total.
    expect(find.text(_m(90)), findsOneWidget, reason: 'the Subtotal row');
    expect(find.text('−${_m(10)}'), findsOneWidget, reason: 'signed negative');
    expect(find.text(_m(80)), findsOneWidget, reason: 'Total is net of it');
    expect(
      find.text(_m(10)),
      findsNothing,
      reason: 'an unsigned 10 would read as an amount charged, not taken off',
    );
  });

  testWidgets('an undiscounted line is unchanged', (tester) async {
    final c = await cartContainer();
    await tester.pumpWidget(cartApp(c, const SaleDetailScreen(sale: _plain)));
    await tester.pumpAndSettle();

    expect(find.text('Discount'), findsNothing);
    expect(find.text('Subtotal'), findsNothing);
    expect(
      find.text(_m(90)),
      findsOneWidget,
      reason: 'with nothing off, the Total is the full 45.00 x 2',
    );
  });
}
