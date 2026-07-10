import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:ai_shopkeeper/shared/providers/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal harness: a screen that shows the localized settings title and flips
/// locale via the provider, proving the wiring end-to-end.
void main() {
  // setLocale persists via SharedPreferences; give it an in-memory store so
  // the plugin channel resolves under `flutter test` instead of hanging.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('changing localeProvider swaps the settings title language',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) {
            final locale = ref.watch(localeProvider);
            return MaterialApp(
              locale: locale,
              supportedLocales: supportedAppLocales,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: Builder(
                builder: (context) =>
                    Text(AppLocalizations.of(context).settings_title),
              ),
            );
          },
        ),
      ),
    );

    expect(find.text('Settings'), findsOneWidget);

    await container.read(localeProvider.notifier).setLocale(const Locale('bn'));
    await tester.pumpAndSettle();

    expect(find.text('সেটিংস'), findsOneWidget);
  });
}
