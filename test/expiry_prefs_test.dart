import 'package:ai_shopkeeper/features/expiry/presentation/expiry_prefs.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('defaults: 7 days, reminders on, permission not asked', () async {
    final p = await loadExpiryPrefs();
    expect(p.warnDays, 7);
    expect(p.remindersOn, isTrue);
    expect(p.permissionAsked, isFalse);
  });

  test('changes persist across a reload', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(expiryPrefsProvider.notifier);
    await n.setWarnDays(14);
    await n.setRemindersOn(false);
    await n.markPermissionAsked();
    expect(c.read(expiryPrefsProvider).warnDays, 14);

    final reloaded = await loadExpiryPrefs();
    expect(reloaded.warnDays, 14);
    expect(reloaded.remindersOn, isFalse);
    expect(reloaded.permissionAsked, isTrue);
  });
}
