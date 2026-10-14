import '../../inventory/domain/product.dart';
import 'expiry_dates.dart';
import 'expiry_estimate.dart';

enum ExpiryAlertKind { expired, expiringSoon }

/// One line on the Home card, the alerts screen and the daily reminder.
class ExpiryAlert {
  const ExpiryAlert({
    required this.product,
    required this.kind,
    required this.quantity,
    required this.expiryDate,
    required this.daysLeft,
  });

  final Product product;
  final ExpiryAlertKind kind;
  final double quantity;

  /// For an expired alert, the earliest expiry among the product's expired
  /// deliveries.
  final DateTime expiryDate;

  /// Days from today to [expiryDate]: 0 = today, 1 = tomorrow, negative once
  /// expired.
  final int daysLeft;
}

/// Expired units are summed into ONE alert per product ("Expired: 5 Pepsi");
/// each expiring-soon delivery gets its own. Expired first, then by date.
List<ExpiryAlert> buildExpiryAlerts({
  required List<Product> products,
  required Map<String, ProductExpiry> byProduct,
  required DateTime today,
}) {
  final alerts = <ExpiryAlert>[];
  for (final p in products) {
    final e = byProduct[p.id];
    if (e == null) continue;
    final expired = e.expiredWithStock.toList();
    if (expired.isNotEmpty) {
      final qty = expired.fold<double>(0, (s, b) => s + b.left);
      final earliest = expired
          .map((b) => b.batch.expiryDate)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      alerts.add(
        ExpiryAlert(
          product: p,
          kind: ExpiryAlertKind.expired,
          quantity: round3(qty),
          expiryDate: earliest,
          daysLeft: daysBetween(today, earliest),
        ),
      );
    }
    for (final b in e.expiringSoon) {
      alerts.add(
        ExpiryAlert(
          product: p,
          kind: ExpiryAlertKind.expiringSoon,
          quantity: b.left,
          expiryDate: b.batch.expiryDate,
          daysLeft: daysBetween(today, b.batch.expiryDate),
        ),
      );
    }
  }
  alerts.sort((a, b) {
    if (a.kind != b.kind) return a.kind == ExpiryAlertKind.expired ? -1 : 1;
    final c = a.expiryDate.compareTo(b.expiryDate);
    return c != 0 ? c : a.product.name.compareTo(b.product.name);
  });
  return alerts;
}
