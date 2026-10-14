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
  final removed = <String>[];
  final undated = <String>[];

  @override
  Future<Result<void>> removeUndatedStock({
    required String shopId,
    required String productId,
    required double quantity,
    required String removalId,
  }) async {
    undated.add('$productId $quantity');
    return const Result.success(null);
  }

  @override
  Future<Result<List<ProductBatch>>> fetchClosedBatches(
    String productId, {
    int limit = 10,
  }) async => const Result.success([]);

  @override
  Future<Result<void>> removeStock({
    required String shopId,
    required String batchId,
    double? quantity,
    bool close = true,
    String? removalId,
  }) async {
    removed.add('$batchId $quantity${close ? '' : ' keep-open'}');
    return failRemove
        ? const Result.failure(
            NetworkFailure('No internet connection. Please try again.'),
          )
        : const Result.success(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _pepsi = Product(id: 'pepsi', shopId: 's1', name: 'Pepsi', quantity: 15);
final _today = DateTime(2026, 10, 21);

Future<void> _pump(WidgetTester tester, _Repo repo, {double stock = 15}) async {
  final pepsi = _pepsi.copyWith(quantity: stock);
  final byProduct = estimateAll(
    products: [pepsi],
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
        home: Scaffold(
          body: SingleChildScrollView(child: DeliveriesSection(product: pepsi)),
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

  testWidgets('no "Add expiry date" when every unit already has a date', (
    tester,
  ) async {
    // 15 in stock, 5 + 10 in deliveries: nothing is left to date, and the
    // link read as "you still have to add a date" (2026-10-15, Pepsi).
    await _pump(tester, _Repo());
    expect(find.text('Add expiry date'), findsNothing);
  });

  testWidgets('"Add expiry date" shows while some stock has no date', (
    tester,
  ) async {
    await _pump(tester, _Repo(), stock: 18);
    expect(find.text('Add expiry date'), findsOneWidget);
  });

  testWidgets('stock with no date has its own row and can be removed', (
    tester,
  ) async {
    // The product form has no stock box any more, so undated stock (all of a
    // soap's) needs its own way off the shelf.
    final repo = _Repo();
    await _pump(tester, repo, stock: 18);
    await ProviderScope.containerOf(
      tester.element(find.byType(DeliveriesSection)),
    ).read(myShopProvider.future);

    expect(find.text('No expiry date'), findsOneWidget);
    expect(find.text('3 pcs left'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('undated-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from stock').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '2',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Remove'),
      ),
    );
    await tester.pumpAndSettle();

    expect(repo.undated, ['pepsi 2.0']);
  });

  testWidgets('no "No expiry date" row when every unit has a date', (
    tester,
  ) async {
    await _pump(tester, _Repo());
    expect(find.text('No expiry date'), findsNothing);
  });

  testWidgets('the remove dialog keeps its two buttons side by side', (
    tester,
  ) async {
    // On the S22 (360 dp wide) "Cancel" + "Remove from stock" did not fit on
    // one row, so the dialog stacked them one above the other.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await _pump(tester, _Repo());

    await tester.tap(find.text('Remove from stock'));
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    final cancel = find.descendant(of: dialog, matching: find.text('Cancel'));
    final remove = find.descendant(of: dialog, matching: find.text('Remove'));
    expect(tester.getCenter(cancel).dy, tester.getCenter(remove).dy);
    expect(tester.getCenter(cancel).dx, lessThan(tester.getCenter(remove).dx));
  });

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
        matching: find.text('Remove'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('No internet connection. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('Removed from stock'), findsNothing);
  });

  testWidgets(
    'a good delivery can be removed from its menu; there is no None left',
    (tester) async {
      // A sold-out delivery closes by itself, so the menu has no manual
      // "None left"; it used to close a delivery without lowering stock,
      // which left thrown-away units counted as good (2026-10-15).
      final repo = _Repo();
      await _pump(tester, repo);
      await ProviderScope.containerOf(
        tester.element(find.byType(DeliveriesSection)),
      ).read(myShopProvider.future);

      await tester.tap(find.byType(PopupMenuButton<String>).last);
      await tester.pumpAndSettle();
      expect(find.text('None left'), findsNothing);
      await tester.tap(find.text('Remove from stock').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Remove'),
        ),
      );
      await tester.pumpAndSettle();

      expect(repo.removed, ['new 10.0']);
      expect(find.text('Removed from stock'), findsOneWidget);
    },
  );

  Future<_Repo> openGoodRemove(WidgetTester tester) async {
    final repo = _Repo();
    await _pump(tester, repo);
    await ProviderScope.containerOf(
      tester.element(find.byType(DeliveriesSection)),
    ).read(myShopProvider.future);
    await tester.tap(find.byType(PopupMenuButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from stock').last);
    await tester.pumpAndSettle();
    return repo;
  }

  Finder dialogRemove() => find.descendant(
    of: find.byType(AlertDialog),
    matching: find.widgetWithText(FilledButton, 'Remove'),
  );

  testWidgets('part of a good delivery can be removed', (tester) async {
    // One broken bottle: the batch stays open with the rest.
    final repo = await openGoodRemove(tester);
    final field = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(field).controller!.text, '10');

    await tester.enterText(field, '3');
    await tester.pumpAndSettle();
    await tester.tap(dialogRemove());
    await tester.pumpAndSettle();

    expect(repo.removed, ['new 3.0 keep-open']);
  });

  testWidgets('more than the batch has cannot be removed', (tester) async {
    final repo = await openGoodRemove(tester);
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '11',
    );
    await tester.pumpAndSettle();

    expect(tester.widget<FilledButton>(dialogRemove()).onPressed, isNull);
    expect(find.text('Only 10 pcs left in this batch'), findsOneWidget);
    expect(repo.removed, isEmpty);
  });
}
