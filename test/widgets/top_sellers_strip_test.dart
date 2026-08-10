import 'package:ai_shopkeeper/features/analytics/presentation/analytics_controller.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/inventory/presentation/inventory_controller.dart';
import 'package:ai_shopkeeper/features/scan/presentation/scan_session_controller.dart';
import 'package:ai_shopkeeper/features/scan/presentation/top_sellers_strip.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

const _pepsi = Product(
  id: 'p-pepsi',
  shopId: 's1',
  name: 'Pepsi',
  sellingPrice: 50,
  quantity: 10,
  unit: ProductUnit.pcs,
);
const _gone = Product(
  id: 'p-gone',
  shopId: 's1',
  name: 'Sold Out Soap',
  sellingPrice: 30,
  quantity: 0,
  unit: ProductUnit.pcs,
);

Future<ProviderContainer> _pump(
  WidgetTester tester,
  List<BestSeller> sellers,
) async {
  final c = ProviderContainer(
    overrides: [
      productsStreamProvider.overrideWith(
        (ref) => Stream.value([_pepsi, _gone]),
      ),
      bestSellersProvider.overrideWithValue(AsyncValue.data(sellers)),
    ],
  );
  addTearDown(c.dispose);
  final sub = c.listen(productsStreamProvider, (_, _) {});
  addTearDown(sub.close);
  await c.read(productsStreamProvider.future);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: TopSellersStrip()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return c;
}

BestSeller _s(String id, String name, double units) => BestSeller(
  productId: id,
  name: name,
  categoryId: null,
  units: units,
  revenue: 0,
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('a tap stages the product in the tray, with no AI call', (
    tester,
  ) async {
    final c = await _pump(tester, [_s('p-pepsi', 'Pepsi', 40)]);
    await tester.tap(find.text('Pepsi'));
    await tester.pump();

    final items = c.read(scanSessionProvider);
    expect(items.single.product?.id, 'p-pepsi');
    expect(items.single.quantity, 1);
  });

  testWidgets('tapping twice merges into one chip', (tester) async {
    final c = await _pump(tester, [_s('p-pepsi', 'Pepsi', 40)]);
    await tester.tap(find.text('Pepsi'));
    await tester.pump();
    await tester.tap(find.text('Pepsi'));
    await tester.pump();

    expect(c.read(scanSessionProvider).length, 1);
    expect(c.read(scanSessionProvider).single.quantity, 2);
  });

  testWidgets('out-of-stock sellers are not offered', (tester) async {
    await _pump(tester, [_s('p-gone', 'Sold Out Soap', 90)]);
    expect(find.text('Sold Out Soap'), findsNothing);
  });

  testWidgets('a shop with no sales history shows no strip', (tester) async {
    await _pump(tester, const []);
    // find.byType(SizedBox) passes either way -- the populated branch also
    // returns a top-level SizedBox (its `height: 48` wrapper). Assert on the
    // one thing that actually distinguishes "hidden" from "shown": no chips.
    expect(find.byType(ActionChip), findsNothing);
    expect(find.text('Pepsi'), findsNothing);
  });
}
