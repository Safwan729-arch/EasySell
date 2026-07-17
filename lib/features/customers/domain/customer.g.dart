// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'customer.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Customer _$CustomerFromJson(Map<String, dynamic> json) => _Customer(
  id: json['id'] as String,
  shopId: json['shop_id'] as String,
  name: json['name'] as String,
  phone: json['phone'] as String,
  note: json['note'] as String?,
  createdAt: json['created_at'] == null
      ? null
      : DateTime.parse(json['created_at'] as String),
);

Map<String, dynamic> _$CustomerToJson(_Customer instance) => <String, dynamic>{
  'id': instance.id,
  'shop_id': instance.shopId,
  'name': instance.name,
  'phone': instance.phone,
  'note': instance.note,
  'created_at': instance.createdAt?.toIso8601String(),
};
