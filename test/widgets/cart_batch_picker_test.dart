import 'package:ai_shopkeeper/core/config/theme.dart';
import 'package:ai_shopkeeper/features/auth/data/auth_repository.dart';
import 'package:ai_shopkeeper/features/auth/domain/shop.dart';
import 'package:ai_shopkeeper/features/cart/domain/cart_line.dart';
import 'package:ai_shopkeeper/features/cart/presentation/cart_controller.dart';
import 'package:ai_shopkeeper/features/cart/presentation/cart_screen.dart';
import 'package:ai_shopkeeper/features/expiry/domain/expiry_estimate.dart';
import 'package:ai_shopkeeper/features/expiry/domain/product_batch.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/expiry_providers.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:ai_shopkeeper/shared/providers/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

class _SeededCart extends CartController {
  _SeededCart(this._seed);
  final List<CartLine> _seed;
  @override
  List<CartLine> build() => _seed;
}

const _brush = Product(
  id: 'brush',
  shopId: 's',
  name: 'Toothbrush',
  sellingPrice: 5,
  quantity: 26,
);
const _soap = Product(
  id: 'soap',
  shopId: 's',
  name: 'Soap',
  sellingPrice: 30,
  quantity: 10,
);

ProductBatch _batch(String id, double qty, int expiryDay, {int created = 0}) =>
    ProductBatch(
      id: id,
      shopId: 's',
      productId: 'brush',
      quantity: qty,
      receivedOn: DateTime(2026, 10, 15),
      expiryDate: DateTime(2026, 10, expiryDay),
      createdAt: DateTime(2026, 10, 15, 9, created),
    );

final _byProduct = {
  'brush': estimateProductExpiry(
    productId: 'brush',
    stock: 26,
    openBatches: [_batch('soon', 10, 16), _batch('fresh', 16, 21, created: 1)],
    today: DateTime(2026, 10, 15),
    shopWarnDays: 7,
  ),
};

Widget _harness(
  List<CartLine> lines, {
  Map<String, ProductExpiry>? byProduct,
}) => ProviderScope(
  overrides: [
    cartControllerProvider.overrideWith(() => _SeededCart(lines)),
    myShopProvider.overrideWith(
      (ref) =>
          const Shop(id: 's', ownerId: 'o', name: 'Test Shop', currency: 'BDT'),
    ),
    productExpiryProvider.overrideWith((ref) => byProduct ?? _byProduct),
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

  void usePhoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('with several batches the seller must choose one', (
    tester,
  ) async {
    usePhoneSize(tester);
    await tester.pumpWidget(
      _harness([const CartLine(product: _brush, quantity: 1)]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Batch: Choose'), findsOneWidget);
    expect(find.text('Choose which batch this comes from'), findsOneWidget);
    await tester.tap(find.text('Batch: Choose'));
    await tester.pumpAndSettle();

    expect(find.text('Sell from which batch?'), findsOneWidget);
    // One batch holds the line, so there is no "several batches" shortcut.
    expect(find.text('Several batches, soonest expiry first'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('batch-option-fresh')));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(CartScreen)),
    );
    expect(container.read(cartControllerProvider).single.batchId, 'fresh');
    expect(find.textContaining('Batch: Expires'), findsOneWidget);
    expect(find.text('Choose which batch this comes from'), findsNothing);
  });

  testWidgets('with one batch the line shows it without asking', (
    tester,
  ) async {
    usePhoneSize(tester);
    await tester.pumpWidget(
      _harness(
        [const CartLine(product: _brush, quantity: 1)],
        byProduct: {
          'brush': estimateProductExpiry(
            productId: 'brush',
            stock: 16,
            openBatches: [_batch('fresh', 16, 21)],
            today: DateTime(2026, 10, 15),
            shopWarnDays: 7,
          ),
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Batch: Expires'), findsOneWidget);
    expect(find.text('Batch: Choose'), findsNothing);
    expect(find.text('Choose which batch this comes from'), findsNothing);
  });

  testWidgets('"several batches" is offered when no one batch is enough', (
    tester,
  ) async {
    usePhoneSize(tester);
    await tester.pumpWidget(
      _harness([const CartLine(product: _brush, quantity: 20)]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Batch: Choose'));
    await tester.pumpAndSettle();
    expect(find.text('Several batches, soonest expiry first'), findsOneWidget);
  });

  testWidgets('a product with one place to sell from shows no picker', (
    tester,
  ) async {
    usePhoneSize(tester);
    await tester.pumpWidget(
      _harness([const CartLine(product: _soap, quantity: 1)]),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Batch:'), findsNothing);
  });

  testWidgets('a chosen batch with too few left says so', (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(
      _harness([
        const CartLine(product: _brush, quantity: 11, batchId: 'soon'),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('left in this batch'), findsOneWidget);
  });
}
