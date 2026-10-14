import 'package:ai_shopkeeper/core/config/theme.dart';
import 'package:ai_shopkeeper/features/auth/data/auth_repository.dart';
import 'package:ai_shopkeeper/features/auth/domain/shop.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/expiry_providers.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/inventory/presentation/category_controller.dart';
import 'package:ai_shopkeeper/features/inventory/presentation/product_form_screen.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:ai_shopkeeper/shared/providers/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

const _pepsi = Product(
  id: 'pepsi',
  shopId: 's1',
  name: 'Pepsi',
  quantity: 30,
  sellingPrice: 25,
  buyingPrice: 20,
);

Widget _app(Product? product) => ProviderScope(
  overrides: [
    myShopProvider.overrideWith(
      (ref) =>
          const Shop(id: 's1', ownerId: 'o1', name: 'Shop', currency: 'BDT'),
    ),
    categoriesStreamProvider.overrideWith((ref) => Stream.value(const [])),
    productExpiryProvider.overrideWith((ref) => const {}),
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
    home: ProductFormScreen(product: product),
  ),
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('editing a product has no stock box', (tester) async {
    // Stock changes through sales, Restock and Remove from stock only; a
    // typed number here bypassed all of them and the batches (2026-10-15).
    await tester.pumpWidget(_app(_pepsi));
    await tester.pumpAndSettle();
    expect(find.text('Stock (pieces) *'), findsNothing);
    expect(find.text('Reorder at'), findsOneWidget);
  });

  testWidgets('a new product still takes its first stock', (tester) async {
    await tester.pumpWidget(_app(null));
    await tester.pumpAndSettle();
    expect(find.text('Stock (pieces) *'), findsOneWidget);
  });
}
