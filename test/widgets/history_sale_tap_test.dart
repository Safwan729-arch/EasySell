import 'package:ai_shopkeeper/core/config/theme.dart';
import 'package:ai_shopkeeper/features/auth/data/auth_repository.dart';
import 'package:ai_shopkeeper/features/auth/domain/shop.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/inventory/presentation/inventory_controller.dart';
import 'package:ai_shopkeeper/features/transactions/domain/transaction.dart';
import 'package:ai_shopkeeper/features/transactions/presentation/history_screen.dart';
import 'package:ai_shopkeeper/features/transactions/presentation/sale_detail_screen.dart';
import 'package:ai_shopkeeper/features/transactions/presentation/sales_providers.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:ai_shopkeeper/shared/providers/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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

// Anchored to "today" (not a fixed calendar date) so the sale always falls
// inside the History screen's default "Today" scope regardless of when the
// suite runs. A hardcoded past date silently drops out of scope once the clock
// moves past it, which made this test pass only on the day it was written.
final _sale = Transaction(
  id: 't1',
  shopId: 's',
  productId: 'p1',
  type: 'sale',
  quantity: 0.5,
  buyingPrice: 700,
  sellingPrice: 850,
  source: 'manual',
  createdAt: DateTime.now(),
);

GoRouter _router() => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, _) => const HistoryScreen()),
    GoRoute(
      path: '/history/sale/:id',
      builder: (_, state) =>
          SaleDetailScreen(sale: state.extra as Transaction?),
    ),
  ],
);

Widget _harness() => ProviderScope(
  overrides: [
    myShopProvider.overrideWith(
      (ref) => const Shop(id: 's', ownerId: 'o', name: 'Shop', currency: 'USD'),
    ),
    productsStreamProvider.overrideWith((ref) => Stream.value(const [_product])),
    recentSalesProvider.overrideWith((ref) async => [_sale]),
    earliestSaleDateProvider.overrideWith((ref) async => null),
  ],
  child: MaterialApp.router(
    routerConfig: _router(),
    theme: AppTheme.light,
    locale: const Locale('en'),
    supportedLocales: supportedAppLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
  ),
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('tapping a single sale row opens its detail screen',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    // The row shows the product name; the detail screen title does not exist yet.
    expect(find.text('Sale details'), findsNothing);

    // The product name renders inside a RichText (so the "+N" badge can be
    // styled independently); find.text needs findRichText to see it.
    await tester.tap(find.text('Soyabean Oil', findRichText: true));
    await tester.pumpAndSettle();

    // Now on the detail screen.
    expect(find.text('Sale details'), findsOneWidget);
    expect(find.text('0.5 litre'), findsOneWidget);
  });
}
