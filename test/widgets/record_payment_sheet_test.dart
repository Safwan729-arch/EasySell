import 'package:ai_shopkeeper/core/error/failure.dart';
import 'package:ai_shopkeeper/core/error/result.dart';
import 'package:ai_shopkeeper/features/auth/data/auth_repository.dart';
import 'package:ai_shopkeeper/features/auth/domain/shop.dart';
import 'package:ai_shopkeeper/features/customers/data/customer_repository.dart';
import 'package:ai_shopkeeper/features/customers/domain/customer_balance.dart';
import 'package:ai_shopkeeper/features/customers/domain/ledger_entry.dart';
import 'package:ai_shopkeeper/features/customers/presentation/record_payment_sheet.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

const _customer = CustomerBalance(
  id: 'c1',
  name: 'Rahim',
  phone: '01700000000',
  balance: 150,
);

/// Fails every payment (as a lost reply would) and records the id sent.
class _FailingRepo implements CustomerRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  final paymentIds = <String>[];

  @override
  Future<Result<List<LedgerEntry>>> ledgerFor(String customerId) async =>
      const Result.success(<LedgerEntry>[]);

  @override
  Future<Result<LedgerEntry>> recordPayment({
    required String shopId,
    required String customerId,
    required double amount,
    required String paymentId,
    String? note,
  }) async {
    paymentIds.add(paymentId);
    return const Result.failure(
      NetworkFailure('No internet connection. Please try again.'),
    );
  }
}

Widget _host({List<Override> overrides = const []}) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () =>
                showRecordPaymentSheet(context, customer: _customer),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('rejects a payment larger than the balance', (tester) async {
    await tester.pumpWidget(_host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Enter 500 against a 150 balance.
    await tester.enterText(find.byType(TextFormField).first, '500');
    // Tap the record button (the sheet's primary action).
    await tester.tap(find.byType(FilledButton).last);
    await tester.pumpAndSettle();

    // The over-balance validation message shows; the sheet stays open.
    expect(find.text('More than what is owed'), findsOneWidget);
  });

  group('a failed payment', () {
    late _FailingRepo repo;

    Future<void> openAndPay(WidgetTester tester, String amount) async {
      await tester.enterText(find.byType(TextFormField).first, amount);
      await tester.tap(find.byType(FilledButton).last);
      await tester.pumpAndSettle();
    }

    Future<void> open(WidgetTester tester) async {
      repo = _FailingRepo();
      await tester.pumpWidget(
        _host(
          overrides: [
            customerRepositoryProvider.overrideWithValue(repo),
            myShopProvider.overrideWith(
              (ref) => const Shop(
                id: 's',
                ownerId: 'o',
                name: 'Test Shop',
                currency: 'USD',
              ),
            ),
          ],
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows its error inside the sheet, which stays open', (
      tester,
    ) async {
      await open(tester);
      await openAndPay(tester, '50');

      expect(
        find.text('No internet connection. Please try again.'),
        findsOneWidget,
      );
      expect(find.byType(TextFormField), findsNWidgets(2));
    });

    testWidgets('retried unchanged, re-sends the same payment id', (
      tester,
    ) async {
      await open(tester);
      await openAndPay(tester, '50');
      await tester.tap(find.byType(FilledButton).last);
      await tester.pumpAndSettle();

      expect(repo.paymentIds, hasLength(2));
      expect(repo.paymentIds[1], repo.paymentIds[0]);
    });

    testWidgets('retried with a new amount, sends a new payment id', (
      tester,
    ) async {
      await open(tester);
      await openAndPay(tester, '50');
      await openAndPay(tester, '60');

      expect(repo.paymentIds, hasLength(2));
      expect(repo.paymentIds[1], isNot(repo.paymentIds[0]));
    });
  });
}
