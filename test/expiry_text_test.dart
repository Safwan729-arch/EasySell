import 'package:ai_shopkeeper/features/expiry/domain/expiry_alerts.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/expiry_text.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

ExpiryAlert _a(Product p, ExpiryAlertKind kind, double qty, int daysLeft) =>
    ExpiryAlert(
      product: p,
      kind: kind,
      quantity: qty,
      expiryDate: DateTime(2026, 10, 20),
      daysLeft: daysLeft,
    );

void main() {
  const pepsi = Product(id: 'p', shopId: 's', name: 'Pepsi');
  const rice = Product(
    id: 'r',
    shopId: 's',
    name: 'Rice',
    unitType: UnitType.weight,
    unit: ProductUnit.kg,
  );
  final en = lookupAppLocalizations(const Locale('en'));

  test('expired, with the unit only for weight and volume', () {
    expect(
      expiryAlertText(en, _a(pepsi, ExpiryAlertKind.expired, 5, -1)),
      'Expired: 5 Pepsi',
    );
    expect(
      expiryAlertText(en, _a(rice, ExpiryAlertKind.expired, 2.5, -1)),
      'Expired: 2.5 kg Rice',
    );
  });

  test('expiring today, tomorrow and in N days', () {
    expect(
      expiryAlertText(en, _a(pepsi, ExpiryAlertKind.expiringSoon, 3, 0)),
      'Pepsi: 3 expire today',
    );
    expect(
      expiryAlertText(en, _a(pepsi, ExpiryAlertKind.expiringSoon, 3, 1)),
      'Pepsi: 3 expire tomorrow',
    );
    expect(
      expiryAlertText(en, _a(pepsi, ExpiryAlertKind.expiringSoon, 2, 4)),
      'Pepsi: 2 expire in 4 days',
    );
  });

  test('alert text is Bengali in bn', () {
    final previous = Intl.defaultLocale;
    Intl.defaultLocale = 'bn';
    addTearDown(() => Intl.defaultLocale = previous);
    final bn = lookupAppLocalizations(const Locale('bn'));
    expect(
      expiryAlertText(bn, _a(pepsi, ExpiryAlertKind.expired, 5, -1)),
      'মেয়াদোত্তীর্ণ: ৫ Pepsi',
    );
  });
}
