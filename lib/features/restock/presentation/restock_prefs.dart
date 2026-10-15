import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Presets for "I restock every N days" (spec §4.3: 1–30, default 7).
const restockDayChoices = [1, 2, 3, 5, 7, 10, 14, 30];

const _kRestockDays = 'restock_every_days';

/// Seeded in `main()` from SharedPreferences, like `initialExpiryPrefsProvider`.
final initialRestockDaysProvider = Provider<int>((ref) => 7);

class RestockDaysController extends Notifier<int> {
  @override
  int build() => ref.watch(initialRestockDaysProvider);

  Future<void> set(int days) async {
    state = days.clamp(1, 30);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kRestockDays, state);
  }
}

final restockDaysProvider = NotifierProvider<RestockDaysController, int>(
  RestockDaysController.new,
);

Future<int> loadRestockDays() async {
  final prefs = await SharedPreferences.getInstance();
  return (prefs.getInt(_kRestockDays) ?? 7).clamp(1, 30);
}
