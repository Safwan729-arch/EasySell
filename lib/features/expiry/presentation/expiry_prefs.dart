import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/reminder_service.dart';

/// Phone-local expiry settings (spec §5 Settings), stored like the theme.
class ExpiryPrefs {
  const ExpiryPrefs({
    this.warnDays = 7,
    this.remindersOn = true,
    this.permissionAsked = false,
  });

  /// The most days ahead the automatic warning may start (spec §4.3).
  final int warnDays;
  final bool remindersOn;

  /// Notification permission is requested once, the first time an expiry
  /// date is saved (spec §6).
  final bool permissionAsked;

  static const warnDayChoices = [3, 7, 14, 30];

  ExpiryPrefs copyWith({
    int? warnDays,
    bool? remindersOn,
    bool? permissionAsked,
  }) => ExpiryPrefs(
    warnDays: warnDays ?? this.warnDays,
    remindersOn: remindersOn ?? this.remindersOn,
    permissionAsked: permissionAsked ?? this.permissionAsked,
  );
}

const _kWarnDays = 'expiry_warn_days';
const _kRemindersOn = 'expiry_reminders_on';
const _kPermissionAsked = 'expiry_permission_asked';

/// Seeded in `main()` from SharedPreferences, like `initialThemeModeProvider`.
final initialExpiryPrefsProvider = Provider<ExpiryPrefs>(
  (ref) => const ExpiryPrefs(),
);

class ExpiryPrefsController extends Notifier<ExpiryPrefs> {
  @override
  ExpiryPrefs build() => ref.watch(initialExpiryPrefsProvider);

  Future<void> setWarnDays(int days) async {
    state = state.copyWith(warnDays: days);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kWarnDays, days);
  }

  Future<void> setRemindersOn(bool on) async {
    state = state.copyWith(remindersOn: on);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kRemindersOn, on);
  }

  Future<void> markPermissionAsked() async {
    state = state.copyWith(permissionAsked: true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPermissionAsked, true);
  }

  /// Requests notification permission the first time an expiry date is saved
  /// (spec §6). Marked asked BEFORE requesting so a crash cannot loop it. A
  /// failure here must never break the save that triggered it.
  Future<void> askPermissionOnce() async {
    if (state.permissionAsked) return;
    try {
      await markPermissionAsked();
      await ref.read(reminderServiceProvider).requestPermission();
    } catch (_) {}
  }
}

final expiryPrefsProvider =
    NotifierProvider<ExpiryPrefsController, ExpiryPrefs>(
      ExpiryPrefsController.new,
    );

Future<ExpiryPrefs> loadExpiryPrefs() async {
  final prefs = await SharedPreferences.getInstance();
  return ExpiryPrefs(
    warnDays: prefs.getInt(_kWarnDays) ?? 7,
    remindersOn: prefs.getBool(_kRemindersOn) ?? true,
    permissionAsked: prefs.getBool(_kPermissionAsked) ?? false,
  );
}
