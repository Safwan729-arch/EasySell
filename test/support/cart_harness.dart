import 'package:ai_shopkeeper/core/config/theme.dart';
import 'package:ai_shopkeeper/features/auth/data/auth_repository.dart';
import 'package:ai_shopkeeper/features/auth/domain/shop.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/transactions/data/transaction_repository.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:ai_shopkeeper/shared/providers/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
Future<ProviderContainer> cartContainer({TransactionRepository? repo}) async {
  final container = ProviderContainer(
    overrides: [
      myShopProvider.overrideWith(
        (ref) async =>
            const Shop(id: 's1', ownerId: 'o1', name: 'Shop', currency: 'BDT'),
      ),
      if (repo != null) transactionRepositoryProvider.overrideWithValue(repo),
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
