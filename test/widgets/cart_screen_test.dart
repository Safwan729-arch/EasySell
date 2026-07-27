import 'package:ai_shopkeeper/core/config/theme.dart';
import 'package:ai_shopkeeper/features/auth/data/auth_repository.dart';
import 'package:ai_shopkeeper/features/auth/domain/shop.dart';
import 'package:ai_shopkeeper/features/cart/domain/cart_line.dart';
import 'package:ai_shopkeeper/features/cart/presentation/cart_controller.dart';
import 'package:ai_shopkeeper/features/cart/presentation/cart_screen.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:ai_shopkeeper/shared/providers/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// Seeds the cart with fixed contents so we can render CartScreen without a
/// live backend.
class _SeededCart extends CartController {
  _SeededCart(this._seed);
  final List<CartLine> _seed;
  @override
  List<CartLine> build() => _seed;
}

Product _p(String id, {required String name, double price = 35}) => Product(
  id: id,
  shopId: 's',
  name: name,
  brand: 'BrandCo',
  variant: '500ml',
  sellingPrice: price,
  quantity: 10,
);

Widget _harness(List<CartLine> lines) => ProviderScope(
  overrides: [
    cartControllerProvider.overrideWith(() => _SeededCart(lines)),
    myShopProvider.overrideWith(
      (ref) =>
          const Shop(id: 's', ownerId: 'o', name: 'Test Shop', currency: 'USD'),
    ),
  ],
  child: MaterialApp(
    theme: AppTheme.light,
    locale: const Locale('en'),
    supportedLocales: supportedAppLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: const CartScreen(),
  ),
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  // Match the physical S22 the app is tested on: 1080x2340 @ DPR 3 => 360x780.
  void usePhoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  testWidgets(
    'a non-empty cart renders each line with details and a body that has real '
    'height (regression: the bottom bar used to collapse the list to 0px)',
    (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(
        _harness([
          CartLine(product: _p('a', name: 'Pepsi 500ml'), quantity: 1),
          CartLine(product: _p('b', name: 'Lays Chips'), quantity: 2),
        ]),
      );
      await tester.pumpAndSettle();

      // The list viewport must not be starved to zero height by the bottom bar.
      expect(tester.getSize(find.byType(ListView)).height, greaterThan(300));

      // Both lines render, each as a card with an explicit Remove affordance.
      expect(find.text('Pepsi 500ml'), findsOneWidget);
      expect(find.text('Lays Chips'), findsOneWidget);
      expect(find.byType(Card), findsNWidgets(2));
      expect(find.text('Remove'), findsNWidgets(2));

      // Product detail (unit price) and the checkout bar are both present.
      expect(find.textContaining('/ pcs'), findsWidgets);
      expect(find.text('Checkout'), findsOneWidget);
      expect(find.textContaining('Total ·'), findsOneWidget);
    },
  );

  testWidgets('tapping Remove drops the line from the cart', (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(
      _harness([
        CartLine(product: _p('a', name: 'Pepsi 500ml'), quantity: 1),
        CartLine(product: _p('b', name: 'Lays Chips'), quantity: 1),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Card), findsNWidgets(2));
    await tester.tap(find.text('Remove').first);
    await tester.pumpAndSettle();

    // One line removed; the other remains.
    expect(find.byType(Card), findsOneWidget);
    expect(find.text('Lays Chips'), findsOneWidget);
    expect(find.text('Pepsi 500ml'), findsNothing);
  });

  testWidgets(
    'Clear-cart dialog: confirm button hugs its content, not full width',
    (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(
        _harness([CartLine(product: _p('a', name: 'Loose rice'), quantity: 1)]),
      );
      await tester.pumpAndSettle();

      // Open the confirm dialog from the app-bar "Clear" action.
      await tester.tap(find.widgetWithText(TextButton, 'Clear'));
      await tester.pumpAndSettle();
      expect(find.text('Clear cart?'), findsOneWidget);

      // The destructive confirm must not stretch across the whole dialog
      // (the theme's full-width FilledButton minimumSize is overridden).
      final confirm = find.widgetWithText(FilledButton, 'Clear');
      expect(confirm, findsOneWidget);
      expect(tester.getSize(confirm).width, lessThan(200));
    },
  );

  testWidgets('an empty cart shows the empty state and no checkout bar', (
    tester,
  ) async {
    usePhoneSize(tester);
    await tester.pumpWidget(_harness(const []));
    await tester.pumpAndSettle();

    expect(find.text('Your cart is empty'), findsOneWidget);
    expect(find.text('Checkout'), findsNothing);
    expect(find.byType(Card), findsNothing);
  });
}
