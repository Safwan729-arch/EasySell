import '../../cart/domain/cart_line.dart';
import '../../inventory/domain/product.dart';
import 'batch_pick.dart';
import 'expiry_estimate.dart';

/// Why a cart line cannot be checked out as it stands (spec §5 Cart).
sealed class CartLineNotice {
  const CartLineNotice();
}

/// The line wants more than the GOOD stock while expired units exist.
final class ExpiredStockNotice extends CartLineNotice {
  const ExpiredStockNotice({
    required this.good,
    required this.expired,
    required this.expiredBatchIds,
  });

  final double good;
  final double expired;

  /// The deliveries "Remove expired" / "They're not expired" act on.
  final List<String> expiredBatchIds;
}

/// The line wants more than the live stock (e.g. after "Remove expired").
final class OverStockNotice extends CartLineNotice {
  const OverStockNotice(this.stock);
  final double stock;
}

/// The line's chosen delivery has fewer units than the line wants (0 when
/// that delivery is gone).
final class BatchShortNotice extends CartLineNotice {
  const BatchShortNotice(this.left);
  final double left;
}

/// The product has several batches and the seller has not said which one
/// this line sells from.
final class BatchUnchosenNotice extends CartLineNotice {
  const BatchUnchosenNotice();
}

/// One notice per product whose line cannot go through. [liveProducts] is the
/// live product list keyed by id -- a cart line holds a snapshot of the
/// product from when it was added, so its own `quantity` may be stale.
Map<String, CartLineNotice> cartLineNotices({
  required List<CartLine> lines,
  required Map<String, Product> liveProducts,
  required Map<String, ProductExpiry> byProduct,
}) {
  final out = <String, CartLineNotice>{};
  for (final l in lines) {
    final id = l.product.id;
    final e = byProduct[id];
    if (e != null && e.expired > 0 && l.quantity > e.good + 1e-9) {
      out[id] = ExpiredStockNotice(
        good: e.good,
        expired: e.expired,
        expiredBatchIds: [for (final b in e.expiredWithStock) b.batch.id],
      );
      continue;
    }
    if (isUnchosen(l, e)) {
      out[id] = const BatchUnchosenNotice();
      continue;
    }
    final left = chosenLeft(l, e);
    if (left != null && l.quantity > left + 1e-9) {
      out[id] = BatchShortNotice(left);
      continue;
    }
    final live = liveProducts[id];
    if (live != null && l.quantity > live.quantity + 1e-9) {
      out[id] = OverStockNotice(live.quantity);
    }
  }
  return out;
}

/// Products whose line would sell expired units. Checkout refuses these.
List<String> expiredBlockedProductIds(
  List<CartLine> lines,
  Map<String, ProductExpiry> byProduct,
) => [
  for (final l in lines)
    if ((byProduct[l.product.id]?.expired ?? 0) > 0 &&
        l.quantity > byProduct[l.product.id]!.good + 1e-9)
      l.product.id,
];
