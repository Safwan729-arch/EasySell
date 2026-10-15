import 'package:ai_shopkeeper/core/config/theme.dart';
import 'package:ai_shopkeeper/core/error/failure.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/restock/domain/restock_plan.dart';
import 'package:ai_shopkeeper/features/restock/presentation/restock_card.dart';
import 'package:ai_shopkeeper/features/restock/presentation/restock_providers.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:ai_shopkeeper/shared/providers/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

RestockItem _item(String name, double daysLeft) => RestockItem(
  product: Product(id: name, shopId: 's1', name: name),
  speed: 1,
  goodStock: daysLeft,
  daysLeft: daysLeft,
  suggestion: 5,
  trend: RestockTrend.flat,
);

Future<void> _pump(WidgetTester tester, AsyncValue<RestockPlan> plan) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [restockPlanProvider.overrideWithValue(plan)],
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
        home: const Scaffold(body: RestockSoonCard()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('names the count and the top two with days left', (tester) async {
    await _pump(
      tester,
      AsyncValue.data(
        RestockPlan(
          buyNow: [_item('Mojo', 0.5), _item('Pepsi', 3.4), _item('Salt', 6)],
          enough: const [],
        ),
      ),
    );
    expect(find.text('Restock soon'), findsOneWidget);
    expect(find.text('3 items to restock'), findsOneWidget);
    expect(find.text('Mojo · today'), findsOneWidget);
    expect(find.text('Pepsi · 3 days'), findsOneWidget);
    expect(find.textContaining('Salt'), findsNothing);
  });

  testWidgets('hidden when nothing needs buying', (tester) async {
    await _pump(
      tester,
      AsyncValue.data(
        RestockPlan(buyNow: const [], enough: [_item('Salt', 40)]),
      ),
    );
    expect(find.text('Restock soon'), findsNothing);
  });

  testWidgets('hidden on error (e.g. 0017 not run yet) and while loading', (
    tester,
  ) async {
    await _pump(
      tester,
      AsyncValue.error(const DatabaseFailure('missing'), StackTrace.empty),
    );
    expect(find.text('Restock soon'), findsNothing);
    await _pump(tester, const AsyncValue.loading());
    expect(find.text('Restock soon'), findsNothing);
  });
}
