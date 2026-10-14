import 'package:ai_shopkeeper/core/config/theme.dart';
import 'package:ai_shopkeeper/features/expiry/domain/expiry_estimate.dart';
import 'package:ai_shopkeeper/features/expiry/domain/product_batch.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/batch_form_sheet.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/expiry_providers.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/today_provider.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:ai_shopkeeper/shared/providers/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

const _pepsi = Product(id: 'pepsi', shopId: 's1', name: 'Pepsi', quantity: 29);
final _batch = ProductBatch(
  id: 'b',
  shopId: 's1',
  productId: 'pepsi',
  quantity: 30,
  pickedQty: 1,
  receivedOn: DateTime(2026, 10, 15),
  expiryDate: DateTime(2026, 10, 24),
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('editing a delivery shows its amount but cannot change it', (
    tester,
  ) async {
    // Stock moves only through sales, Restock and Remove; an editable amount
    // here changed the batch but not stock and confused the user.
    final today = DateTime(2026, 10, 15);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nowProvider.overrideWithValue(() => today),
          productExpiryProvider.overrideWith(
            (ref) => estimateAll(
              products: [_pepsi],
              openBatches: [_batch],
              today: today,
              shopWarnDays: 7,
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
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showBatchFormSheet(context, product: _pepsi, batch: _batch),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Edit delivery'), findsOneWidget);
    expect(find.text('29 pcs left'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });
}
