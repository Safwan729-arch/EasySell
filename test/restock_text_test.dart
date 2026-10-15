import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/restock/domain/restock_plan.dart';
import 'package:ai_shopkeeper/features/restock/presentation/restock_text.dart';
import 'package:ai_shopkeeper/l10n/app_localizations_bn.dart';
import 'package:ai_shopkeeper/l10n/app_localizations_en.dart';
import 'package:flutter_test/flutter_test.dart';

RestockItem _at(double daysLeft) => RestockItem(
  product: const Product(id: 'a', shopId: 's', name: 'A'),
  speed: 1,
  goodStock: daysLeft,
  daysLeft: daysLeft,
  suggestion: 5,
  trend: RestockTrend.flat,
);

/// Final review 2026-10-15: English read "Runs out in 1 days", "1 days",
/// "I restock every 1 days" (1 is a preset) and "1 items to restock".
void main() {
  final en = AppLocalizationsEn();
  final bn = AppLocalizationsBn();

  test('English says 1 day, not 1 days', () {
    expect(runsOutText(en, _at(1.4)), 'Runs out in 1 day');
    expect(runsOutText(en, _at(3)), 'Runs out in 3 days');
    expect(daysLeftShort(en, _at(1)), '1 day');
    expect(daysLeftShort(en, _at(4.9)), '4 days');
    expect(en.settings_restockEvery(1), 'I restock every day');
    expect(en.settings_restockEvery(7), 'I restock every 7 days');
    expect(en.restockPlan_cardSummary(1), '1 item to restock');
    expect(en.restockPlan_cardSummary(3), '3 items to restock');
  });

  test('no sales speed, below the reorder level: says so', () {
    final item = RestockItem(
      product: const Product(id: 'a', shopId: 's', name: 'A'),
      speed: 0,
      goodStock: 3,
      daysLeft: double.infinity,
      suggestion: 3,
      trend: RestockTrend.flat,
      belowReorder: true,
    );
    expect(runsOutText(en, item), 'At your reorder level');
    expect(daysLeftShort(en, item), 'low stock');
    expect(runsOutText(bn, item), isNot(contains('Infinity')));
  });

  test('Bengali keeps Bengali digits', () {
    expect(runsOutText(bn, _at(3)), '৩ দিনে শেষ হবে');
    expect(bn.restockPlan_cardSummary(3), '৩টি পণ্য রিস্টক করতে হবে');
  });
}
