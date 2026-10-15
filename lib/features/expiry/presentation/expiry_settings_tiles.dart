import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../core/widgets/section_bits.dart';
import '../../../shared/extensions/format.dart';
import '../data/reminder_service.dart';
import 'expiry_prefs.dart';

/// Whether the phone lets the app post notifications. Re-read each time the
/// Settings screen opens (autoDispose).
final reminderPermissionProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(reminderServiceProvider).notificationsEnabled(),
);

class ExpiryWarnDaysTile extends ConsumerWidget {
  const ExpiryWarnDaysTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final days = ref.watch(expiryPrefsProvider.select((p) => p.warnDays));
    return ListTile(
      leading: const SettingsIconTile(Icons.event_note_outlined),
      title: Text(l10n.settings_expiryWarnDays(Qty.format(days))),
      onTap: () async {
        final picked = await showDialog<int>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: Text(l10n.settings_expiryWarnDaysTitle),
            children: [
              for (final d in ExpiryPrefs.warnDayChoices)
                SimpleDialogOption(
                  onPressed: () => Navigator.of(ctx).pop(d),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.settings_expiryDaysOption(Qty.format(d)),
                        ),
                      ),
                      if (d == days) const Icon(Icons.check, size: 18),
                    ],
                  ),
                ),
            ],
          ),
        );
        if (picked != null) {
          await ref.read(expiryPrefsProvider.notifier).setWarnDays(picked);
        }
      },
    );
  }
}

class ExpiryReminderTile extends ConsumerWidget {
  const ExpiryReminderTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final on = ref.watch(expiryPrefsProvider.select((p) => p.remindersOn));
    final allowed = ref.watch(reminderPermissionProvider).value ?? true;
    return SwitchListTile(
      secondary: const SettingsIconTile(Icons.notifications_active_outlined),
      title: Text(l10n.settings_expiryReminder),
      subtitle: Text(
        on && !allowed
            ? l10n.settings_expiryReminderBlocked
            : l10n.settings_expiryReminderSub,
      ),
      value: on,
      onChanged: (v) =>
          ref.read(expiryPrefsProvider.notifier).setRemindersOn(v),
    );
  }
}
