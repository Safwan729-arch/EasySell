import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Thrown when the user refuses camera access. Distinct from a generic failure
/// because the recovery is different: no amount of retrying helps, the user has
/// to change a system setting.
class CameraPermissionDenied implements Exception {
  const CameraPermissionDenied();
  @override
  String toString() => 'CameraPermissionDenied';
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
  /// Throws [CameraPermissionDenied] if the user refuses access.
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
    captureCount++;
    return Uint8List.fromList([captureCount, 0, 0, 0]);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    _ready = false;
  }
}

/// Overridden in tests with a [FakeScanCamera]; Task 4 supplies the real one.
final scanCameraProvider = Provider<ScanCamera>(
  (ref) => throw UnimplementedError('scanCameraProvider must be overridden'),
);
