import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One stable [ScrollController] per bottom-nav branch (0 Home · 1 Items ·
/// 2 Reports · 3 History). The shell animates a branch's list back to the top
/// when its already-active tab is tapped again; each branch's primary list
/// attaches the matching controller via [branchScrollControllerProvider].
///
/// App-lifetime (not autoDispose) so scroll positions survive tab switches, and
/// Riverpod owns disposal — the screens stay free of controller lifecycle.
final branchScrollControllerProvider = Provider.family<ScrollController, int>((
  ref,
  branch,
) {
  final controller = ScrollController();
  ref.onDispose(controller.dispose);
  return controller;
});
