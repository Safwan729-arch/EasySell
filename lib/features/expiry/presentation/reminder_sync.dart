import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router/app_router.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/providers/locale_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../../inventory/presentation/inventory_controller.dart';
import '../data/reminder_service.dart';
import '../domain/reminder_plan.dart';
import 'expiry_prefs.dart';
import 'expiry_providers.dart';
import 'expiry_text.dart';
import 'today_provider.dart';

/// Keeps the next 7 days of reminders in step with the data (spec §6).
/// Rebuilds -- and so reschedules -- on any stock or delivery change, a
/// settings change, a LANGUAGE change (the text is baked in when scheduled)
/// and a new day. Signed out or switched off: every reminder is cancelled, so
/// a shared phone never shows the previous account's stock.
final reminderSyncProvider = Provider<void>((ref) {
  final service = ref.watch(reminderServiceProvider);
  final shopAsync = ref.watch(myShopProvider);
  final prefs = ref.watch(expiryPrefsProvider);
  final locale = ref.watch(localeProvider);
  ref.watch(todayProvider);

  if (!prefs.remindersOn) {
    unawaited(service.cancelAll());
    return;
  }
  // The shop is fetched from the server: loading, or failed with no signal,
  // is NOT signed out. Keep what is scheduled -- cancelling here would
  // silence the reminders on exactly the days there is no internet (spec §1).
  if (!shopAsync.hasValue) return;
  final shop = shopAsync.value;
  if (shop == null) {
    unawaited(service.cancelAll());
    return;
  }

  final products = ref.watch(productsStreamProvider).value;
  final batches = ref.watch(batchesStreamProvider).value;
  // Still loading: keep whatever is already scheduled.
  if (products == null || batches == null) return;

  final l10n = lookupAppLocalizations(locale);
  final plan = planReminders(
    now: ref.read(nowProvider)(),
    products: products,
    openBatches: batches,
    shopWarnDays: prefs.warnDays,
  );
  unawaited(
    service.replaceAll([
      for (final p in plan)
        ScheduledReminder(
          id: p.id,
          at: p.at,
          title: l10n.reminder_title,
          body: reminderBody([
            for (final a in p.alerts) expiryAlertText(l10n, a),
          ], (more) => l10n.reminder_more(more.toString())),
        ),
    ], channelName: l10n.reminder_channelName),
  );
});

/// Opens the alerts screen when a reminder is tapped -- while running, or
/// once after a launch from a tap. Signed out, the router's guard sends the
/// shopkeeper to login first.
final reminderTapRouterProvider = Provider<void>((ref) {
  final service = ref.watch(reminderServiceProvider);
  final router = ref.watch(goRouterProvider);
  void open() => router.push(AppRoutes.alerts);

  final sub = service.taps.listen((_) => open());
  ref.onDispose(sub.cancel);
  if (service.consumeLaunchTap()) {
    WidgetsBinding.instance.addPostFrameCallback((_) => open());
  }
});
