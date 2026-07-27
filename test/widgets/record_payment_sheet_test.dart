import 'package:ai_shopkeeper/features/customers/domain/customer_balance.dart';
import 'package:ai_shopkeeper/features/customers/presentation/record_payment_sheet.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _customer = CustomerBalance(
  id: 'c1',
  name: 'Rahim',
  phone: '01700000000',
  balance: 150,
);

Widget _host() => ProviderScope(
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showRecordPaymentSheet(context, customer: _customer),
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
}
