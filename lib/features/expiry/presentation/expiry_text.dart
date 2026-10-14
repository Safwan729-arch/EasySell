import '../../../l10n/app_localizations.dart';
import '../../../shared/extensions/format.dart';
import '../../inventory/domain/product.dart';
import '../domain/expiry_alerts.dart';

/// "5" for pieces, "2.5 kg" for weight/volume -- "5 pcs Pepsi" reads badly.
/// Digits follow `Intl.defaultLocale`, which the locale provider keeps in sync
/// with the app language, so Bengali shows ৫.
String alertQtyText(ExpiryAlert a) => a.product.unitType == UnitType.piece
    ? Qty.format(a.quantity)
    : '${Qty.format(a.quantity)} ${a.product.unitLabel}';

/// One alert as a sentence. Shared by the Home card, the alerts screen and
/// the daily reminder (which builds it with no BuildContext).
String expiryAlertText(AppLocalizations l10n, ExpiryAlert a) {
  final qty = alertQtyText(a);
  final name = a.product.name;
  if (a.kind == ExpiryAlertKind.expired)
    return l10n.expiry_alertExpired(qty, name);
  return switch (a.daysLeft) {
    <= 0 => l10n.expiry_alertSoonToday(name, qty),
    1 => l10n.expiry_alertSoonTomorrow(name, qty),
    final days => l10n.expiry_alertSoonDays(name, qty, Qty.format(days)),
  };
}
