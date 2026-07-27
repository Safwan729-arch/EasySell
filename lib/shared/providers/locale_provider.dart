import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The languages the app ships. English is the template/fallback.
const supportedAppLocales = [Locale('en'), Locale('bn')];

/// Seeded at startup in `main()` from SharedPreferences (overridden in the
/// ProviderScope), mirroring [initialThemeModeProvider]. Falls back to English
/// during a hot reload (which never re-runs `main()`); a hot restart picks up
/// the persisted value.
final initialLocaleProvider = Provider<Locale>((ref) => const Locale('en'));

const _prefsKey = 'locale';

/// The app's active [Locale]. `MaterialApp.router` watches this. [setLocale]
/// updates it, syncs `Intl.defaultLocale` (so number/date formatters localize),
/// and persists so the choice survives restarts.
class LocaleController extends Notifier<Locale> {
  @override
  Locale build() {
    final loc = ref.watch(initialLocaleProvider);
    Intl.defaultLocale = loc.languageCode;
    return loc;
  }

  Future<void> setLocale(Locale locale) async {
    state = locale;
    Intl.defaultLocale = locale.languageCode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, locale.languageCode);
  }
}

final localeProvider = NotifierProvider<LocaleController, Locale>(
  LocaleController.new,
);

/// Reads the persisted language once, for seeding [initialLocaleProvider].
/// First launch with no stored choice follows the device locale when it is
/// Bengali, otherwise English.
Future<Locale> loadLocale() async {
  final prefs = await SharedPreferences.getInstance();
  final code = prefs.getString(_prefsKey);
  if (code == 'bn') return const Locale('bn');
  if (code == 'en') return const Locale('en');
  final device = WidgetsBinding.instance.platformDispatcher.locale;
  return device.languageCode == 'bn' ? const Locale('bn') : const Locale('en');
}
