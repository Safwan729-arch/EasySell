import 'package:ai_shopkeeper/features/expiry/data/reminder_service.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/expiry_prefs.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/expiry_settings_tiles.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:ai_shopkeeper/shared/providers/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Blocked extends NoopReminderService {
  const _Blocked();
  @override
  Future<bool> notificationsEnabled() async => false;
}

Widget _app(ProviderContainer c) => UncontrolledProviderScope(
  container: c,
  child: MaterialApp(
    locale: const Locale('en'),
    supportedLocales: supportedAppLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: const Scaffold(
      body: Column(children: [ExpiryWarnDaysTile(), ExpiryReminderTile()]),
    ),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('choosing 14 days stores it', (tester) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await tester.pumpWidget(_app(c));

    expect(find.text('Warn me up to 7 days before'), findsOneWidget);
    await tester.tap(find.text('Warn me up to 7 days before'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('14 days'));
    await tester.pumpAndSettle();

    expect(c.read(expiryPrefsProvider).warnDays, 14);
    expect(find.text('Warn me up to 14 days before'), findsOneWidget);
  });

  testWidgets('blocked notifications say so', (tester) async {
    final c = ProviderContainer(
      overrides: [reminderServiceProvider.overrideWithValue(const _Blocked())],
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(_app(c));
    await tester.pumpAndSettle();
    expect(
      find.text('Blocked — turn on notifications in phone settings'),
      findsOneWidget,
    );
  });
}
