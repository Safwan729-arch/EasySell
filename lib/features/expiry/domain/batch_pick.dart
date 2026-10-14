import 'dart:math' as math;

import '../../cart/domain/cart_line.dart';
import 'expiry_estimate.dart';

/// [CartLine.batchId] for "sell the stock that has no expiry date".
const noDateBatch = 'no-date';

/// [CartLine.batchId] for "several batches, soonest expiry first" -- only
/// offered when no single batch holds the line (see [offersMix]).
const mixBatches = 'mix';

/// One place a sale can come from: an open, unexpired delivery with units
/// left, or ([batchId] null) the stock that has no date.
class SellOption {
  const SellOption({
    required this.batchId,
    required this.left,
    this.expiryDate,
    this.status,
  });

  final String? batchId;
  final double left;
  final DateTime? expiryDate;
  final BatchStatus? status;
}

/// Where [e]'s product can be sold from, soonest expiry first and the stock
/// with no date last. Expired deliveries are never offered.
List<SellOption> sellOptions(ProductExpiry? e) {
  if (e == null) return const [];
  final dated = [
    for (final b in e.batches)
      if ((b.status == BatchStatus.good ||
              b.status == BatchStatus.expiringSoon) &&
          b.left > 0)
        SellOption(
          batchId: b.batch.id,
          left: b.left,
          expiryDate: b.batch.expiryDate,
          status: b.status,
        ),
  ];
  final loose = undatedStock(e.stock, e);
  return [...dated, if (loose > 0) SellOption(batchId: null, left: loose)];
}

/// The seller must pick a batch only when there is more than one place to
/// sell from; with one, the line sells from it, and a product without dates
/// looks exactly as it did before.
bool needsBatchChoice(List<SellOption> options) => options.length >= 2;

/// "Several batches, soonest expiry first" is offered only when no single
/// place to sell from holds [quantity] -- otherwise the seller names one.
bool offersMix(List<SellOption> options, double quantity) =>
    needsBatchChoice(options) && options.every((o) => o.left < quantity - 1e-9);

/// The one place a line sells from when there is no choice to make: the
/// single dated delivery, or null (no date, or nothing to sell from).
SellOption? onlyOption(List<SellOption> options) =>
    options.length == 1 ? options.single : null;

SellOption? _chosen(List<SellOption> options, String choice) {
  final id = choice == noDateBatch ? null : choice;
  for (final o in options) {
    if (o.batchId == id) return o;
  }
  return null;
}

/// What the line's chosen delivery has left: null when no single delivery
/// was chosen (none yet, or several batches), 0 when the chosen one is gone.
double? chosenLeft(CartLine line, ProductExpiry? e) {
  final choice = line.batchId;
  if (choice == null || choice == mixBatches) return null;
  return _chosen(sellOptions(e), choice)?.left ?? 0;
}

/// True when the line still needs the seller to pick a batch.
bool isUnchosen(CartLine line, ProductExpiry? e) =>
    line.batchId == null && needsBatchChoice(sellOptions(e));

Map<String, dynamic> _item(String productId, double qty, String? batchId) => {
  'product_id': productId,
  'quantity': qty,
  'batch_id': ?batchId,
};

/// The `record_sale_cart` items for [lines], each naming the delivery it
/// sells from, so the server can count the pick in the same save as the
/// sale. [unchosen] lists products with several batches and no choice made;
/// [short] those whose chosen delivery does not have enough left.
({List<Map<String, dynamic>> items, List<String> short, List<String> unchosen})
resolveSaleItems(List<CartLine> lines, Map<String, ProductExpiry> byProduct) {
  final items = <Map<String, dynamic>>[];
  final short = <String>[];
  final unchosen = <String>[];
  for (final l in lines) {
    final id = l.product.id;
    final options = sellOptions(byProduct[id]);
    final choice = l.batchId;
    if (choice == null) {
      if (needsBatchChoice(options)) {
        unchosen.add(id);
        continue;
      }
      // One place to sell from: name it when it holds the line. More than
      // that is more than the good stock, which the gate or server refuses.
      final only = onlyOption(options);
      items.add(
        _item(
          id,
          l.quantity,
          only != null && l.quantity <= only.left + 1e-9 ? only.batchId : null,
        ),
      );
      continue;
    }
    if (choice == mixBatches) {
      var rest = l.quantity;
      for (final o in options) {
        if (rest <= 1e-9) break;
        final take = round3(math.min(o.left, rest));
        if (take <= 0) continue;
        items.add(_item(id, take, o.batchId));
        rest = round3(rest - take);
      }
      // More than the good stock: the expiry gate or the server refuses it.
      if (rest > 1e-9) items.add(_item(id, rest, null));
      continue;
    }
    final o = _chosen(options, choice);
    if (o == null || l.quantity > o.left + 1e-9) {
      short.add(id);
      continue;
    }
    items.add(_item(id, l.quantity, o.batchId));
  }
  return (items: items, short: short, unchosen: unchosen);
}
