// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'product_batch.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ProductBatch {

 String get id; String get shopId; String get productId; double get quantity; double get buyingPrice; DateTime get receivedOn; DateTime get expiryDate; double? get expiredQty; double get pickedQty; DateTime? get closedAt; String? get closedReason; DateTime? get createdAt;
/// Create a copy of ProductBatch
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProductBatchCopyWith<ProductBatch> get copyWith => _$ProductBatchCopyWithImpl<ProductBatch>(this as ProductBatch, _$identity);

  /// Serializes this ProductBatch to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProductBatch&&(identical(other.id, id) || other.id == id)&&(identical(other.shopId, shopId) || other.shopId == shopId)&&(identical(other.productId, productId) || other.productId == productId)&&(identical(other.quantity, quantity) || other.quantity == quantity)&&(identical(other.buyingPrice, buyingPrice) || other.buyingPrice == buyingPrice)&&(identical(other.receivedOn, receivedOn) || other.receivedOn == receivedOn)&&(identical(other.expiryDate, expiryDate) || other.expiryDate == expiryDate)&&(identical(other.expiredQty, expiredQty) || other.expiredQty == expiredQty)&&(identical(other.pickedQty, pickedQty) || other.pickedQty == pickedQty)&&(identical(other.closedAt, closedAt) || other.closedAt == closedAt)&&(identical(other.closedReason, closedReason) || other.closedReason == closedReason)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,shopId,productId,quantity,buyingPrice,receivedOn,expiryDate,expiredQty,pickedQty,closedAt,closedReason,createdAt);

@override
String toString() {
  return 'ProductBatch(id: $id, shopId: $shopId, productId: $productId, quantity: $quantity, buyingPrice: $buyingPrice, receivedOn: $receivedOn, expiryDate: $expiryDate, expiredQty: $expiredQty, pickedQty: $pickedQty, closedAt: $closedAt, closedReason: $closedReason, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class $ProductBatchCopyWith<$Res>  {
  factory $ProductBatchCopyWith(ProductBatch value, $Res Function(ProductBatch) _then) = _$ProductBatchCopyWithImpl;
@useResult
$Res call({
 String id, String shopId, String productId, double quantity, double buyingPrice, DateTime receivedOn, DateTime expiryDate, double? expiredQty, double pickedQty, DateTime? closedAt, String? closedReason, DateTime? createdAt
});




}
/// @nodoc
class _$ProductBatchCopyWithImpl<$Res>
    implements $ProductBatchCopyWith<$Res> {
  _$ProductBatchCopyWithImpl(this._self, this._then);

  final ProductBatch _self;
  final $Res Function(ProductBatch) _then;

/// Create a copy of ProductBatch
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? shopId = null,Object? productId = null,Object? quantity = null,Object? buyingPrice = null,Object? receivedOn = null,Object? expiryDate = null,Object? expiredQty = freezed,Object? pickedQty = null,Object? closedAt = freezed,Object? closedReason = freezed,Object? createdAt = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,shopId: null == shopId ? _self.shopId : shopId // ignore: cast_nullable_to_non_nullable
as String,productId: null == productId ? _self.productId : productId // ignore: cast_nullable_to_non_nullable
as String,quantity: null == quantity ? _self.quantity : quantity // ignore: cast_nullable_to_non_nullable
as double,buyingPrice: null == buyingPrice ? _self.buyingPrice : buyingPrice // ignore: cast_nullable_to_non_nullable
as double,receivedOn: null == receivedOn ? _self.receivedOn : receivedOn // ignore: cast_nullable_to_non_nullable
as DateTime,expiryDate: null == expiryDate ? _self.expiryDate : expiryDate // ignore: cast_nullable_to_non_nullable
as DateTime,expiredQty: freezed == expiredQty ? _self.expiredQty : expiredQty // ignore: cast_nullable_to_non_nullable
as double?,pickedQty: null == pickedQty ? _self.pickedQty : pickedQty // ignore: cast_nullable_to_non_nullable
as double,closedAt: freezed == closedAt ? _self.closedAt : closedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,closedReason: freezed == closedReason ? _self.closedReason : closedReason // ignore: cast_nullable_to_non_nullable
as String?,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [ProductBatch].
extension ProductBatchPatterns on ProductBatch {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProductBatch value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProductBatch() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProductBatch value)  $default,){
final _that = this;
switch (_that) {
case _ProductBatch():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProductBatch value)?  $default,){
final _that = this;
switch (_that) {
case _ProductBatch() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String shopId,  String productId,  double quantity,  double buyingPrice,  DateTime receivedOn,  DateTime expiryDate,  double? expiredQty,  double pickedQty,  DateTime? closedAt,  String? closedReason,  DateTime? createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProductBatch() when $default != null:
return $default(_that.id,_that.shopId,_that.productId,_that.quantity,_that.buyingPrice,_that.receivedOn,_that.expiryDate,_that.expiredQty,_that.pickedQty,_that.closedAt,_that.closedReason,_that.createdAt);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String shopId,  String productId,  double quantity,  double buyingPrice,  DateTime receivedOn,  DateTime expiryDate,  double? expiredQty,  double pickedQty,  DateTime? closedAt,  String? closedReason,  DateTime? createdAt)  $default,) {final _that = this;
switch (_that) {
case _ProductBatch():
return $default(_that.id,_that.shopId,_that.productId,_that.quantity,_that.buyingPrice,_that.receivedOn,_that.expiryDate,_that.expiredQty,_that.pickedQty,_that.closedAt,_that.closedReason,_that.createdAt);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String shopId,  String productId,  double quantity,  double buyingPrice,  DateTime receivedOn,  DateTime expiryDate,  double? expiredQty,  double pickedQty,  DateTime? closedAt,  String? closedReason,  DateTime? createdAt)?  $default,) {final _that = this;
switch (_that) {
case _ProductBatch() when $default != null:
return $default(_that.id,_that.shopId,_that.productId,_that.quantity,_that.buyingPrice,_that.receivedOn,_that.expiryDate,_that.expiredQty,_that.pickedQty,_that.closedAt,_that.closedReason,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ProductBatch extends ProductBatch {
  const _ProductBatch({required this.id, required this.shopId, required this.productId, required this.quantity, this.buyingPrice = 0, required this.receivedOn, required this.expiryDate, this.expiredQty, this.pickedQty = 0, this.closedAt, this.closedReason, this.createdAt}): super._();
  factory _ProductBatch.fromJson(Map<String, dynamic> json) => _$ProductBatchFromJson(json);

@override final  String id;
@override final  String shopId;
@override final  String productId;
@override final  double quantity;
@override@JsonKey() final  double buyingPrice;
@override final  DateTime receivedOn;
@override final  DateTime expiryDate;
@override final  double? expiredQty;
@override@JsonKey() final  double pickedQty;
@override final  DateTime? closedAt;
@override final  String? closedReason;
@override final  DateTime? createdAt;

/// Create a copy of ProductBatch
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProductBatchCopyWith<_ProductBatch> get copyWith => __$ProductBatchCopyWithImpl<_ProductBatch>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ProductBatchToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProductBatch&&(identical(other.id, id) || other.id == id)&&(identical(other.shopId, shopId) || other.shopId == shopId)&&(identical(other.productId, productId) || other.productId == productId)&&(identical(other.quantity, quantity) || other.quantity == quantity)&&(identical(other.buyingPrice, buyingPrice) || other.buyingPrice == buyingPrice)&&(identical(other.receivedOn, receivedOn) || other.receivedOn == receivedOn)&&(identical(other.expiryDate, expiryDate) || other.expiryDate == expiryDate)&&(identical(other.expiredQty, expiredQty) || other.expiredQty == expiredQty)&&(identical(other.pickedQty, pickedQty) || other.pickedQty == pickedQty)&&(identical(other.closedAt, closedAt) || other.closedAt == closedAt)&&(identical(other.closedReason, closedReason) || other.closedReason == closedReason)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,shopId,productId,quantity,buyingPrice,receivedOn,expiryDate,expiredQty,pickedQty,closedAt,closedReason,createdAt);

@override
String toString() {
  return 'ProductBatch(id: $id, shopId: $shopId, productId: $productId, quantity: $quantity, buyingPrice: $buyingPrice, receivedOn: $receivedOn, expiryDate: $expiryDate, expiredQty: $expiredQty, pickedQty: $pickedQty, closedAt: $closedAt, closedReason: $closedReason, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class _$ProductBatchCopyWith<$Res> implements $ProductBatchCopyWith<$Res> {
  factory _$ProductBatchCopyWith(_ProductBatch value, $Res Function(_ProductBatch) _then) = __$ProductBatchCopyWithImpl;
@override @useResult
$Res call({
 String id, String shopId, String productId, double quantity, double buyingPrice, DateTime receivedOn, DateTime expiryDate, double? expiredQty, double pickedQty, DateTime? closedAt, String? closedReason, DateTime? createdAt
});




}
/// @nodoc
class __$ProductBatchCopyWithImpl<$Res>
    implements _$ProductBatchCopyWith<$Res> {
  __$ProductBatchCopyWithImpl(this._self, this._then);

  final _ProductBatch _self;
  final $Res Function(_ProductBatch) _then;

/// Create a copy of ProductBatch
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? shopId = null,Object? productId = null,Object? quantity = null,Object? buyingPrice = null,Object? receivedOn = null,Object? expiryDate = null,Object? expiredQty = freezed,Object? pickedQty = null,Object? closedAt = freezed,Object? closedReason = freezed,Object? createdAt = freezed,}) {
  return _then(_ProductBatch(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,shopId: null == shopId ? _self.shopId : shopId // ignore: cast_nullable_to_non_nullable
as String,productId: null == productId ? _self.productId : productId // ignore: cast_nullable_to_non_nullable
as String,quantity: null == quantity ? _self.quantity : quantity // ignore: cast_nullable_to_non_nullable
as double,buyingPrice: null == buyingPrice ? _self.buyingPrice : buyingPrice // ignore: cast_nullable_to_non_nullable
as double,receivedOn: null == receivedOn ? _self.receivedOn : receivedOn // ignore: cast_nullable_to_non_nullable
as DateTime,expiryDate: null == expiryDate ? _self.expiryDate : expiryDate // ignore: cast_nullable_to_non_nullable
as DateTime,expiredQty: freezed == expiredQty ? _self.expiredQty : expiredQty // ignore: cast_nullable_to_non_nullable
as double?,pickedQty: null == pickedQty ? _self.pickedQty : pickedQty // ignore: cast_nullable_to_non_nullable
as double,closedAt: freezed == closedAt ? _self.closedAt : closedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,closedReason: freezed == closedReason ? _self.closedReason : closedReason // ignore: cast_nullable_to_non_nullable
as String?,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
