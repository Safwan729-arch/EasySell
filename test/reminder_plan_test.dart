import 'package:ai_shopkeeper/features/expiry/domain/product_batch.dart';
import 'package:ai_shopkeeper/features/expiry/domain/reminder_plan.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const bread = Product(id: 'bread', shopId: 's1', name: 'Bread', quantity: 10);
  // Added Mon 13 Oct, expires Sat 18 Oct: warned from Fri 17, expired Sun 19.
  final loaf = ProductBatch(
    id: 'b',
    shopId: 's1',
    productId: 'bread',
    quantity: 10,
    receivedOn: DateTime(2026, 10, 13),
    expiryDate: DateTime(2026, 10, 18),
  );

  List<PlannedReminder> plan(DateTime now) => planReminders(
    now: now,
    products: [bread],
    openBatches: [loaf],
    shopWarnDays: 7,
  );

  test('only days with something to say get a 9 AM reminder', () {
    final p = plan(DateTime(2026, 10, 14, 8));
    expect(p.map((r) => r.at), [
      DateTime(2026, 10, 17, 9),
      DateTime(2026, 10, 18, 9),
      DateTime(2026, 10, 19, 9),
      DateTime(2026, 10, 20, 9),
    ]);
    expect(p.first.id, reminderBaseId + 3);
  });

  test('after 9 AM today is skipped', () {
    final p = plan(DateTime(2026, 10, 17, 10));
    expect(p.first.at, DateTime(2026, 10, 18, 9));
  });

  test('the body lists two items then "+N more"', () {
    String more(int n) => '+$n more';
    expect(reminderBody(['a', 'b'], more), 'a, b');
    expect(reminderBody(['a', 'b', 'c', 'd'], more), 'a, b +2 more');
  });
}
