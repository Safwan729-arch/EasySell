import 'package:freezed_annotation/freezed_annotation.dart';

import '../../inventory/domain/product.dart';

part 'cart_line.freezed.dart';

/// One staged line in the cart: a product plus the quantity to sell. Purely
/// local UI state -- never serialized; checkout converts it to the RPC's
/// plain jsonb shape via `cartItemsPayload` (see cart_math.dart).
@freezed
abstract class CartLine with _$CartLine {
  const CartLine._();

  const factory CartLine({required Product product, required double quantity}) =
      _CartLine;

  double get subtotal => product.sellingPrice * quantity;
}
