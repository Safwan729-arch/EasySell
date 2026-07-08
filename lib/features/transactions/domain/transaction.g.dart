// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transaction.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Transaction _$TransactionFromJson(Map<String, dynamic> json) => _Transaction(
  id: json['id'] as String,
  shopId: json['shop_id'] as String,
  productId: json['product_id'] as String,
  type: json['type'] as String,
  quantity: (json['quantity'] as num).toDouble(),
  buyingPrice: (json['buying_price'] as num?)?.toDouble() ?? 0,
  sellingPrice: (json['selling_price'] as num?)?.toDouble() ?? 0,
  source: json['source'] as String?,
  saleGroupId: json['sale_group_id'] as String?,
  createdAt: json['created_at'] == null
      ? null
      : DateTime.parse(json['created_at'] as String),
);

Map<String, dynamic> _$TransactionToJson(_Transaction instance) =>
    <String, dynamic>{
      'id': instance.id,
      'shop_id': instance.shopId,
      'product_id': instance.productId,
      'type': instance.type,
      'quantity': instance.quantity,
      'buying_price': instance.buyingPrice,
      'selling_price': instance.sellingPrice,
      'source': instance.source,
      'sale_group_id': instance.saleGroupId,
      'created_at': instance.createdAt?.toIso8601String(),
    };
