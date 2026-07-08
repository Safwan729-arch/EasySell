/// Supabase connection config, read from `--dart-define` at build/run time.
///
/// NEVER hardcode keys here or commit them. Pass them on the command line:
///
/// ```bash
/// flutter run \
///   --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=eyJhbGciOi...
/// ```
///
/// Only the **anon** key belongs on-device. The service-role key must live
/// exclusively inside Supabase Edge Functions, never in the app.
class SupabaseConfig {
  const SupabaseConfig._();

  static const String url = String.fromEnvironment('SUPABASE_URL');
  static const String anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// True when both defines were provided. `main()` checks this so the app
  /// fails fast with a clear message instead of a confusing SDK error.
  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}
