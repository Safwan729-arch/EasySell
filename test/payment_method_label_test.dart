import 'package:ai_shopkeeper/core/l10n/enum_labels.dart';
import 'package:ai_shopkeeper/features/transactions/domain/transaction.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:ai_shopkeeper/l10n/app_localizations_en.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final AppLocalizations l10n = AppLocalizationsEn();

  test('maps each payment method to its checkout word', () {
    expect(paymentMethodLabel(l10n, 'cash'), 'Cash');
    expect(paymentMethodLabel(l10n, 'digital'), 'Digital');
    expect(paymentMethodLabel(l10n, 'credit'), 'Credit');
  });

  test('sales from before 0018 have no label rather than a guess', () {
    expect(paymentMethodLabel(l10n, null), isNull);
    expect(paymentMethodLabel(l10n, 'something-else'), isNull);
  });

  test('the payment method is read from the row', () {
    final t = Transaction.fromJson({
      'id': 't1',
      'shop_id': 's1',
      'product_id': 'p1',
      'type': 'sale',
      'quantity': 1,
      'payment_method': 'digital',
    });
    expect(t.paymentMethod, 'digital');
  });
}
