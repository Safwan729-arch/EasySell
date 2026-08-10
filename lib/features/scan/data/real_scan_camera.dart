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
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw const CameraPermissionDenied();
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
      await controller.initialize();
      _controller = controller;
    } on CameraException catch (e) {
      // The plugin reports a refusal as an access-denied code rather than a
      // typed error; anything else is a real device fault worth rethrowing.
      if (e.code == 'CameraAccessDenied' ||
          e.code == 'CameraAccessDeniedWithoutPrompt' ||
          e.code == 'CameraAccessRestricted') {
        throw const CameraPermissionDenied();
      }
      rethrow;
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
