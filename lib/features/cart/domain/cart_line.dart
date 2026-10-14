import 'package:freezed_annotation/freezed_annotation.dart';

import '../../inventory/domain/product.dart';

part 'cart_line.freezed.dart';

/// One staged line in the cart: a product plus the quantity to sell. Purely
/// local UI state -- never serialized; checkout converts it to the RPC's
/// plain jsonb shape via `resolveSaleItems` (see batch_pick.dart).
@freezed
abstract class CartLine with _$CartLine {
  const CartLine._();

  const factory CartLine({
    required Product product,
    required double quantity,
    // The delivery to sell from: null = soonest expiry first, [noDateBatch]
    // = the stock with no date, otherwise a `product_batches` id.
    String? batchId,
  }) = _CartLine;

  double get subtotal => product.sellingPrice * quantity;
}
