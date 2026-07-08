// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'product.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Product _$ProductFromJson(Map<String, dynamic> json) => _Product(
  id: json['id'] as String,
  shopId: json['shop_id'] as String,
  name: json['name'] as String,
  unitType:
      $enumDecodeNullable(_$UnitTypeEnumMap, json['unit_type']) ??
      UnitType.piece,
  unit:
      $enumDecodeNullable(_$ProductUnitEnumMap, json['unit']) ??
      ProductUnit.pcs,
  brand: json['brand'] as String?,
  variant: json['variant'] as String?,
  categoryId: json['category_id'] as String?,
  category: json['category'] as String?,
  quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
  buyingPrice: (json['buying_price'] as num?)?.toDouble() ?? 0,
  sellingPrice: (json['selling_price'] as num?)?.toDouble() ?? 0,
  reorderThreshold: (json['reorder_threshold'] as num?)?.toDouble() ?? 0,
  imageUrls:
      (json['image_urls'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const <String>[],
  createdAt: json['created_at'] == null
      ? null
      : DateTime.parse(json['created_at'] as String),
  updatedAt: json['updated_at'] == null
      ? null
      : DateTime.parse(json['updated_at'] as String),
);

Map<String, dynamic> _$ProductToJson(_Product instance) => <String, dynamic>{
  'id': instance.id,
  'shop_id': instance.shopId,
  'name': instance.name,
  'unit_type': _$UnitTypeEnumMap[instance.unitType]!,
  'unit': _$ProductUnitEnumMap[instance.unit]!,
  'brand': instance.brand,
  'variant': instance.variant,
  'category_id': instance.categoryId,
  'category': instance.category,
  'quantity': instance.quantity,
  'buying_price': instance.buyingPrice,
  'selling_price': instance.sellingPrice,
  'reorder_threshold': instance.reorderThreshold,
  'image_urls': instance.imageUrls,
  'created_at': instance.createdAt?.toIso8601String(),
  'updated_at': instance.updatedAt?.toIso8601String(),
};

const _$UnitTypeEnumMap = {
  UnitType.piece: 'piece',
  UnitType.weight: 'weight',
  UnitType.volume: 'volume',
};

const _$ProductUnitEnumMap = {
  ProductUnit.pcs: 'pcs',
  ProductUnit.kg: 'kg',
  ProductUnit.g: 'g',
  ProductUnit.litre: 'litre',
  ProductUnit.ml: 'ml',
};
