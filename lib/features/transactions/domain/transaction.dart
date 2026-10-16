import 'package:freezed_annotation/freezed_annotation.dart';

part 'transaction.freezed.dart';
part 'transaction.g.dart';

/// A stock movement. `buyingPrice`/`sellingPrice` are SNAPSHOTS frozen at the
/// time of the transaction by the `record_sale`/`record_restock` RPCs — never
/// recompute historical profit from current product prices.
@freezed
abstract class Transaction with _$Transaction {
  const Transaction._();

  const factory Transaction({
    required String id,
    required String shopId,
    required String productId,
    required String type, // 'sale' | 'restock' | 'adjustment'
    required double quantity, // decimal: 12 pcs OR 2.5 kg
    @Default(0) double buyingPrice,
    @Default(0) double sellingPrice,

    /// This line's share of a cart-level discount, allocated by
    /// `record_sale_cart`. Summing it over a `saleGroupId` reproduces the
    /// discount the shopkeeper typed, exactly -- the split floors and then
    /// hands the remainder out a paisa at a time, so nothing is lost to
    /// rounding and the receipt total never needs storing separately.
    @Default(0) double discountAmount,
    String? source, // 'voice' | 'image' | 'manual'
    String? saleGroupId, // shared by every line from one cart checkout
    /// The delivery this sale line was taken from (0012). Null for undated
    /// stock and for sales made before deliveries were tracked.
    String? batchId,

    /// That delivery's expiry date, read from the embedded
    /// `batch:product_batches(expiry_date)` History selects. Display only:
    /// never written back, since it is not a column of `transactions`.
    @JsonKey(readValue: _readBatchExpiry, includeToJson: false)
    DateTime? batchExpiry,

    /// How the customer paid: 'cash' | 'digital' | 'credit' (0018). Null for
    /// sales made before it was recorded -- History shows nothing for those
    /// rather than guessing.
    String? paymentMethod,
    DateTime? createdAt,
  }) = _Transaction;

  factory Transaction.fromJson(Map<String, dynamic> json) =>
      _$TransactionFromJson(json);

  double get revenue => sellingPrice * quantity - discountAmount;
  double get cost => buyingPrice * quantity;
  double get profit => revenue - cost;
}

Object? _readBatchExpiry(Map<dynamic, dynamic> json, String _) =>
    (json['batch'] as Map?)?['expiry_date'];
