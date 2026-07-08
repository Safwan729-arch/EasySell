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
    String? source, // 'voice' | 'image' | 'manual'
    String? saleGroupId, // shared by every line from one cart checkout
    DateTime? createdAt,
  }) = _Transaction;

  factory Transaction.fromJson(Map<String, dynamic> json) =>
      _$TransactionFromJson(json);

  double get revenue => sellingPrice * quantity;
  double get cost => buyingPrice * quantity;
  double get profit => revenue - cost;
}
