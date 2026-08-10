import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../cart/domain/cart_math.dart';
import '../../cart/presentation/cart_controller.dart';
import '../../inventory/domain/product.dart';
import '../../inventory/presentation/inventory_controller.dart';
import '../data/scan_camera.dart';
import '../data/vision_scan_repository.dart';
import '../domain/scan_candidates.dart';
import '../domain/scan_decision.dart';
import '../domain/scan_item.dart';

/// How many recognitions may be in flight at once.
///
/// A person cannot press a shutter much faster than once a second and each call
/// takes ~3s, so three-in-flight is roughly the natural steady state anyway:
/// higher buys no wall-clock improvement and invites rate-limit rejections,
/// lower re-serialises the very thing this session exists to parallelise.
const maxScanInFlight = 3;

/// The scan session: captures are instant, recognition happens behind them, and
/// nothing reaches the cart until [addAllToCart].
class ScanSessionController extends Notifier<List<ScanItem>> {
  @override
  List<ScanItem> build() => const <ScanItem>[];

  final _frames = <String, Uint8List>{};
  final _queue = <String>[];
  int _active = 0;
  int _seq = 0;

  int get pendingCount => state.where((i) => i.isPending).length;

  /// Grabs a frame and returns immediately. The recognition it starts resolves
  /// later, into whichever chip is still holding this id.
  Future<void> capture() async {
    final bytes = await ref.read(scanCameraProvider).capture();
    final id = 'chip-${_seq++}';
    _frames[id] = bytes;
    state = [
      ...state,
      ScanItem(id: id, status: ScanItemStatus.recognizing, frame: bytes),
    ];
    _queue.add(id);
    _pump();
  }

  /// Re-sends a failed chip's held frame -- no re-shoot required.
  Future<void> retry(String itemId) async {
    if (!_frames.containsKey(itemId)) return;
    _patch(itemId, (it) => it.copyWith(status: ScanItemStatus.recognizing));
    _queue.add(itemId);
    _pump();
  }

  void _pump() {
    while (_active < maxScanInFlight && _queue.isNotEmpty) {
      final id = _queue.removeAt(0);
      // A chip removed while queued must not consume a slot.
      if (!state.any((it) => it.id == id)) continue;
      _active++;
      _recognize(id);
    }
  }

  Future<void> _recognize(String id) async {
    final bytes = _frames[id];
    if (bytes == null) {
      _active--;
      return;
    }
    final products =
        ref.read(productsStreamProvider).value ?? const <Product>[];
    final payload = buildCandidatePayload(products);
    final result = await ref
        .read(visionScanRepositoryProvider)
        .recognize(imageBytes: bytes, candidates: payload.candidates);
    _active--;

    // The chip may have been removed while the call was in flight.
    if (state.any((it) => it.id == id)) {
      result.when(
        success: (recognition) {
          final byId = {for (final p in products) p.id: p};
          final decision = decideScanAction(recognition);
          final matched = <Product>[
            for (final m in decision.matches)
              if (byId[payload.resolve(m.productId)] case final Product p) p,
          ];
          final label = _readLabel(
            recognition.readBrand,
            recognition.readName,
            recognition.readSize,
          );
          if (decision.action == ScanAction.autoSell && matched.isNotEmpty) {
            _resolve(id, matched.first, label);
          } else if (matched.length > 1) {
            _patch(
              id,
              (it) => it.copyWith(
                status: ScanItemStatus.ambiguous,
                choices: matched,
                readLabel: label,
              ),
            );
          } else if (matched.length == 1) {
            _resolve(id, matched.first, label);
          } else {
            _patch(
              id,
              (it) => it.copyWith(
                status: ScanItemStatus.unmatched,
                readLabel: label,
              ),
            );
          }
        },
        failure: (_) =>
            _patch(id, (it) => it.copyWith(status: ScanItemStatus.failed)),
      );
    }
    _pump();
  }

  /// Settles [id] onto [product], folding into an existing chip for the same
  /// product if there is one.
  ///
  /// The fold happens HERE, at resolve time, not at capture time: a pending chip
  /// has no product yet and answers arrive out of order, so capture cannot know
  /// what it is merging into. This is what makes "tap the shutter three times
  /// for three bottles" show as one chip at x3.
  void _resolve(String id, Product product, String? readLabel) {
    final step = stepForUnit(product.unit);
    final twin = state.indexWhere(
      (it) =>
          it.id != id &&
          it.status == ScanItemStatus.resolved &&
          it.product?.id == product.id,
    );
    _frames.remove(id);

    if (twin != -1) {
      final target = state[twin];
      final bumped = _clamp(product, target.quantity + step);
      final next = [...state];
      next[twin] = target.copyWith(quantity: bumped);
      state = next.where((it) => it.id != id).toList();
      return;
    }
    _patch(
      id,
      (it) => it.copyWith(
        status: ScanItemStatus.resolved,
        product: product,
        readLabel: readLabel,
        quantity: _clamp(product, step),
        choices: const <Product>[],
        clearFrame: true,
      ),
    );
  }

  /// Settles an ambiguous or unmatched chip onto a product the shopkeeper
  /// picked. Merges by the same rule as a recognition.
  void choose(String itemId, Product product) {
    final it = state.where((i) => i.id == itemId).firstOrNull;
    _resolve(itemId, product, it?.readLabel);
  }

  void setQuantity(String itemId, double quantity) {
    final it = state.where((i) => i.id == itemId).firstOrNull;
    final product = it?.product;
    if (product == null) return;
    final clamped = _clamp(product, quantity);
    if (clamped <= 0) return remove(itemId);
    _patch(itemId, (i) => i.copyWith(quantity: clamped));
  }

  void remove(String itemId) {
    _frames.remove(itemId);
    _queue.remove(itemId);
    state = state.where((i) => i.id != itemId).toList();
  }

  /// Stages every resolved chip into the cart and clears the tray. Chips that
  /// never resolved are dropped -- the screen confirms that with the user first.
  void addAllToCart() {
    final cart = ref.read(cartControllerProvider.notifier);
    for (final it in state) {
      if (it.isAddable) cart.addOrIncrement(it.product!, it.quantity);
    }
    state = const <ScanItem>[];
    _frames.clear();
    _queue.clear();
  }

  void clear() {
    state = const <ScanItem>[];
    _frames.clear();
    _queue.clear();
  }

  /// Clamps against stock the CART has not already claimed. The tray is not in
  /// the cart yet, and chips are merged one-per-product, so the cart's remaining
  /// figure is the correct ceiling.
  double _clamp(Product product, double value) => clampCartQuantity(
    value: value,
    remaining: ref
        .read(cartControllerProvider.notifier)
        .remainingStockFor(product),
    allowsDecimal: product.unitType.allowsDecimal,
  );

  void _patch(String id, ScanItem Function(ScanItem) f) {
    state = [
      for (final it in state)
        if (it.id == id) f(it) else it,
    ];
  }

  static String? _readLabel(String? brand, String? name, String? size) {
    final parts = [
      brand,
      name,
      size,
    ].where((s) => s != null && s.trim().isNotEmpty).map((s) => s!.trim());
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

final scanSessionProvider =
    NotifierProvider<ScanSessionController, List<ScanItem>>(
      ScanSessionController.new,
    );
