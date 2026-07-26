import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../inventory/domain/product.dart';
import '../../inventory/presentation/inventory_controller.dart';
import '../data/vision_scan_repository.dart';
import '../domain/scan_candidates.dart';
import '../domain/scan_decision.dart';

/// The resolved outcome the scan screen renders: an action plus the concrete
/// products it maps to (already resolved from match ids to Product objects).
class ScanOutcome {
  const ScanOutcome({required this.action, required this.products});
  final ScanAction action;
  final List<Product> products;
}

/// Captures a photo, recognizes it against the shop's catalog, and resolves the
/// decision into concrete products. Returns null if the user cancels capture.
class ScanController {
  ScanController(this._ref);

  final Ref _ref;
  final ImagePicker _picker = ImagePicker();

  Future<ScanOutcome?> captureAndRecognize() async {
    // MEMBER C: camera capture. image_picker is the stub seam.
    // Smaller/lighter capture = faster upload with no real hit to label
    // reading — the product name/size stays legible at 768px, and the smaller
    // payload noticeably cuts scan latency on slow shop connections.
    final XFile? shot = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 768,
      imageQuality: 60,
    );
    if (shot == null) return null;
    final Uint8List bytes = await shot.readAsBytes();

    final products =
        _ref.read(productsStreamProvider).value ?? const <Product>[];
    final result = await _ref
        .read(visionScanRepositoryProvider)
        .recognize(imageBytes: bytes, candidates: buildCandidates(products));

    return result.when(
      success: (recognition) {
        final decision = decideScanAction(recognition);
        final byId = {for (final p in products) p.id: p};
        final resolved = [
          for (final m in decision.matches)
            if (byId[m.productId] != null) byId[m.productId]!,
        ];
        return ScanOutcome(action: decision.action, products: resolved);
      },
      failure: (f) => throw f,
    );
  }
}

final scanControllerProvider = Provider<ScanController>((ref) => ScanController(ref));
