import 'dart:typed_data';

import 'package:ai_shopkeeper/features/scan/data/scan_camera.dart';
import 'package:flutter_test/flutter_test.dart';

/// The fake is the whole reason the session logic is testable, so its own
/// contract is pinned: capture must hand back distinct, non-empty bytes so a
/// test can tell one frame from another.
void main() {
  test('capture yields distinct non-empty frames', () async {
    final cam = FakeScanCamera();
    await cam.initialize();
    final a = await cam.capture();
    final b = await cam.capture();
    expect(a, isA<Uint8List>());
    expect(a.isNotEmpty, isTrue);
    expect(a, isNot(equals(b)));
    expect(cam.captureCount, 2);
    await cam.dispose();
  });

  test('capture before initialize throws rather than returning junk', () {
    expect(FakeScanCamera().capture(), throwsStateError);
  });

  test('a denied camera surfaces CameraPermissionDenied', () {
    expect(
      FakeScanCamera(permissionGranted: false).initialize(),
      throwsA(isA<CameraPermissionDenied>()),
    );
  });
}
