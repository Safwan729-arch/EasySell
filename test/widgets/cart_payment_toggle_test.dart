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
/// live backend. Mirrors `cart_screen_test.dart`'s harness.
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
    'Cash is selected by default and the checkout button is enabled',
    (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(
        _harness([
          CartLine(product: _p('a', name: 'Pepsi 500ml'), quantity: 1),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cash'), findsOneWidget);
      expect(find.text('Digital'), findsOneWidget);
      expect(find.text('Credit'), findsOneWidget);

      final checkoutButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Checkout'),
      );
      expect(checkoutButton.onPressed, isNotNull);

      // No customer affordance while Cash is selected.
      expect(find.text('Select customer'), findsNothing);
    },
  );

  testWidgets('Digital keeps checkout enabled and asks for no customer', (
    tester,
  ) async {
    usePhoneSize(tester);
    await tester.pumpWidget(
      _harness([CartLine(product: _p('a', name: 'Pepsi 500ml'), quantity: 1)]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Digital'));
    await tester.pumpAndSettle();

    expect(find.text('Select customer'), findsNothing);
    final checkoutButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Checkout'),
    );
    expect(checkoutButton.onPressed, isNotNull);
  });

  testWidgets(
    'tapping Credit disables checkout until a customer is chosen, and shows '
    'the select-customer affordance',
    (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(
        _harness([
          CartLine(product: _p('a', name: 'Pepsi 500ml'), quantity: 1),
        ]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Credit'));
      await tester.pumpAndSettle();

      expect(find.text('Select customer'), findsOneWidget);

      final checkoutButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Checkout'),
      );
      expect(checkoutButton.onPressed, isNull);
    },
  );
}
