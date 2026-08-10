import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'scan_camera.dart';

/// The `camera` package behind the [ScanCamera] seam.
///
/// Resolution is deliberately [ResolutionPreset.medium] (640x480). The old
/// `image_picker` path shot at maxWidth 768 / quality 60 because a smaller
/// payload noticeably cut scan latency on slow shop connections, and `medium`
/// is the closest preset. This is the one number in the feature NOT backed by
/// evidence: if small print on packaging reads worse than it used to, move to
/// [ResolutionPreset.high] (1280x720) and accept the larger upload.
class RealScanCamera implements ScanCamera {
  CameraController? _controller;

  @override
  Future<void> initialize() async {
    // scanCameraProvider is a plain (non-autoDispose) Provider, so one
    // RealScanCamera outlives every app-lifecycle pause/resume and
    // initialize() can land again without a preceding dispose(). Retiring
    // whatever controller is already here first (a no-op the first time)
    // stops that path from silently abandoning a controller that still
    // holds a live device-orientation subscription and bound platform
    // camera resources -- the frozen/black preview after backgrounding.
    await _disposeQuietly(_controller);
    _controller = null;

    final cameras = await availableCameras();
    if (cameras.isEmpty) throw const CameraUnavailable();
    final back = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    final controller = CameraController(
      back,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    try {
      await controller.initialize();
    } on CameraException catch (e) {
      // A failure here can land after the plugin has already bound the
      // camera to the process lifecycle (ProcessCameraProvider.bindToLifecycle
      // in android_camera_camerax.dart, called from initializeCamera before
      // this can throw), so the controller may be holding live hardware and
      // an active stream subscription. Dispose it before mapping/rethrowing
      // so nothing is ever abandoned. A pure permission refusal throws
      // earlier, in createCameraWithSettings, before anything is bound --
      // disposing here is a no-op for that case, not a workaround for it.
      await _disposeQuietly(controller);
      // The plugin reports a refusal as an access-denied code rather than a
      // typed error; anything else is a real device fault worth rethrowing.
      if (e.code == 'CameraAccessDenied' ||
          e.code == 'CameraAccessDeniedWithoutPrompt' ||
          e.code == 'CameraAccessRestricted') {
        throw const CameraPermissionDenied();
      }
      rethrow;
    }
    _controller = controller;
  }

  /// Best-effort disposal used during cleanup paths where we are already
  /// mid-error-handling or replacing a controller nobody asked to keep: a
  /// dispose() that itself throws must never mask the reason we were
  /// disposing in the first place, and must never block bringing up the
  /// controller that follows it.
  static Future<void> _disposeQuietly(CameraController? controller) async {
    if (controller == null) return;
    try {
      await controller.dispose();
    } catch (_) {
      // Swallowed deliberately -- see doc comment above.
    }
  }

  @override
  Widget buildPreview(BuildContext context) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }
    return CameraPreview(c);
  }

  @override
  Future<Uint8List> capture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      throw StateError('capture() before initialize()');
    }
    final shot = await c.takePicture();
    return shot.readAsBytes();
  }

  @override
  Future<void> dispose() async {
    final c = _controller;
    _controller = null;
    await c?.dispose();
  }
}
