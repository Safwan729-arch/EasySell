import 'package:ai_shopkeeper/core/config/theme.dart';
import 'package:ai_shopkeeper/core/error/failure.dart';
import 'package:ai_shopkeeper/core/error/result.dart';
import 'package:ai_shopkeeper/features/auth/data/auth_repository.dart';
import 'package:ai_shopkeeper/features/auth/domain/shop.dart';
import 'package:ai_shopkeeper/features/expiry/data/batch_repository.dart';
import 'package:ai_shopkeeper/features/expiry/domain/expiry_estimate.dart';
import 'package:ai_shopkeeper/features/expiry/domain/product_batch.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/deliveries_section.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/expiry_providers.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/expiry_reconciler.dart';
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

import '../support/expiry_fakes.dart';

class _Repo implements BatchRepository {
  _Repo({this.failRemove = false});
  final bool failRemove;

  @override
  Future<Result<List<ProductBatch>>> fetchClosedBatches(
    String productId, {
    int limit = 10,
  }) async => const Result.success([]);

  @override
  Future<Result<void>> removeExpiredStock({
    required String shopId,
    required String batchId,
  }) async => failRemove
      ? const Result.failure(
          NetworkFailure('No internet connection. Please try again.'),
        )
      : const Result.success(null);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _pepsi = Product(id: 'pepsi', shopId: 's1', name: 'Pepsi', quantity: 15);
final _today = DateTime(2026, 10, 21);

Future<void> _pump(WidgetTester tester, _Repo repo) async {
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
    today: _today,
    shopWarnDays: 7,
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        productExpiryProvider.overrideWithValue(byProduct),
        batchRepositoryProvider.overrideWithValue(repo),
        nowProvider.overrideWithValue(() => _today),
        myShopProvider.overrideWith(
          (ref) async => const Shop(
            id: 's1',
            ownerId: 'o1',
            name: 'Shop',
            currency: 'BDT',
          ),
        ),
        expiryReconcilerProvider.overrideWithValue(NoopReconciler()),
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
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting();
  });

  testWidgets(
    'an expired delivery offers Remove from stock, a good one does not',
    (tester) async {
      await _pump(tester, _Repo());

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

  testWidgets('a failed removal says why instead of doing nothing', (
    tester,
  ) async {
    await _pump(tester, _Repo(failRemove: true));
    // In the app the shop is long loaded by the time this page shows.
    await ProviderScope.containerOf(
      tester.element(find.byType(DeliveriesSection)),
    ).read(myShopProvider.future);

    await tester.tap(find.text('Remove from stock'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Remove from stock'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('No internet connection. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('Expired stock removed'), findsNothing);
  });
}
