import 'package:ai_shopkeeper/features/expiry/presentation/today_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('today is the local date and moves on refresh after midnight', () {
    var now = DateTime(2026, 10, 20, 23, 59);
    final c = ProviderContainer(
      overrides: [nowProvider.overrideWithValue(() => now)],
    );
    addTearDown(c.dispose);

    expect(c.read(todayProvider), DateTime(2026, 10, 20));

    now = DateTime(2026, 10, 21, 0, 0, 5);
    c.read(todayProvider.notifier).refresh();
    expect(c.read(todayProvider), DateTime(2026, 10, 21));
  });
}
