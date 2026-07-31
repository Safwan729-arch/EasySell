import 'package:ai_shopkeeper/core/config/theme.dart';
import 'package:ai_shopkeeper/features/auth/data/auth_repository.dart';
import 'package:ai_shopkeeper/features/auth/domain/shop.dart';
import 'package:ai_shopkeeper/features/inventory/domain/category.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/inventory/presentation/category_controller.dart';
import 'package:ai_shopkeeper/features/inventory/presentation/inventory_controller.dart';
import 'package:ai_shopkeeper/features/inventory/presentation/inventory_list_screen.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:ai_shopkeeper/shared/providers/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

Widget _harness(ProviderContainer container, {required Widget child}) =>
    UncontrolledProviderScope(
      container: container,
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
        home: child,
      ),
    );

/// 30 cost / 45 retail, plus 200 cost / 240 retail = 230 and 285.
const _products = [
  Product(
    id: 'a',
    shopId: 's',
    name: 'Rice',
    buyingPrice: 10,
    sellingPrice: 15,
    quantity: 3,
  ),
  Product(
    id: 'b',
    shopId: 's',
    name: 'Oil',
    buyingPrice: 100,
    sellingPrice: 120,
    quantity: 2,
    reorderThreshold: 5, // qty 2 <= 5, so this one is low
  ),
];

ProviderContainer _container() {
  final container = ProviderContainer(
    overrides: [
      myShopProvider.overrideWith(
        (ref) async =>
            const Shop(id: 's', ownerId: 'o', name: 'Shop', currency: 'USD'),
      ),
      productsStreamProvider.overrideWith((ref) => Stream.value(_products)),
      usedCategoriesProvider.overrideWith((ref) => const <Category>[]),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('the header value line is present and does not overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(_container(), child: const InventoryListScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('2 items'), findsOneWidget);
    // A FittedBox shrinks the line to fit rather than letting it be chopped
    // mid-number, which is what the cramped header used to do.
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the value line opens the exact-figures sheet', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(_container(), child: const InventoryListScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Inventory value'), findsNothing);

    await tester.tap(find.textContaining('2 items'));
    await tester.pumpAndSettle();

    // The figure the header had to abbreviate, now in full.
    expect(find.text('Inventory value'), findsOneWidget);
    expect(find.text(r'$230.00'), findsOneWidget);
    expect(find.text(r'$285.00'), findsOneWidget);
    // Retail 285 - cost 230.
    expect(find.text(r'$55.00'), findsOneWidget);
    expect(find.text('Potential profit'), findsOneWidget);
  });

  testWidgets('an empty inventory still opens a sheet reading zero', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        myShopProvider.overrideWith(
          (ref) async =>
              const Shop(id: 's', ownerId: 'o', name: 'Shop', currency: 'USD'),
        ),
        productsStreamProvider.overrideWith(
          (ref) => Stream.value(const <Product>[]),
        ),
        usedCategoriesProvider.overrideWith((ref) => const <Category>[]),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _harness(container, child: const InventoryListScreen()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('0 items'));
    await tester.pumpAndSettle();

    expect(find.text('Inventory value'), findsOneWidget);
    expect(find.text(r'$0.00'), findsNWidgets(3)); // cost, retail, profit
  });
}
