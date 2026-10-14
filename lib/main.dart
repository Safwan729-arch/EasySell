import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/supabase_config.dart';
import 'features/expiry/presentation/expiry_prefs.dart';
import 'shared/providers/locale_provider.dart';
import 'shared/providers/onboarding_provider.dart';
import 'shared/providers/theme_mode_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Draw behind the status and navigation bars; the per-theme overlay style
  // (icon contrast) is set in App's builder so it tracks light/dark.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  if (!SupabaseConfig.isConfigured) {
    // Fail fast with a clear message instead of an opaque SDK error.
    runApp(const _MissingConfigApp());
    return;
  }

  await Supabase.initialize(
    url: SupabaseConfig.url,
    // `publishableKey` is the current name for the public/anon key. We keep the
    // SUPABASE_ANON_KEY define name (per CLAUDE.md) and feed it here.
    publishableKey: SupabaseConfig.anonKey,
  );

  final seenOnboarding = await loadOnboardingSeen();
  final themeMode = await loadThemeMode();
  await initializeDateFormatting();
  final locale = await loadLocale();
  final expiryPrefs = await loadExpiryPrefs();

  runApp(
    ProviderScope(
      overrides: [
        initialOnboardingSeenProvider.overrideWithValue(seenOnboarding),
        initialThemeModeProvider.overrideWithValue(themeMode),
        initialLocaleProvider.overrideWithValue(locale),
        initialExpiryPrefsProvider.overrideWithValue(expiryPrefs),
      ],
      child: const App(),
    ),
  );
}

/// Shown when the app is launched without the required `--dart-define` secrets.
class _MissingConfigApp extends StatelessWidget {
  const _MissingConfigApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text(
              'Missing Supabase configuration.\n\n'
              'Run with:\n'
              '--dart-define=SUPABASE_URL=...\n'
              '--dart-define=SUPABASE_ANON_KEY=...',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
