import '../../inventory/domain/product.dart';
import 'cart_line.dart';

/// Adds [quantity] of [product] to [lines], merging into an existing line for
/// the same product if present. The resulting quantity for that product is
/// clamped to [Product.quantity] (current stock) so the cart can never stage
/// more of an item than physically exists, even across repeated adds, and
/// rounded to the database's `numeric(10,3)` precision (see [_round3]).
///
/// The rounding is here, not only in [clampCartQuantity], because not every
/// caller goes through the add-to-cart sheet. The voice flow hands a quantity
/// straight from the AI's JSON to this function, so a parsed `2.5004` would
/// otherwise be staged at four decimals while Postgres stores three — making
/// the app's subtotal disagree with the one `record_sale_cart` computes, and
/// a near-total discount fail the whole checkout.
List<CartLine> addOrIncrementLine(
  List<CartLine> lines,
  Product product,
  double quantity,
) {
  final index = lines.indexWhere((l) => l.product.id == product.id);
  if (index == -1) {
    final clamped = _round3(quantity.clamp(0, product.quantity).toDouble());
    return clamped <= 0
        ? lines
        : [...lines, CartLine(product: product, quantity: clamped)];
  }
  final existing = lines[index];
  final merged = _round3(
    (existing.quantity + quantity).clamp(0, product.quantity).toDouble(),
  );
  final updated = [...lines];
  updated[index] = existing.copyWith(quantity: merged);
  return updated;
}

/// How much more of [product] can be added right now: [stock] (default: the
/// product's current stock) minus whatever of it is already staged in
/// [lines]. Never negative. Callers pass the GOOD stock so expired units are
/// never offered (expiry spec §5 Cart).
double remainingStockForLines(
  List<CartLine> lines,
  Product product, {
  double? stock,
}) {
  final staged = lines
      .where((l) => l.product.id == product.id)
      .fold<double>(0, (sum, l) => sum + l.quantity);
  final remaining = (stock ?? product.quantity) - staged;
  return remaining < 0 ? 0 : remaining;
}

/// Sets the line for [productId] to exactly [quantity], clamped to that
/// product's current stock and rounded to the database's `numeric(10,3)`
/// precision (see [_round3], and the note on [addOrIncrementLine] for why the
/// rounding cannot live only in [clampCartQuantity]). A quantity at/below zero
/// removes the line.
List<CartLine> updateLineQuantity(
  List<CartLine> lines,
  String productId,
  double quantity,
) {
  if (quantity <= 0) return removeLine(lines, productId);
  final index = lines.indexWhere((l) => l.product.id == productId);
  if (index == -1) return lines;
  final clamped = _round3(
    quantity.clamp(0, lines[index].product.quantity).toDouble(),
  );
  final updated = [...lines];
  updated[index] = lines[index].copyWith(quantity: clamped);
  return updated;
}

List<CartLine> removeLine(List<CartLine> lines, String productId) =>
    lines.where((l) => l.product.id != productId).toList();

/// Sum of every line's subtotal (unit selling price x quantity).
double cartTotal(List<CartLine> lines) =>
    lines.fold(0, (sum, l) => sum + l.subtotal);

/// The wire shape `record_sale_cart` expects for its `p_items` jsonb array.
List<Map<String, dynamic>> cartItemsPayload(List<CartLine> lines) => [
  for (final l in lines) {'product_id': l.product.id, 'quantity': l.quantity},
];

/// Quantity-stepper increment matched to how a product is sold: whole units
/// for pieces, fractional for weight/volume. Used by the add-to-cart sheet
/// and the cart screen's line stepper.
double stepForUnit(ProductUnit unit) => switch (unit) {
  ProductUnit.pcs => 1,
  ProductUnit.kg => 0.5,
  ProductUnit.g => 50,
  ProductUnit.litre => 0.5,
  ProductUnit.ml => 50,
};

/// Rounds a quantity to whole thousandths, the precision the database keeps.
///
/// `transactions.quantity` is `numeric(10,3)` (0003 widened it for kg/litre),
/// so the INSERT rounds a fourth decimal away no matter what Dart holds. Dart
/// does not round, so without this the cart can stage a quantity the database
/// will never store, and every figure derived from it disagrees: at 1000/kg a
/// typed 0.1234 gives Dart a line subtotal of 123.40 and the database 123.00.
/// A discount of 123.40 -- which the app happily accepts against its own
/// subtotal -- then exceeds the bill `record_sale_cart` actually builds, so it
/// raises `Discount exceeds total` and the whole checkout fails with no stock
/// moved and nothing on screen explaining why. Rounding here means Dart can
/// never stage a quantity the database would change underneath it.
double _round3(double v) => (v * 1000).roundToDouble() / 1000;

/// Clamps a typed or stepped cart quantity to a valid range: never below 0,
/// never above [remaining] stock, rounded to the `numeric(10,3)` precision the
/// database stores (see [_round3]), and floored to a whole number when the
/// product is sold by the piece ([allowsDecimal] false). Used by the
/// add-to-cart sheet's quantity field and stepper.
double clampCartQuantity({
  required double value,
  required double remaining,
  required bool allowsDecimal,
}) {
  var v = allowsDecimal ? _round3(value) : value.floorToDouble();
  if (v < 0) v = 0;
  if (v > remaining) v = remaining;
  return v;
}
