import 'package:ai_shopkeeper/core/config/theme.dart';
import 'package:ai_shopkeeper/core/error/result.dart';
import 'package:ai_shopkeeper/features/auth/data/auth_repository.dart';
import 'package:ai_shopkeeper/features/auth/domain/shop.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/expiry_gate.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/expiry_reconciler.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/transactions/data/transaction_repository.dart';
import 'package:ai_shopkeeper/features/transactions/domain/transaction.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:ai_shopkeeper/shared/providers/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'expiry_fakes.dart';

/// 850 sell / 700 buy => 150 profit on one unit. Chosen so a 162 discount
/// lands 12 below cost, which is the below-cost warning's test case.
const kOil = Product(
  id: 'p2',
  shopId: 's1',
  name: 'Oil',
  sellingPrice: 850,
  buyingPrice: 700,
  quantity: 100,
);

const kPepsi = Product(
  id: 'p1',
  shopId: 's1',
  name: 'Pepsi',
  sellingPrice: 45,
  buyingPrice: 30,
  quantity: 100,
);

/// A container with a resolved shop.
///
/// AWAITING THE SHOP IS NOT OPTIONAL. `CartController.build` watches
/// `myShopProvider` to key its lifecycle to the signed-in shop, so the cart is
/// reset when that provider resolves. Stage a cart before the shop settles and
/// the lines vanish underneath the test, which reads as a broken feature
/// rather than a broken harness.
Future<ProviderContainer> cartContainer({
  TransactionRepository? repo,
  ExpiryGate gate = const PassingExpiryGate(),
}) async {
  final container = ProviderContainer(
    overrides: [
      myShopProvider.overrideWith(
        (ref) async =>
            const Shop(id: 's1', ownerId: 'o1', name: 'Shop', currency: 'BDT'),
      ),
      if (repo != null) transactionRepositoryProvider.overrideWithValue(repo),
      // Checkout now runs the expiry gate (and a reconcile after a sale);
      // neither has a backend in tests.
      expiryGateProvider.overrideWithValue(gate),
      expiryReconcilerProvider.overrideWithValue(NoopReconciler()),
    ],
  );
  addTearDown(container.dispose);
  await container.read(myShopProvider.future);
  return container;
}

Widget cartApp(ProviderContainer container, Widget home) =>
    UncontrolledProviderScope(
      container: container,
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
        home: home,
      ),
    );

/// Records what checkout sent. `TransactionRepository` is a concrete class, so
/// this implements its five public methods explicitly -- there is no mock
/// framework in this project.
class CapturingTransactionRepository implements TransactionRepository {
  double? sentDiscount;
  String? sentCustomerId;
  bool? sentDigital;
  List<Map<String, dynamic>>? sentItems;
  final sentGroupIds = <String>[];
  int calls = 0;

  @override
  Future<Result<List<Transaction>>> recordSaleCart({
    required String shopId,
    required List<Map<String, dynamic>> items,
    required String saleGroupId,
    String source = 'manual',
    String? customerId,
    double discount = 0,
    bool digital = false,
  }) async {
    calls++;
    sentItems = items;
    sentGroupIds.add(saleGroupId);
    sentDiscount = discount;
    sentCustomerId = customerId;
    sentDigital = digital;
    return const Result.success(<Transaction>[]);
  }

  @override
  Future<Result<Transaction>> recordRestock({
    required String shopId,
    required String productId,
    required double quantity,
    required String restockId,
    String source = 'manual',
    DateTime? expiryDate,
    DateTime? receivedOn,
  }) async => throw UnimplementedError();

  @override
  Future<Result<List<Transaction>>> recentSales({
    required String shopId,
    int limit = 100,
    DateTime? since,
  }) async => const Result.success(<Transaction>[]);

  @override
  Future<Result<List<Transaction>>> salesForDay({
    required String shopId,
    required DateTime day,
  }) async => const Result.success(<Transaction>[]);

  @override
  Future<Result<DateTime?>> earliestSaleDate({required String shopId}) async =>
      const Result.success(null);
}
