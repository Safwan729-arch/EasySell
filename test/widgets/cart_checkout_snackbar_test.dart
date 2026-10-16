import 'package:ai_shopkeeper/features/cart/presentation/cart_controller.dart';
import 'package:ai_shopkeeper/features/cart/presentation/cart_discount_controller.dart';
import 'package:ai_shopkeeper/features/cart/presentation/cart_screen.dart';
import 'package:ai_shopkeeper/shared/extensions/format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:ai_shopkeeper/core/config/theme.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:ai_shopkeeper/shared/providers/locale_provider.dart';

import '../support/cart_harness.dart';

String _m(num v) => Money.format(v, currencyCode: 'BDT');

/// CartScreen pops the route on a successful checkout, so this needs a real
/// router underneath it -- the plain `cartApp` harness would throw on
/// `context.pop()` before the snackbar was ever built.
Widget _routedCart(ProviderContainer container) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: TextButton(
            onPressed: () => context.push('/cart'),
            child: const Text('to cart'),
          ),
        ),
      ),
      GoRoute(path: '/cart', builder: (_, _) => const CartScreen()),
    ],
  );
  addTearDown(router.dispose);
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      theme: AppTheme.light,
      locale: const Locale('en'),
      supportedLocales: supportedAppLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
    ),
  );
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  // The bug this pins: the snackbar total was read as `cartTotal(lines)` --
  // gross -- so a 895 cart with 60 off announced 895 while the database
  // recorded 835. On credit the same figure names the debt just written to
  // customer_ledger, so it misstated what the customer owed at the moment the
  // debt was created.
  testWidgets('the success snackbar reports the DISCOUNTED total', (
    tester,
  ) async {
    final repo = CapturingTransactionRepository();
    final c = await cartContainer(repo: repo);
    c.read(cartControllerProvider.notifier).addOrIncrement(kOil, 1); // 850
    c.read(cartControllerProvider.notifier).addOrIncrement(kPepsi, 1); // 45
    c.read(cartDiscountControllerProvider.notifier).setAmount(60);

    await tester.pumpWidget(_routedCart(c));
    await tester.pumpAndSettle();
    await tester.tap(find.text('to cart'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Checkout'));
    await tester.pumpAndSettle();

    expect(repo.sentDiscount, 60);
    expect(find.text('2 items sold · ${_m(835)}'), findsOneWidget);
    expect(
      find.text('2 items sold · ${_m(895)}'),
      findsNothing,
      reason: 'the gross bill is not what was charged',
    );
  });

  testWidgets('choosing Digital at checkout sends the sale as digital', (
    tester,
  ) async {
    final repo = CapturingTransactionRepository();
    final c = await cartContainer(repo: repo);
    c.read(cartControllerProvider.notifier).addOrIncrement(kOil, 1);

    await tester.pumpWidget(_routedCart(c));
    await tester.pumpAndSettle();
    await tester.tap(find.text('to cart'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Digital'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Checkout'));
    await tester.pumpAndSettle();

    expect(repo.sentDigital, isTrue);
    expect(repo.sentCustomerId, isNull);
  });

  testWidgets('an undiscounted checkout still reports the full total', (
    tester,
  ) async {
    final repo = CapturingTransactionRepository();
    final c = await cartContainer(repo: repo);
    c.read(cartControllerProvider.notifier).addOrIncrement(kOil, 1); // 850

    await tester.pumpWidget(_routedCart(c));
    await tester.pumpAndSettle();
    await tester.tap(find.text('to cart'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Checkout'));
    await tester.pumpAndSettle();

    expect(find.text('1 item sold · ${_m(850)}'), findsOneWidget);
  });
}
