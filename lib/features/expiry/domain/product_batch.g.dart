// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'product_batch.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ProductBatch _$ProductBatchFromJson(Map<String, dynamic> json) =>
    _ProductBatch(
      id: json['id'] as String,
      shopId: json['shop_id'] as String,
      productId: json['product_id'] as String,
      quantity: (json['quantity'] as num).toDouble(),
      buyingPrice: (json['buying_price'] as num?)?.toDouble() ?? 0,
      receivedOn: DateTime.parse(json['received_on'] as String),
      expiryDate: DateTime.parse(json['expiry_date'] as String),
      expiredQty: (json['expired_qty'] as num?)?.toDouble(),
      pickedQty: (json['picked_qty'] as num?)?.toDouble() ?? 0,
      closedAt: json['closed_at'] == null
          ? null
          : DateTime.parse(json['closed_at'] as String),
      closedReason: json['closed_reason'] as String?,
      createdAt: json['created_at'] == null
          ? null
          : DateTime.parse(json['created_at'] as String),
    );

Map<String, dynamic> _$ProductBatchToJson(_ProductBatch instance) =>
    <String, dynamic>{
      'id': instance.id,
      'shop_id': instance.shopId,
      'product_id': instance.productId,
      'quantity': instance.quantity,
      'buying_price': instance.buyingPrice,
      'received_on': instance.receivedOn.toIso8601String(),
      'expiry_date': instance.expiryDate.toIso8601String(),
      'expired_qty': instance.expiredQty,
      'picked_qty': instance.pickedQty,
      'closed_at': instance.closedAt?.toIso8601String(),
      'closed_reason': instance.closedReason,
      'created_at': instance.createdAt?.toIso8601String(),
    };
