import 'package:ai_shopkeeper/core/config/feature_flags.dart';
import 'package:ai_shopkeeper/core/config/theme.dart';
import 'package:ai_shopkeeper/features/auth/data/auth_repository.dart';
import 'package:ai_shopkeeper/features/auth/domain/shop.dart';
import 'package:ai_shopkeeper/features/inventory/domain/category.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/inventory/presentation/category_controller.dart';
import 'package:ai_shopkeeper/features/inventory/presentation/inventory_controller.dart';
import 'package:ai_shopkeeper/features/inventory/presentation/inventory_list_screen.dart';
import 'package:ai_shopkeeper/features/restock/domain/restock_plan.dart';
import 'package:ai_shopkeeper/features/restock/presentation/restock_providers.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:ai_shopkeeper/shared/providers/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// The Inventory header (2026-10-15, S22 screenshot): with scan, voice,
/// restock and add all in the title row, "Inventory" broke into
/// "Inven / tory". Run this file with the release flags on too:
///   flutter test test/widgets/inventory_header_test.dart \
///     --dart-define=VISION_SCAN_ENABLED=true --dart-define=VOICE_SALE_ENABLED=true

RestockItem _item(String id) => RestockItem(
  product: Product(id: id, shopId: 's', name: id),
  speed: 1,
  goodStock: 1,
  daysLeft: 1,
  suggestion: 5,
  trend: RestockTrend.flat,
);

Future<void> _pump(WidgetTester tester, RestockPlan plan, Locale locale) async {
  // Galaxy S22: 1080 px wide at 3.0 → 360 dp, the narrowest phone we target.
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        myShopProvider.overrideWith(
          (ref) async =>
              const Shop(id: 's', ownerId: 'o', name: 'Shop', currency: 'BDT'),
        ),
        productsStreamProvider.overrideWith(
          (ref) => Stream.value(const <Product>[]),
        ),
        usedCategoriesProvider.overrideWith((ref) => const <Category>[]),
        restockPlanProvider.overrideWithValue(AsyncValue.data(plan)),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        locale: locale,
        supportedLocales: supportedAppLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const InventoryListScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final locale in const [Locale('en'), Locale('bn')]) {
    testWidgets('the title stays on one line, uncut ($locale)', (tester) async {
      await _pump(tester, RestockPlan.empty, locale);
      final title = find.text(
        locale.languageCode == 'en' ? 'Inventory' : 'পণ্যতালিকা',
      );
      expect(title, findsOneWidget);
      expect(tester.widget<Text>(title).maxLines, 1);
      expect(
        tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
        isFalse,
        reason: 'the title must fit, not be cut off',
      );
    });
  }

  testWidgets('scan and voice sit inside the search bar', (tester) async {
    await _pump(tester, RestockPlan.empty, const Locale('en'));
    final inSearch = find.descendant(
      of: find.byType(TextField),
      matching: find.byType(IconButton),
    );
    final expected =
        (FeatureFlags.visionScanEnabled ? 1 : 0) +
        (FeatureFlags.voiceSaleEnabled ? 1 : 0);
    expect(inSearch, findsNWidgets(expected));
  });

  testWidgets('the restock button shows how many items to restock', (
    tester,
  ) async {
    await _pump(
      tester,
      RestockPlan(
        buyNow: [_item('a'), _item('b'), _item('c'), _item('d')],
        enough: const [],
      ),
      const Locale('en'),
    );
    final badge = find.ancestor(
      of: find.byIcon(Icons.shopping_basket_outlined),
      matching: find.byType(Badge),
    );
    expect(badge, findsOneWidget);
    expect(tester.widget<Badge>(badge).isLabelVisible, isTrue);
    expect(
      find.descendant(of: badge, matching: find.text('4')),
      findsOneWidget,
    );
  });

  testWidgets('no number when nothing needs restocking', (tester) async {
    await _pump(tester, RestockPlan.empty, const Locale('en'));
    final badge = find.ancestor(
      of: find.byIcon(Icons.shopping_basket_outlined),
      matching: find.byType(Badge),
    );
    expect(badge, findsOneWidget);
    expect(tester.widget<Badge>(badge).isLabelVisible, isFalse);
  });
}
