import 'package:flutter/foundation.dart';

import '../../inventory/domain/product.dart';

/// Where one tray chip is in its life.
enum ScanItemStatus {
  /// Queued or in flight. The camera does not wait for this.
  recognizing,

  /// One product, confidently. Counts toward "Add N items".
  resolved,

  /// Several plausible products; the shopkeeper taps to pick.
  ambiguous,

  /// Recognized nothing in the catalog; tap to pick manually.
  unmatched,

  /// The call failed (offline, 502). The frame is held so retry needs no
  /// re-shoot.
  failed,
}

/// One chip in the review tray.
@immutable
class ScanItem {
  const ScanItem({
    required this.id,
    required this.status,
    this.product,
    this.choices = const <Product>[],
    this.readLabel,
    this.quantity = 0,
    this.frame,
  });

  /// Local, stable key. Never a product id -- two chips can hold the same
  /// product briefly, before the merge in [ScanSessionController] folds them.
  final String id;
  final ScanItemStatus status;
  final Product? product;
  final List<Product> choices;

  /// What the model reported reading off the packaging, e.g. "Pepsi · 1L".
  final String? readLabel;
  final double quantity;

  /// Held only while the chip may still need re-sending; dropped on success so
  /// a long session does not accumulate JPEGs.
  final Uint8List? frame;

  bool get isPending => status == ScanItemStatus.recognizing;
  bool get isAddable => status == ScanItemStatus.resolved && quantity > 0;

  ScanItem copyWith({
    ScanItemStatus? status,
    Product? product,
    List<Product>? choices,
    String? readLabel,
    double? quantity,
    bool clearFrame = false,
  }) => ScanItem(
    id: id,
    status: status ?? this.status,
    product: product ?? this.product,
    choices: choices ?? this.choices,
    readLabel: readLabel ?? this.readLabel,
    quantity: quantity ?? this.quantity,
    frame: clearFrame ? null : frame,
  );
}
