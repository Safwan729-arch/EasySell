import 'dart:math' as math;

import '../../inventory/domain/product.dart';
import 'expiry_dates.dart';
import 'product_batch.dart';

/// Status of one open delivery on a given day (spec §4.3).
enum BatchStatus { good, expiringSoon, expired, soldOut }

/// A write the estimate asks for (spec §4.2). The estimate itself never
/// writes; `ExpiryReconciler` applies these from a fresh server read.
sealed class ReconcileWrite {
  const ReconcileWrite(this.batchId);
  final String batchId;
}

/// Store [quantity] as the delivery's `expired_qty`. From then on sales are
/// never counted against those units.
final class LockExpired extends ReconcileWrite {
  const LockExpired(super.batchId, this.quantity);
  final double quantity;

  @override
  bool operator ==(Object other) =>
      other is LockExpired &&
      other.batchId == batchId &&
      other.quantity == quantity;

  @override
  int get hashCode => Object.hash('lock', batchId, quantity);

  @override
  String toString() => 'LockExpired($batchId, $quantity)';
}

/// Close the delivery as `sold_out`. Without this, an undated restock would
/// be handed to the old delivery and raise a false alarm.
final class CloseSoldOut extends ReconcileWrite {
  const CloseSoldOut(super.batchId);

  @override
  bool operator ==(Object other) =>
      other is CloseSoldOut && other.batchId == batchId;

  @override
  int get hashCode => Object.hash('close', batchId);

  @override
  String toString() => 'CloseSoldOut($batchId)';
}

class BatchEstimate {
  const BatchEstimate({
    required this.batch,
    required this.left,
    required this.status,
    required this.warnDays,
  });

  final ProductBatch batch;

  /// Estimated units of this delivery still on the shelf.
  final double left;
  final BatchStatus status;
  final int warnDays;
}

class ProductExpiry {
  const ProductExpiry({
    required this.productId,
    required this.stock,
    required this.good,
    required this.expired,
    required this.batches,
    required this.writes,
  });

  final String productId;
  final double stock;

  /// Units that may be sold: stock minus expired units.
  final double good;
  final double expired;

  /// Open deliveries, earliest expiry first.
  final List<BatchEstimate> batches;
  final List<ReconcileWrite> writes;

  Iterable<BatchEstimate> get expiredWithStock =>
      batches.where((b) => b.status == BatchStatus.expired && b.left > 0);

  Iterable<BatchEstimate> get expiringSoon =>
      batches.where((b) => b.status == BatchStatus.expiringSoon);
}

/// Rounds to whole thousandths -- the `numeric(10,3)` precision the database
/// keeps. Without it 0.1 + 0.2 leaves a 0.00000000000000004 remainder that
/// keeps a "sold out" delivery open, or a 0.0999999 that wrongly closes one.
double round3(double v) => (v * 1000).roundToDouble() / 1000;

/// Days before expiry the warning starts (spec §4.3). Shelf life is
/// `expiryDate - receivedOn`; a short-lived item is warned near its end
/// (5-day bread: 1 day), a long-lived one [shopWarnDays] ahead.
int warningDays({
  required DateTime receivedOn,
  required DateTime expiryDate,
  required int shopWarnDays,
  int? productWarnDays,
}) {
  if (productWarnDays != null) return productWarnDays;
  final shelf = daysBetween(receivedOn, expiryDate);
  final auto = math.max(1, shelf ~/ 3);
  return math.min(shopWarnDays, auto);
}

DateTime _created(ProductBatch b) =>
    b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

/// Estimates every open delivery of one product (spec §4.1).
///
/// 1. Locked expired deliveries are reserved first, earliest expiry first.
/// 2. Every other delivery is filled newest-received first, so whatever is
///    left over lands on the oldest ("older sells first"). A delivery holds
///    at most its amount minus the units picked from it at checkout.
/// 3. Anything still left is untracked stock with no date, counted as good.
ProductExpiry estimateProductExpiry({
  required String productId,
  required double stock,
  required List<ProductBatch> openBatches,
  required DateTime today,
  required int shopWarnDays,
  int? productWarnDays,
}) {
  final t = dateOnly(today);
  final st = stock < 0 ? 0.0 : stock;
  var r = st;
  final alloc = <String, double>{};

  final locked = openBatches.where((b) => b.expiredQty != null).toList()
    ..sort((a, b) {
      final c = a.expiryDate.compareTo(b.expiryDate);
      return c != 0 ? c : _created(a).compareTo(_created(b));
    });
  for (final b in locked) {
    final take = math.min(b.expiredQty!, r);
    alloc[b.id] = take;
    r -= take;
  }

  final rest = openBatches.where((b) => b.expiredQty == null).toList()
    ..sort((a, b) {
      final c = b.receivedOn.compareTo(a.receivedOn);
      return c != 0 ? c : _created(b).compareTo(_created(a));
    });
  for (final b in rest) {
    // Units picked from this delivery at checkout already left it, so they
    // are not FIFO's to hand out. Stock went down by the same amount, so the
    // older deliveries keep exactly what they had.
    final take = math.min(math.max(0.0, b.quantity - b.pickedQty), r);
    alloc[b.id] = take;
    r -= take;
  }

  final estimates = <BatchEstimate>[];
  final writes = <ReconcileWrite>[];
  var expired = 0.0;
  for (final b in openBatches) {
    final left = round3(alloc[b.id] ?? 0);
    final w = warningDays(
      receivedOn: b.receivedOn,
      expiryDate: b.expiryDate,
      shopWarnDays: shopWarnDays,
      productWarnDays: productWarnDays,
    );
    final BatchStatus status;
    if (b.expiredQty != null) {
      status = BatchStatus.expired;
      expired += left;
    } else if (left <= 0) {
      status = BatchStatus.soldOut;
      writes.add(CloseSoldOut(b.id));
    } else if (t.isAfter(dateOnly(b.expiryDate))) {
      status = BatchStatus.expired;
      expired += left;
      writes.add(LockExpired(b.id, left));
    } else if (daysBetween(t, b.expiryDate) <= w) {
      status = BatchStatus.expiringSoon;
    } else {
      status = BatchStatus.good;
    }
    estimates.add(
      BatchEstimate(batch: b, left: left, status: status, warnDays: w),
    );
  }
  estimates.sort((a, b) => a.batch.expiryDate.compareTo(b.batch.expiryDate));

  final exp = round3(expired);
  return ProductExpiry(
    productId: productId,
    stock: st,
    good: round3(math.max(0, st - exp)),
    expired: exp,
    batches: estimates,
    writes: writes,
  );
}

/// Estimates every product in [products] that has at least one open
/// delivery. Products not in the list (archived) are skipped.
Map<String, ProductExpiry> estimateAll({
  required List<Product> products,
  required List<ProductBatch> openBatches,
  required DateTime today,
  required int shopWarnDays,
}) {
  final byProduct = <String, List<ProductBatch>>{};
  for (final b in openBatches) {
    if (b.isOpen) (byProduct[b.productId] ??= []).add(b);
  }
  return {
    for (final p in products)
      if (byProduct[p.id] != null)
        p.id: estimateProductExpiry(
          productId: p.id,
          stock: p.quantity,
          openBatches: byProduct[p.id]!,
          today: today,
          shopWarnDays: shopWarnDays,
          productWarnDays: p.expiryWarnDays,
        ),
  };
}

/// Units of [stock] that sit in no open delivery, so have no expiry date.
/// Never negative.
double undatedStock(double stock, ProductExpiry? e) {
  final dated = e?.batches.fold<double>(0, (s, b) => s + b.left) ?? 0;
  return math.max(0.0, round3(stock - dated));
}

/// Units of [p] that may be sold. A product with no open deliveries is
/// entirely good stock.
double goodStockOf(Product p, Map<String, ProductExpiry> byProduct) =>
    byProduct[p.id]?.good ?? p.quantity;

/// [batches] as they will look once [writes] are stored: locks applied,
/// sold-out deliveries gone.
List<ProductBatch> applyReconcileWrites(
  List<ProductBatch> batches,
  List<ReconcileWrite> writes,
) {
  final locks = {
    for (final w in writes.whereType<LockExpired>()) w.batchId: w.quantity,
  };
  final closed = {for (final w in writes.whereType<CloseSoldOut>()) w.batchId};
  return [
    for (final b in batches)
      if (!closed.contains(b.id))
        locks.containsKey(b.id) ? b.copyWith(expiredQty: locks[b.id]) : b,
  ];
}
