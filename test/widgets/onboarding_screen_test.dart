import 'package:ai_shopkeeper/features/auth/presentation/auth_controller.dart';
import 'package:ai_shopkeeper/features/onboarding/presentation/onboarding_screen.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:ai_shopkeeper/shared/providers/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Captures createShop args instead of hitting Supabase, and reports success so
/// the UI proceeds. The optional `currency` default mirrors the real controller.
class _RecordingAuthController extends AuthController {
  String? capturedName;
  String? capturedCurrency;

  @override
  Future<void> createShop({
    required String name,
    String? address,
    String? phone,
    String currency = 'BDT',
  }) async {
    capturedName = name;
    capturedCurrency = currency;
    state = const AsyncData(null);
  }
}

/// Mirrors app.dart: MaterialApp.locale is driven by localeProvider so a
/// setLocale() during the test actually re-localizes the tree.
class _TestApp extends ConsumerWidget {
  const _TestApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      home: const OnboardingScreen(),
    );
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('language step gates the shop step until a language is picked', (
    tester,
  ) async {
    late _RecordingAuthController rec;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(() {
            rec = _RecordingAuthController();
            return rec;
          }),
        ],
        child: const _TestApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Step 1 is showing; the shop form is not reachable yet.
    expect(find.text('Choose your language'), findsOneWidget);
    expect(find.text('Create shop'), findsNothing);

    // Continue is disabled until a card is tapped.
    final continueBtn = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Continue'),
    );
    expect(continueBtn.onPressed, isNull);
  });

  testWidgets('English → Continue → create shop with USD records USD', (
    tester,
  ) async {
    late _RecordingAuthController rec;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(() {
            rec = _RecordingAuthController();
            return rec;
          }),
        ],
        child: const _TestApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    // Step 2 is now visible.
    expect(find.text('Create shop'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Shop name *'),
      'Rahim Store',
    );
    await tester.tap(find.text('\$ USD'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create shop'));
    await tester.pumpAndSettle();

    expect(rec.capturedName, 'Rahim Store');
    expect(rec.capturedCurrency, 'USD');
  });

  testWidgets('tapping বাংলা switches the UI to Bengali live', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_RecordingAuthController.new),
        ],
        child: const _TestApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Choose your language'), findsOneWidget);
    await tester.tap(find.text('বাংলা'));
    await tester.pumpAndSettle();

    // The step-1 title is now Bengali.
    expect(find.text('আপনার ভাষা বেছে নিন'), findsOneWidget);
    expect(find.text('Choose your language'), findsNothing);
  });
}
