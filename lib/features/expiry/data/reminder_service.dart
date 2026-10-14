import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../domain/reminder_plan.dart';

class ScheduledReminder {
  const ScheduledReminder({
    required this.id,
    required this.at,
    required this.title,
    required this.body,
  });

  final int id;

  /// Local wall-clock time.
  final DateTime at;
  final String title;
  final String body;
}

/// The phone-side reminder seam (spec §6). // MEMBER C: phone notifications
/// are Member C's area (CLAUDE.md §1/§7); the user chose to build this one
/// here (2026-10-14). Their wider notification work can replace
/// [LocalReminderService] behind this interface.
abstract class ReminderService {
  /// Cancels our reminder slots, then schedules [reminders].
  Future<void> replaceAll(
    List<ScheduledReminder> reminders, {
    required String channelName,
  });
  Future<void> cancelAll();
  Future<bool> requestPermission();
  Future<bool> notificationsEnabled();

  /// Fires when the shopkeeper taps a reminder while the app is running.
  Stream<void> get taps;

  /// True once if the app was launched by tapping a reminder.
  bool consumeLaunchTap();
}

/// Used when the plugin is unavailable (tests, or a failed init).
class NoopReminderService implements ReminderService {
  const NoopReminderService();

  @override
  Future<void> replaceAll(
    List<ScheduledReminder> reminders, {
    required String channelName,
  }) async {}

  @override
  Future<void> cancelAll() async {}

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<bool> notificationsEnabled() async => true;

  @override
  Stream<void> get taps => const Stream.empty();

  @override
  bool consumeLaunchTap() => false;
}

class LocalReminderService implements ReminderService {
  final _plugin = FlutterLocalNotificationsPlugin();
  final _taps = StreamController<void>.broadcast();
  bool _launchedFromTap = false;

  Future<void> init() async {
    tz_data.initializeTimeZones();
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (_) => _taps.add(null),
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    _launchedFromTap = launch?.didNotificationLaunchApp ?? false;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  @override
  Future<void> replaceAll(
    List<ScheduledReminder> reminders, {
    required String channelName,
  }) async {
    await cancelAll();
    for (final r in reminders) {
      await _plugin.zonedSchedule(
        r.id,
        r.title,
        r.body,
        // The alarm fires at an INSTANT, so expressing the local 9 AM as the
        // same instant in UTC is exact and needs no device time-zone lookup.
        // Rescheduling on every app open absorbs any clock-zone change.
        tz.TZDateTime.from(r.at, tz.UTC),
        NotificationDetails(
          android: AndroidNotificationDetails(
            'expiry_reminders',
            channelName,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            styleInformation: BigTextStyleInformation(r.body),
          ),
        ),
        // Inexact: may arrive minutes late, but needs no exact-alarm
        // permission. Android 14 no longer grants SCHEDULE_EXACT_ALARM by
        // default and a missing one can throw from the plugin.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  @override
  Future<void> cancelAll() async {
    for (var i = 0; i < reminderSlots; i++) {
      await _plugin.cancel(reminderBaseId + i);
    }
  }

  @override
  Future<bool> requestPermission() async =>
      await _android?.requestNotificationsPermission() ?? false;

  @override
  Future<bool> notificationsEnabled() async =>
      await _android?.areNotificationsEnabled() ?? true;

  @override
  Stream<void> get taps => _taps.stream;

  @override
  bool consumeLaunchTap() {
    final v = _launchedFromTap;
    _launchedFromTap = false;
    return v;
  }
}

/// Overridden in `main()` with an initialised [LocalReminderService].
final reminderServiceProvider = Provider<ReminderService>(
  (ref) => const NoopReminderService(),
);
