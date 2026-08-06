import 'cart_line.dart';

/// Rounds down to whole paisa.
///
/// The epsilon is not paranoia. `0.29 * 100` is 28.999999999999996 in IEEE
/// 754, so a bare `.floor()` returns 0.28 and short-changes the customer on a
/// perfectly ordinary amount. Nudging up by a billionth clears the
/// representation error without ever promoting a genuine 0.005 to 0.01.
double _floorPaisa(double v) => (v * 100 + 1e-9).floor() / 100;

/// The discount actually chargeable against a bill of [subtotal].
///
/// Clamping is not cosmetic: a discount is entered against one cart and the
/// shopkeeper can then remove lines from it. Rather than remember the larger
/// entered figure and display a smaller one, the controller stores the clamped
/// value -- a gap between the number on screen and the number sent to the
/// database is where money bugs live.
///
/// The cap is the FLOORED subtotal, not the raw one, because `record_sale_cart`
/// raises `Discount exceeds total` above `floor(subtotal * 100) / 100`. A cart
/// can carry a fractional subtotal (`selling_price numeric(10,2)` times
/// `quantity numeric(10,3)`), so clamping to the raw value would let the UI
/// offer a discount the database then refuses -- turning a legal sale into a
/// failed checkout. The entered amount is floored for the same reason:
/// `discount_amount` is `numeric(10,2)` and cannot store a third decimal.
double clampDiscount({required double entered, required double subtotal}) {
  if (entered <= 0 || subtotal <= 0) return 0;
  final cap = _floorPaisa(subtotal);
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
