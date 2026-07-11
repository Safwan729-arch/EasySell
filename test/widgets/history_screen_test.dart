import 'package:ai_shopkeeper/core/config/theme.dart';
import 'package:ai_shopkeeper/features/auth/data/auth_repository.dart';
import 'package:ai_shopkeeper/features/auth/domain/shop.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/inventory/presentation/inventory_controller.dart';
import 'package:ai_shopkeeper/features/transactions/domain/transaction.dart';
import 'package:ai_shopkeeper/features/transactions/presentation/history_screen.dart';
import 'package:ai_shopkeeper/features/transactions/presentation/sales_providers.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:ai_shopkeeper/shared/providers/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

Transaction _sale(
  String id,
  String productId, {
  String? group,
  double qty = 1,
  double price = 35,
  DateTime? at,
}) => Transaction(
  id: id,
  shopId: 's',
  productId: productId,
  type: 'sale',
  quantity: qty,
  sellingPrice: price,
  saleGroupId: group,
  createdAt: at ?? DateTime.now(),
);

Product _prod(String id, String name) => Product(id: id, shopId: 's', name: name);

/// The Item label is a RichText (so the "+N" badge can be styled), which
/// find.text can't see — this matches its flattened plain text instead.
bool _richTextHas(String needle) => find
    .byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText().contains(needle),
    )
    .evaluate()
    .isNotEmpty;

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Widget harness(List<Transaction> sales, List<Product> products) =>
      ProviderScope(
        overrides: [
          myShopProvider.overrideWith(
            (ref) => const Shop(
              id: 's',
              ownerId: 'o',
              name: 'Shop',
              currency: 'USD',
            ),
          ),
          recentSalesProvider.overrideWith((ref) async => sales),
          productsStreamProvider.overrideWith((ref) => Stream.value(products)),
          earliestSaleDateProvider.overrideWith((ref) async => null),
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
          home: const HistoryScreen(),
        ),
      );

  void usePhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('a cart receipt reads as its items ("Loose rice +1"), not "2 items"', (
    tester,
  ) async {
    usePhone(tester);
    final now = DateTime.now();
    await tester.pumpWidget(
      harness(
        [
          _sale('a', 'rice', group: 'g1', qty: 1.5, price: 80, at: now), // $120
          _sale('b', 'soap', group: 'g1', qty: 4, price: 35, at: now), //   $140
          _sale('c', 'soap', qty: 1, price: 35, at: now), // single         $35
        ],
        [_prod('rice', 'Loose rice'), _prod('soap', 'Lifebuoy soap')],
      ),
    );
    await tester.pumpAndSettle();

    // Receipt shows its lead product + a "+1" badge, never the opaque count.
    expect(_richTextHas('Loose rice'), isTrue);
    expect(_richTextHas('+1'), isTrue);
    expect(find.text('2 items'), findsNothing);

    // Mixed-unit receipt shows a dash for Qty; the single sale shows a real 1.
    expect(find.text('—'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);

    // The single sale renders its full name (no truncation of the model value).
    expect(_richTextHas('Lifebuoy soap'), isTrue);
  });

  testWidgets('tapping a receipt expands to its per-product lines', (
    tester,
  ) async {
    usePhone(tester);
    final now = DateTime.now();
    await tester.pumpWidget(
      harness(
        [
          _sale('a', 'rice', group: 'g1', qty: 1.5, price: 80, at: now),
          _sale('b', 'soap', group: 'g1', qty: 4, price: 35, at: now),
        ],
        [_prod('rice', 'Loose rice'), _prod('soap', 'Lifebuoy soap')],
      ),
    );
    await tester.pumpAndSettle();

    // Collapsed: the per-line rows (plain Text) aren't shown yet.
    expect(find.text('Loose rice'), findsNothing);

    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();

    // Expanded: every product line is listed.
    expect(find.text('Loose rice'), findsOneWidget);
    expect(find.text('Lifebuoy soap'), findsOneWidget);
  });
}
