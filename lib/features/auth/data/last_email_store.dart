import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Remembers the last email a user signed in/up with, so the login screen can
/// pre-fill it and they only need to type their password next time.
///
/// This is a local convenience only — it stores the email address (not the
/// password) on-device via [SharedPreferences]. Cleared on explicit sign-out is
/// intentionally *not* done, so the email survives across sessions.
class LastEmailStore {
  static const _key = 'last_email';

  Future<void> save(String email) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, trimmed);
  }

  Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }
}

/// Provider exposing the [LastEmailStore].
final lastEmailStoreProvider = Provider<LastEmailStore>((ref) {
  return LastEmailStore();
});
