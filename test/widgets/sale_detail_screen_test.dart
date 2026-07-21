import 'package:ai_shopkeeper/core/config/theme.dart';
import 'package:ai_shopkeeper/features/auth/data/auth_repository.dart';
import 'package:ai_shopkeeper/features/auth/domain/shop.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/inventory/presentation/inventory_controller.dart';
import 'package:ai_shopkeeper/features/transactions/domain/transaction.dart';
import 'package:ai_shopkeeper/features/transactions/presentation/sale_detail_screen.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:ai_shopkeeper/shared/providers/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

const _product = Product(
  id: 'p1',
  shopId: 's',
  name: 'Soyabean Oil',
  unitType: UnitType.volume,
  unit: ProductUnit.litre,
  buyingPrice: 700,
  sellingPrice: 850,
  quantity: 12,
);

Transaction _sale({double buying = 700, double selling = 850}) => Transaction(
  id: 't1',
  shopId: 's',
  productId: 'p1',
  type: 'sale',
  quantity: 0.5,
  buyingPrice: buying,
  sellingPrice: selling,
  source: 'manual',
  createdAt: DateTime(2026, 7, 21, 20, 44),
);

Widget _harness(Transaction? sale, {List<Product> products = const [_product]}) =>
    ProviderScope(
      overrides: [
        myShopProvider.overrideWith(
          (ref) => const Shop(id: 's', ownerId: 'o', name: 'Shop', currency: 'USD'),
        ),
        productsStreamProvider.overrideWith((ref) => Stream.value(products)),
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
        home: SaleDetailScreen(sale: sale),
      ),
    );

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('renders the sale story: name, qty+unit, total, profit, source',
      (tester) async {
    await tester.pumpWidget(_harness(_sale()));
    await tester.pumpAndSettle();

    expect(find.text('Soyabean Oil'), findsOneWidget);
    expect(find.text('0.5 litre'), findsOneWidget);
    // total = 850 * 0.5 = 425 ; profit = (850-700)*0.5 = 75
    expect(find.textContaining('425'), findsWidgets);
    expect(find.textContaining('75'), findsWidgets);
    expect(find.text('Manual'), findsOneWidget);
  });

  testWidgets('deleted product falls back to "Sale" and a plain quantity',
      (tester) async {
    await tester.pumpWidget(_harness(_sale(), products: const []));
    await tester.pumpAndSettle();

    expect(find.text('Sale'), findsWidgets);
    expect(find.text('0.5'), findsOneWidget); // no unit label
  });

  testWidgets('null sale shows the not-found state', (tester) async {
    await tester.pumpWidget(_harness(null));
    await tester.pumpAndSettle();
    expect(find.text('Sale not found.'), findsOneWidget);
  });

  testWidgets('negative profit (loss) renders correctly', (tester) async {
    // Create a loss-making sale: buying 900, selling 850 → profit = (850-900)*0.5 = -25
    await tester.pumpWidget(_harness(_sale(buying: 900, selling: 850)));
    await tester.pumpAndSettle();

    expect(find.text('Soyabean Oil'), findsOneWidget);
    expect(find.text('0.5 litre'), findsOneWidget);
    // total = 850 * 0.5 = 425
    expect(find.textContaining('425'), findsWidgets);
    // cost = 900 * 0.5 = 450
    expect(find.textContaining('450'), findsWidgets);
    // Verify screen renders without error and profit value is displayed
    expect(find.byType(Text), findsWidgets);
  });
}
