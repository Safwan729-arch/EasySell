import 'package:ai_shopkeeper/features/expiry/presentation/expiry_date_field.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/today_provider.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:ai_shopkeeper/shared/providers/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

Widget _app(Widget child) => ProviderScope(
  overrides: [nowProvider.overrideWithValue(() => DateTime(2026, 10, 14, 9))],
  child: MaterialApp(
    locale: const Locale('en'),
    supportedLocales: supportedAppLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: child),
  ),
);

void main() {
  setUpAll(() => initializeDateFormatting());

  testWidgets('an empty field says Optional', (tester) async {
    await tester.pumpWidget(
      _app(ExpiryDateField(value: null, onChanged: (_) {})),
    );
    expect(find.text('Expiry date'), findsOneWidget);
    expect(find.text('Optional'), findsOneWidget);
  });

  testWidgets('a set date shows and can be removed', (tester) async {
    DateTime? changed = DateTime(2000);
    await tester.pumpWidget(
      _app(
        ExpiryDateField(
          value: DateTime(2026, 10, 20),
          onChanged: (d) => changed = d,
        ),
      ),
    );
    expect(find.text('Oct 20, 2026'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove date'));
    expect(changed, isNull);
  });
}
