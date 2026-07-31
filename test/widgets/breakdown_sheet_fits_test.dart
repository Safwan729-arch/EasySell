import 'package:ai_shopkeeper/core/config/theme.dart';
import 'package:ai_shopkeeper/features/analytics/domain/analytics.dart';
import 'package:ai_shopkeeper/features/dashboard/presentation/summary_breakdown_sheet.dart';
import 'package:ai_shopkeeper/features/inventory/domain/inventory_totals.dart';
import 'package:ai_shopkeeper/features/inventory/presentation/inventory_value_sheet.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:ai_shopkeeper/shared/providers/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// Both breakdown sheets are a Column of fixed-height rows, so on a short screen
/// they can outgrow `showModalBottomSheet`'s default 9/16-of-screen cap and
/// overflow — the dashboard sheet did, by 199px at 600dp tall, before both
/// sheets became scroll-controlled.
///
/// The 800x600 test surface is the short screen; the assertion is simply that
/// opening the sheet raises no layout exception.
Widget _app(Widget Function(BuildContext) onPressed) => MaterialApp(
  theme: AppTheme.light,
  locale: const Locale('en'),
  supportedLocales: supportedAppLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Builder(builder: (context) => Scaffold(body: onPressed(context))),
);

Widget _opener(VoidCallback open) => Center(
  child: ElevatedButton(onPressed: open, child: const Text('open')),
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('the dashboard summary sheet fits a short screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        (context) => _opener(
          () => showSummaryBreakdownSheet(
            context,
            summary: const DashboardSummary(
              revenue: 1000,
              cost: 600,
              profit: 400,
              unitsSold: 20,
              inventoryValue: 5000,
            ),
            period: AnalyticsPeriod.month,
            currency: 'USD',
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Breakdown'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the inventory value sheet fits a short screen', (tester) async {
    await tester.pumpWidget(
      _app(
        (context) => _opener(
          () => showInventoryValueSheet(
            context,
            totals: const InventoryTotals(
              productCount: 7,
              costValue: 26510,
              retailValue: 31000,
              lowStockCount: 2,
            ),
            currency: 'USD',
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Inventory value'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
