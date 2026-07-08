import 'package:flutter/services.dart';

/// Centralized haptic feedback so the whole app speaks one tactile language and
/// can be muted from a single place.
///
/// Use the semantic methods ([tap], [success], [warning]) rather than calling
/// [HapticFeedback] directly — that keeps intent at the call site and lets a
/// future "Haptics" setting flip [enabled] without touching every screen.
///
/// On Android these use the platform's view-level haptic constants, so they
/// need no `VIBRATE` permission.
class AppHaptics {
  const AppHaptics._();

  /// Master switch. A Settings toggle can set this; defaults on.
  static bool enabled = true;

  /// Light tick for discrete selections: pressing a card/row, stepping a
  /// quantity, switching tabs. The most frequent, so the gentlest.
  static void tap() {
    if (enabled) HapticFeedback.selectionClick();
  }

  /// Confirming thud for a committed action that matters — a recorded sale or
  /// restock. Heavier than [tap] so it reads as "done".
  static void success() {
    if (enabled) HapticFeedback.mediumImpact();
  }

  /// Sharper bump for a rejected or destructive action (failed commit, delete).
  static void warning() {
    if (enabled) HapticFeedback.heavyImpact();
  }
}
