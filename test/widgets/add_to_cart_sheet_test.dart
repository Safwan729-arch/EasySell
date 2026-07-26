import 'package:ai_shopkeeper/core/config/theme.dart';
import 'package:ai_shopkeeper/features/auth/data/auth_repository.dart';
import 'package:ai_shopkeeper/features/auth/domain/shop.dart';
import 'package:ai_shopkeeper/features/cart/presentation/add_to_cart_sheet.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

Product _p({
  double quantity = 12,
  double price = 5,
  UnitType unitType = UnitType.piece,
  ProductUnit unit = ProductUnit.pcs,
}) => Product(
  id: 'a',
  shopId: 's',
  name: 'Pepsi 1L',
  brand: 'Pepsi',
  variant: '1L',
  unitType: unitType,
  unit: unit,
  quantity: quantity,
  sellingPrice: price,
);

Widget _harness(Product product) => ProviderScope(
  overrides: [
    myShopProvider.overrideWith(
      (ref) =>
          const Shop(id: 's', ownerId: 'o', name: 'Test Shop', currency: 'USD'),
    ),
  ],
  child: MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showAddToCartSheet(context, product: product),
          child: const Text('open'),
        ),
      ),
    ),
  ),
);

Future<void> _openSheet(WidgetTester tester, Product product) async {
  await tester.pumpWidget(_harness(product));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('typing above stock clamps the field and subtotal to remaining', (
    tester,
  ) async {
    await _openSheet(tester, _p(quantity: 12, price: 5));

    await tester.enterText(find.byType(TextField), '20');
    await tester.pumpAndSettle();

    // Field snaps to the 12-in-stock cap; subtotal reflects 12 * 5.
    expect(find.widgetWithText(TextField, '12'), findsOneWidget);
    expect(find.text('\$60.00'), findsOneWidget);
  });

  testWidgets('a typed decimal is floored for a piece product', (tester) async {
    await _openSheet(tester, _p(quantity: 12, price: 5));

    await tester.enterText(find.byType(TextField), '2.7');
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, '2'), findsOneWidget);
    expect(find.text('\$10.00'), findsOneWidget);
  });

  testWidgets('a weight product keeps a typed decimal', (tester) async {
    await _openSheet(
      tester,
      _p(
        quantity: 10,
        price: 40,
        unitType: UnitType.weight,
        unit: ProductUnit.kg,
      ),
    );

    await tester.enterText(find.byType(TextField), '2.5');
    await tester.pumpAndSettle();

    expect(find.text('\$100.00'), findsOneWidget);
  });

  testWidgets('clearing the quantity disables Add to cart', (tester) async {
    await _openSheet(tester, _p(quantity: 12, price: 5));

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();

    final addBtn = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Add to cart'),
    );
    expect(addBtn.onPressed, isNull);
  });

  testWidgets('the + stepper stays in sync with the field', (tester) async {
    await _openSheet(tester, _p(quantity: 12, price: 5));

    // Initial quantity is one step (1 pcs); tapping + makes it 2.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, '2'), findsOneWidget);
    expect(find.text('\$10.00'), findsOneWidget);
  });
}
