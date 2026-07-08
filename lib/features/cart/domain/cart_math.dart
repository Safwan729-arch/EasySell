import '../../inventory/domain/product.dart';
import 'cart_line.dart';

/// Adds [quantity] of [product] to [lines], merging into an existing line for
/// the same product if present. The resulting quantity for that product is
/// clamped to [Product.quantity] (current stock) so the cart can never stage
/// more of an item than physically exists, even across repeated adds.
List<CartLine> addOrIncrementLine(
  List<CartLine> lines,
  Product product,
  double quantity,
) {
  final index = lines.indexWhere((l) => l.product.id == product.id);
  if (index == -1) {
    final clamped = quantity.clamp(0, product.quantity).toDouble();
    return clamped <= 0
        ? lines
        : [...lines, CartLine(product: product, quantity: clamped)];
  }
  final existing = lines[index];
  final merged =
      (existing.quantity + quantity).clamp(0, product.quantity).toDouble();
  final updated = [...lines];
  updated[index] = existing.copyWith(quantity: merged);
  return updated;
}

/// How much more of [product] can be added right now: current stock minus
/// whatever quantity of it is already staged in [lines]. Never negative.
double remainingStockForLines(List<CartLine> lines, Product product) {
  final staged = lines
      .where((l) => l.product.id == product.id)
      .fold<double>(0, (sum, l) => sum + l.quantity);
  final remaining = product.quantity - staged;
  return remaining < 0 ? 0 : remaining;
}

/// Sets the line for [productId] to exactly [quantity], clamped to that
/// product's current stock. A quantity at/below zero removes the line.
List<CartLine> updateLineQuantity(
  List<CartLine> lines,
  String productId,
  double quantity,
) {
  if (quantity <= 0) return removeLine(lines, productId);
  final index = lines.indexWhere((l) => l.product.id == productId);
  if (index == -1) return lines;
  final clamped = quantity.clamp(0, lines[index].product.quantity).toDouble();
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
