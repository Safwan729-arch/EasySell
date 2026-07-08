// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'category.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Category _$CategoryFromJson(Map<String, dynamic> json) => _Category(
  id: json['id'] as String,
  shopId: json['shop_id'] as String,
  name: json['name'] as String,
  nameNormalized: json['name_normalized'] as String,
  createdAt: json['created_at'] == null
      ? null
      : DateTime.parse(json['created_at'] as String),
);

Map<String, dynamic> _$CategoryToJson(_Category instance) => <String, dynamic>{
  'id': instance.id,
  'shop_id': instance.shopId,
  'name': instance.name,
  'name_normalized': instance.nameNormalized,
  'created_at': instance.createdAt?.toIso8601String(),
};
