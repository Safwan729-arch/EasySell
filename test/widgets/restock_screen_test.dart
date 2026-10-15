import 'package:ai_shopkeeper/core/config/theme.dart';
import 'package:ai_shopkeeper/core/error/failure.dart';
import 'package:ai_shopkeeper/features/auth/data/auth_repository.dart';
import 'package:ai_shopkeeper/features/auth/domain/shop.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/restock/domain/restock_plan.dart';
import 'package:ai_shopkeeper/features/restock/presentation/restock_providers.dart';
import 'package:ai_shopkeeper/features/restock/presentation/restock_screen.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:ai_shopkeeper/shared/providers/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

const _mojo = Product(id: 'mojo', shopId: 's1', name: 'Mojo', quantity: 10);
const _salt = Product(id: 'salt', shopId: 's1', name: 'Salt', quantity: 40);

final _plan = RestockPlan(
  buyNow: [
    RestockItem(
      product: _mojo,
      speed: 5,
      goodStock: 10,
      daysLeft: 2,
      suggestion: 35,
      trend: RestockTrend.up,
    ),
  ],
  enough: [
    RestockItem(
      product: _salt,
      speed: 1,
      goodStock: 40,
      daysLeft: 40,
      suggestion: 0,
      trend: RestockTrend.flat,
    ),
  ],
);

Future<void> _pump(WidgetTester tester, AsyncValue<RestockPlan> plan) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        restockPlanProvider.overrideWithValue(plan),
        myShopProvider.overrideWith(
          (ref) async => const Shop(
            id: 's1',
            ownerId: 'o1',
            name: 'Shop',
            currency: 'BDT',
          ),
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
        home: const RestockScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('a Buy-now row says when it runs out and how many to buy', (
    tester,
  ) async {
    await _pump(tester, AsyncValue.data(_plan));
    expect(find.text('Buy now'), findsOneWidget);
    expect(find.text('Mojo'), findsOneWidget);
    expect(find.text('Runs out in 2 days'), findsOneWidget);
    expect(find.text('Buy about 35 pcs'), findsOneWidget);
    expect(find.text('10 pcs in stock'), findsOneWidget);
    expect(find.byIcon(Icons.trending_up), findsOneWidget);
    // Enough-for-now starts collapsed.
    expect(find.text('Enough for now (1)'), findsOneWidget);
    expect(find.text('Salt'), findsNothing);
  });

  testWidgets('tapping a Buy-now row opens restock with the suggestion', (
    tester,
  ) async {
    await _pump(tester, AsyncValue.data(_plan));
    await tester.tap(find.text('Mojo'));
    await tester.pumpAndSettle();
    // The sheet's title and its confirm button both read "Confirm restock".
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('35 pcs'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('empty plan shows the empty state', (tester) async {
    await _pump(tester, const AsyncValue.data(RestockPlan.empty));
    expect(
      find.text(
        'Nothing to restock yet. Suggestions appear after a few days of sales.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a failed load shows the error with Retry, not a crash', (
    tester,
  ) async {
    await _pump(
      tester,
      AsyncValue.error(
        const DatabaseFailure('function get_restock_speeds does not exist'),
        StackTrace.empty,
      ),
    );
    expect(find.text('Could not load the restock list.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
