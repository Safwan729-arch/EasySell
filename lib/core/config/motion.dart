import 'package:flutter/widgets.dart';

/// Centralized motion tokens for the app.
///
/// Philosophy (Emil Kowalski): UI animation should be fast and intentional.
/// Entrances and exits use strong ease-out curves so they feel responsive the
/// instant the user is watching; on-screen movement uses ease-in-out; exits are
/// shorter than entrances. Durations stay under ~300ms for anything the user
/// sees often. Built-in Flutter curves are a little weak, so we use the same
/// custom cubics the best web UIs ship with.
class AppMotion {
  const AppMotion._();

  // ---- Durations ---------------------------------------------------------
  /// Press feedback (scale-down on tap).
  static const Duration pressIn = Duration(milliseconds: 120);

  /// Small state changes: pills, chips, badges, nav selection.
  static const Duration fast = Duration(milliseconds: 180);

  /// Standard entrances: cards, list items, sheets reaching their place.
  static const Duration medium = Duration(milliseconds: 320);

  /// Exits — deliberately shorter than entrances so dismissals feel snappy.
  static const Duration exit = Duration(milliseconds: 200);

  /// Number count-ups and chart draws — long enough to read the motion.
  static const Duration count = Duration(milliseconds: 650);

  /// Page (route) transitions.
  static const Duration page = Duration(milliseconds: 300);

  /// Delay between staggered siblings. Kept short so a list never feels slow.
  static const Duration stagger = Duration(milliseconds: 45);

  // ---- Curves ------------------------------------------------------------
  /// Strong ease-out for entrances and feedback — instant, then settles.
  static const Cubic easeOut = Cubic(0.23, 1, 0.32, 1);

  /// Strong ease-in-out for elements moving/morphing on screen.
  static const Cubic easeInOut = Cubic(0.77, 0, 0.175, 1);

  /// iOS-like drawer/sheet curve (Ionic).
  static const Cubic drawer = Cubic(0.32, 0.72, 0, 1);

  /// Whether the OS has asked us to reduce motion. When true, callers should
  /// skip translate/scale movement and fall back to a crossfade or no motion.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;
}
