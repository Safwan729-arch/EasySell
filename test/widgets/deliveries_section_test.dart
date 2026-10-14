import 'package:ai_shopkeeper/core/config/theme.dart';
import 'package:ai_shopkeeper/core/error/result.dart';
import 'package:ai_shopkeeper/features/expiry/data/batch_repository.dart';
import 'package:ai_shopkeeper/features/expiry/domain/expiry_estimate.dart';
import 'package:ai_shopkeeper/features/expiry/domain/product_batch.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/deliveries_section.dart';
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
import 'package:intl/date_symbol_data_local.dart';

class _Repo implements BatchRepository {
  @override
  Future<Result<List<ProductBatch>>> fetchClosedBatches(
    String productId, {
    int limit = 10,
  }) async => const Result.success([]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _pepsi = Product(id: 'pepsi', shopId: 's1', name: 'Pepsi', quantity: 15);

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting();
  });

  testWidgets(
    'an expired delivery offers Remove from stock, a good one does not',
    (tester) async {
      final today = DateTime(2026, 10, 21);
      final byProduct = estimateAll(
        products: [_pepsi],
        openBatches: [
          ProductBatch(
            id: 'old',
            shopId: 's1',
            productId: 'pepsi',
            quantity: 5,
            receivedOn: DateTime(2026, 10, 1),
            expiryDate: DateTime(2026, 10, 20),
            expiredQty: 5,
          ),
          ProductBatch(
            id: 'new',
            shopId: 's1',
            productId: 'pepsi',
            quantity: 10,
            receivedOn: DateTime(2026, 10, 10),
            expiryDate: DateTime(2026, 12, 15),
          ),
        ],
        today: today,
        shopWarnDays: 7,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            productExpiryProvider.overrideWithValue(byProduct),
            batchRepositoryProvider.overrideWithValue(_Repo()),
            nowProvider.overrideWithValue(() => today),
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
            home: const Scaffold(
              body: SingleChildScrollView(
                child: DeliveriesSection(product: _pepsi),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Deliveries'), findsOneWidget);
      expect(find.text('Expired'), findsOneWidget);
      expect(find.text('Good'), findsOneWidget);
      expect(find.text('Remove from stock'), findsOneWidget);
      expect(
        find.text('Added Oct 1, 2026 · Expires Oct 20, 2026'),
        findsOneWidget,
      );
    },
  );
}
