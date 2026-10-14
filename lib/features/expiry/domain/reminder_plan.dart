import '../../inventory/domain/product.dart';
import 'expiry_alerts.dart';
import 'expiry_dates.dart';
import 'expiry_estimate.dart';
import 'product_batch.dart';

/// Notification ids 4100..4106: one slot per day ahead, so rescheduling
/// cancels exactly our reminders and nothing else the app may show.
const reminderBaseId = 4100;
const reminderSlots = 7;

class PlannedReminder {
  const PlannedReminder({
    required this.id,
    required this.at,
    required this.alerts,
  });

  final int id;
  final DateTime at;
  final List<ExpiryAlert> alerts;
}

/// The next [days] daily reminders at [hour]:00 local (spec §6). Each day's
/// alerts come from the estimate run with that day as "today", assuming no
/// further sales. Days with nothing to say get no reminder; a slot whose time
/// has already passed is skipped.
List<PlannedReminder> planReminders({
  required DateTime now,
  required List<Product> products,
  required List<ProductBatch> openBatches,
  required int shopWarnDays,
  int days = reminderSlots,
  int hour = 9,
}) {
  final today = dateOnly(now);
  final out = <PlannedReminder>[];
  for (var i = 0; i < days; i++) {
    final day = DateTime(today.year, today.month, today.day + i);
    final at = DateTime(day.year, day.month, day.day, hour);
    if (!at.isAfter(now)) continue;
    final alerts = buildExpiryAlerts(
      products: products,
      byProduct: estimateAll(
        products: products,
        openBatches: openBatches,
        today: day,
        shopWarnDays: shopWarnDays,
      ),
      today: day,
    );
    if (alerts.isNotEmpty) {
      out.add(PlannedReminder(id: reminderBaseId + i, at: at, alerts: alerts));
    }
  }
  return out;
}

/// "a, b +2 more" -- a notification shows little, so list [max] then count.
String reminderBody(
  List<String> lines,
  String Function(int more) moreText, {
  int max = 2,
}) {
  if (lines.length <= max) return lines.join(', ');
  return '${lines.take(max).join(', ')} ${moreText(lines.length - max)}';
}
