import 'package:ai_shopkeeper/features/restock/presentation/restock_prefs.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('defaults to 7 days', () async {
    expect(await loadRestockDays(), 7);
  });

  test('a change persists across a reload, clamped to 1–30', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(restockDaysProvider.notifier).set(3);
    expect(c.read(restockDaysProvider), 3);
    expect(await loadRestockDays(), 3);

    await c.read(restockDaysProvider.notifier).set(90);
    expect(c.read(restockDaysProvider), 30);
  });
}
