import 'package:ai_shopkeeper/shared/providers/theme_mode_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('loadThemeMode', () {
    test('a fresh install opens in dark mode', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await loadThemeMode(), ThemeMode.dark);
    });

    test('an owner who picked light keeps light', () async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'light'});
      expect(await loadThemeMode(), ThemeMode.light);
    });

    test('an owner who picked dark keeps dark', () async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});
      expect(await loadThemeMode(), ThemeMode.dark);
    });

    test('a legacy "system" value opens in dark mode', () async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'system'});
      expect(await loadThemeMode(), ThemeMode.dark);
    });
  });

  test('without the startup override the provider defaults to dark', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(themeModeProvider), ThemeMode.dark);
  });
}
