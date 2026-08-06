import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/cart_math.dart';
import '../domain/discount_math.dart';
import 'cart_controller.dart';

/// A flat amount off the whole cart, held beside the cart rather than inside
/// it -- the same shape as [PaymentMethodController], which is also a small
/// per-checkout decision rather than part of the basket itself.
///
/// `build` WATCHES the cart, so the discount is re-clamped every time a line
/// is added, changed or removed. That is the whole reason this is a Notifier
/// and not a plain field: a discount is entered against one basket, and the
/// shopkeeper can then take things out of it. Storing the clamped value (as
/// opposed to remembering the larger entered figure and displaying a smaller
/// one) keeps the number on screen and the number sent to `record_sale_cart`
/// identical -- there is no second, hidden truth to disagree with.
class CartDiscountController extends Notifier<double> {
  double _entered = 0;

  @override
  double build() {
    final subtotal = cartTotal(ref.watch(cartControllerProvider));
    final clamped = clampDiscount(entered: _entered, subtotal: subtotal);
    _entered = clamped;
    return clamped;
  }

  void setAmount(double amount) {
    final subtotal = cartTotal(ref.read(cartControllerProvider));
    _entered = clampDiscount(entered: amount, subtotal: subtotal);
    state = _entered;
  }

  void clear() {
    _entered = 0;
    state = 0;
  }
}

final cartDiscountControllerProvider =
    NotifierProvider<CartDiscountController, double>(
      CartDiscountController.new,
    );
