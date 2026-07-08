import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Seeded at startup in `main()` from SharedPreferences (overridden in the
/// ProviderScope). Holds the persisted "has seen onboarding" value.
final initialOnboardingSeenProvider = Provider<bool>(
  (ref) => throw UnimplementedError('overridden in main()'),
);

const _prefsKey = 'seen_onboarding';

/// Whether the user has completed the welcome/onboarding flow. The router watches
/// this; [markSeen] flips it and persists so onboarding shows only once.
class OnboardingSeen extends Notifier<bool> {
  @override
  bool build() => ref.watch(initialOnboardingSeenProvider);

  Future<void> markSeen() async {
    state = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, true);
  }
}

final onboardingSeenProvider = NotifierProvider<OnboardingSeen, bool>(
  OnboardingSeen.new,
);

/// Reads the persisted flag once, for seeding [initialOnboardingSeenProvider].
Future<bool> loadOnboardingSeen() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_prefsKey) ?? false;
}
