import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'real_scan_camera.dart';

/// Thrown when the user refuses camera access. Distinct from a generic failure
/// because the recovery is different: no amount of retrying helps, the user has
/// to change a system setting.
class CameraPermissionDenied implements Exception {
  const CameraPermissionDenied();
  @override
  String toString() => 'CameraPermissionDenied';
}

/// Thrown when the device has no camera hardware at all. Distinct from
/// [CameraPermissionDenied]: `availableCameras()` enumerates hardware without
/// requiring the runtime CAMERA permission, so an empty list means "nothing to
/// bind to", not "access refused". Telling the user to go change a permission
/// setting would be wrong advice on a device -- an emulator, most often --
/// that simply has no camera.
class CameraUnavailable implements Exception {
  const CameraUnavailable();
  @override
  String toString() => 'CameraUnavailable';
}

/// The scan session's view of a camera.
///
/// Deliberately narrow, and deliberately includes [buildPreview] even though
/// that mixes a widget into a `data/` type: a real camera preview is a platform
/// texture only the plugin can construct. Paying that small layering cost buys
/// a fake, and the fake is what makes the session controller, the merge rules
/// and the whole tray testable -- none of which a real camera permits inside
/// `flutter test`.
abstract interface class ScanCamera {
  /// Throws [CameraPermissionDenied] if the user refuses access, or
  /// [CameraUnavailable] if the device has no camera hardware.
  Future<void> initialize();

  Widget buildPreview(BuildContext context);

  /// JPEG bytes of the current frame. Throws [StateError] before [initialize].
  Future<Uint8List> capture();

  Future<void> dispose();
}

/// In-memory camera for tests. Each [capture] returns different bytes so a test
/// can assert which frame a chip is holding.
class FakeScanCamera implements ScanCamera {
  FakeScanCamera({this.permissionGranted = true});

  final bool permissionGranted;
  bool _ready = false;
  int captureCount = 0;
  bool disposed = false;

  /// When true, the next [capture] throws instead of returning bytes, then
  /// resets itself back to false -- for exercising "the camera throws
  /// mid-capture" paths (a rapid double tap hitting the real plugin's
  /// "Previous capture has not returned yet.", or any other transient
  /// hardware fault) without needing a bespoke fake per test.
  bool failNextCapture = false;

  /// When set, [capture] awaits this before resolving, instead of returning
  /// on the next microtask like it normally does. Real captures take ~300ms;
  /// this fake is otherwise instant, which is too fast for a widget test to
  /// ever observe a second tap landing while the first is still in flight.
  /// Gate it to make that window test-controllable.
  Completer<void>? captureGate;

  @override
  Future<void> initialize() async {
    if (!permissionGranted) throw const CameraPermissionDenied();
    _ready = true;
  }

  @override
  Widget buildPreview(BuildContext context) =>
      const ColoredBox(color: Color(0xFF202020));

  @override
  Future<Uint8List> capture() async {
    if (!_ready) throw StateError('capture() before initialize()');
    if (failNextCapture) {
      failNextCapture = false;
      throw StateError('capture failed');
    }
    if (captureGate != null) await captureGate!.future;
    captureCount++;
    return Uint8List.fromList([captureCount, 0, 0, 0]);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    _ready = false;
  }
}

/// Overridden with a [FakeScanCamera] in tests.
final scanCameraProvider = Provider<ScanCamera>((ref) => RealScanCamera());
