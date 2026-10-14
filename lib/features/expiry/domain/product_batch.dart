import 'package:freezed_annotation/freezed_annotation.dart';

part 'product_batch.freezed.dart';
part 'product_batch.g.dart';

/// `product_batches.closed_reason` values (CHECK constraint in 0011).
abstract final class BatchCloseReason {
  static const removed = 'removed';
  static const noneLeft = 'none_left';
  static const notExpired = 'not_expired';
  static const soldOut = 'sold_out';
}

/// One delivery that has an expiry date. How much of it is LEFT is never
/// stored -- it is estimated from the product's current stock (see
/// `expiry_estimate.dart`), so sales never have to know about deliveries.
///
/// `receivedOn` / `expiryDate` are Postgres `date`s: `DateTime.parse` reads
/// "2026-10-20" as local midnight, which is exactly the local calendar date.
@freezed
abstract class ProductBatch with _$ProductBatch {
  const ProductBatch._();

  const factory ProductBatch({
    required String id,
    required String shopId,
    required String productId,
    required double quantity,
    @Default(0) double buyingPrice,
    required DateTime receivedOn,
    required DateTime expiryDate,
    // Locked the first time the app sees this delivery expired; from then on
    // sales are never counted against these units (spec §4.2).
    double? expiredQty,
    // Units the shopkeeper chose to sell from THIS delivery at checkout
    // (migration 0012). The estimate takes them off this delivery before it
    // works out who holds the rest.
    @Default(0) double pickedQty,
    DateTime? closedAt,
    String? closedReason,
    DateTime? createdAt,
  }) = _ProductBatch;

  factory ProductBatch.fromJson(Map<String, dynamic> json) =>
      _$ProductBatchFromJson(json);

  bool get isOpen => closedAt == null;
}
