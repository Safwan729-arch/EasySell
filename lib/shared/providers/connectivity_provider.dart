import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Pure mapping from the plugin's connectivity results to an online boolean.
///
/// `connectivity_plus` (v6+) reports a *list* of active interfaces. We treat the
/// device as **offline** only when there is no usable interface — an empty list
/// or a list whose sole entry is [ConnectivityResult.none]. Any other interface
/// (wifi, mobile, ethernet, vpn, …) counts as online. This reflects interface
/// state, not real internet reachability — see the design's Known limitation.
bool isOnlineFromResults(List<ConnectivityResult> results) {
  final usable = results.where((r) => r != ConnectivityResult.none);
  return usable.isNotEmpty;
}

/// Emits `true` while the device has a usable network interface, `false` when it
/// has none. Seeds from an initial `checkConnectivity()` reading, then follows
/// `onConnectivityChanged`. Fails **open** (online) while loading or on error so
/// the offline banner never shows spuriously before the first real reading.
final isOnlineProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  yield isOnlineFromResults(await connectivity.checkConnectivity());
  yield* connectivity.onConnectivityChanged.map(isOnlineFromResults);
});
