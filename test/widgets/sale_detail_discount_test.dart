import 'package:ai_shopkeeper/features/transactions/domain/transaction.dart';
import 'package:ai_shopkeeper/features/transactions/presentation/sale_detail_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import '../support/cart_harness.dart';

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
  });

  testWidgets('an undiscounted line is unchanged', (tester) async {
    final c = await cartContainer();
    await tester.pumpWidget(cartApp(c, const SaleDetailScreen(sale: _plain)));
    await tester.pumpAndSettle();

    expect(find.text('Discount'), findsNothing);
    expect(find.text('Subtotal'), findsNothing);
  });
}
