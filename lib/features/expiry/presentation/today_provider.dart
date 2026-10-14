import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/expiry_dates.dart';

/// The current instant. A provider so tests can pin it; production reads the
/// zone-scoped `clock`.
final nowProvider = Provider<DateTime Function()>((ref) => clock.now);

/// The phone's local calendar date. It must MOVE: an app left open overnight
/// would otherwise never mark anything expired (spec §4.2). Updated by a timer
/// at local midnight and whenever the app returns to the foreground.
class TodayController extends Notifier<DateTime> {
  Timer? _midnight;
  AppLifecycleListener? _lifecycle;

  @override
  DateTime build() {
    _lifecycle = AppLifecycleListener(onResume: refresh);
    ref.onDispose(() {
      _midnight?.cancel();
      _lifecycle?.dispose();
    });
    final now = ref.read(nowProvider)();
    _arm(now);
    return dateOnly(now);
  }

  void refresh() {
    final now = ref.read(nowProvider)();
    final today = dateOnly(now);
    if (today != state) state = today;
    _arm(now);
  }

  void _arm(DateTime now) {
    _midnight?.cancel();
    final next = DateTime(now.year, now.month, now.day + 1);
    _midnight = Timer(
      next.difference(now) + const Duration(seconds: 1),
      refresh,
    );
  }
}

final todayProvider = NotifierProvider<TodayController, DateTime>(
  TodayController.new,
);
