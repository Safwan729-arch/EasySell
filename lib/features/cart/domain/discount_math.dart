import 'cart_line.dart';

/// Rounds down to whole paisa.
///
/// The epsilon is not paranoia. `0.29 * 100` is 28.999999999999996 in IEEE
/// 754, so a bare `.floor()` returns 0.28 and short-changes the customer on a
/// perfectly ordinary amount. Nudging up by a billionth clears the
/// representation error without ever promoting a genuine 0.005 to 0.01.
double _floorPaisa(double v) => (v * 100 + 1e-9).floor() / 100;

/// The largest discount `record_sale_cart` will accept for [lines]: the sum of
/// each line's FLOORED subtotal, not the floor of the summed subtotal.
///
/// The distinction is invisible on ordinary 2-decimal carts, where the two are
/// identical, and load-bearing on fractional-quantity ones. `discount_amount`
/// is `numeric(10,2)` and each line's share is floored so it can never exceed
/// that line's own value (`transactions_discount_within_line`), so the largest
/// amount the split can actually place is the sum of the per-line floors. Two
/// lines of 45.00 x 2.501 = 112.545 sum to exactly 225.09 -- which the floor of
/// the total permits -- but each line can only absorb 112.54, so a paisa would
/// be left unallocated and `sum(discount_amount)` would come to 225.08. Capping
/// at 225.08 instead makes the maximum exactly allocatable by construction, so
/// "the entered discount equals the sum of the stored shares" becomes true
/// rather than approximately true.
///
/// The outer floor only repairs binary drift: each term is already a whole
/// number of paisa, but summing them in doubles can land a hair above.
///
/// This MUST match `record_sale_cart`'s `v_max`. A Dart cap above the SQL one
/// offers a discount the database refuses, turning an ordinary checkout into a
/// failure; a Dart cap below it silently short-changes the shopkeeper.
double maxDiscount(List<CartLine> lines) => _floorPaisa(
  lines.fold<double>(0, (sum, l) => sum + _floorPaisa(l.subtotal)),
);

/// The discount actually chargeable against the bill for [lines].
///
/// Clamping is not cosmetic: a discount is entered against one cart and the
/// shopkeeper can then remove lines from it. Rather than remember the larger
/// entered figure and display a smaller one, the controller stores the clamped
/// value -- a gap between the number on screen and the number sent to the
/// database is where money bugs live.
///
/// The cap is [maxDiscount], not the raw subtotal, because `record_sale_cart`
/// raises `Discount exceeds total` above it. The entered amount is floored for
/// the same reason the cap is: `discount_amount` is `numeric(10,2)` and cannot
/// store a third decimal.
double clampDiscount({
  required double entered,
  required List<CartLine> lines,
}) {
  if (entered <= 0) return 0;
  final cap = maxDiscount(lines);
  if (cap <= 0) return 0;
  final wanted = _floorPaisa(entered);
  return wanted > cap ? cap : wanted;
}

/// What the staged cart cost the shop -- buying price x quantity, summed.
/// Buying prices are already on the [CartLine]'s product, so this needs no
/// network call and the below-cost warning can be live as the field is typed.
double cartCost(List<CartLine> lines) => lines.fold<double>(
  0,
  (sum, l) => sum + l.product.buyingPrice * l.quantity,
);

/// How much money the shop loses if [discount] is applied -- 0 while the sale
/// still breaks even or profits.
///
/// Drives a warning, never a block: clearing near-expiry stock below cost is a
/// deliberate, normal thing to do, and the app is not the shopkeeper's boss.
double lossFromDiscount({
  required double subtotal,
  required double cost,
  required double discount,
}) {
  final net = subtotal - discount;
  return net >= cost ? 0 : cost - net;
}
