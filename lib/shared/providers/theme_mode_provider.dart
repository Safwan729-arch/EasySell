import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Seeded at startup in `main()` from SharedPreferences (overridden in the
/// ProviderScope). Falls back to [ThemeMode.dark], the app's default look, when
/// no override is present — e.g. during a hot reload, which does not re-run
/// `main()` and so never applies the override. A hot *restart* picks up the
/// persisted value.
///
/// The app offers only Light and Dark (no System); [ThemeMode.system] is never
/// stored, and any legacy stored value is mapped to Dark on load.
final initialThemeModeProvider = Provider<ThemeMode>((ref) => ThemeMode.dark);

const _prefsKey = 'theme_mode';

/// The user's chosen [ThemeMode]. `MaterialApp.router` watches this; [setMode]
/// updates it and persists so the choice survives restarts. Defaults to
/// [ThemeMode.dark] until the user picks otherwise.
class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.watch(initialThemeModeProvider);

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

/// Reads the persisted preference once, for seeding [initialThemeModeProvider].
/// Only Light and Dark are supported; anything but an explicit Light choice
/// (unset, or a legacy `system` value) resolves to Dark. A user who already
/// picked Light keeps it.
Future<ThemeMode> loadThemeMode() async {
  final prefs = await SharedPreferences.getInstance();
  final name = prefs.getString(_prefsKey);
  return name == ThemeMode.light.name ? ThemeMode.light : ThemeMode.dark;
}
