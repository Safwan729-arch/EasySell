// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'transaction.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Transaction {

 String get id; String get shopId; String get productId; String get type; double get quantity; double get buyingPrice; double get sellingPrice;/// This line's share of a cart-level discount, allocated by
/// `record_sale_cart`. Summing it over a `saleGroupId` reproduces the
/// discount the shopkeeper typed, exactly -- the split floors and then
/// hands the remainder out a paisa at a time, so nothing is lost to
/// rounding and the receipt total never needs storing separately.
 double get discountAmount; String? get source; String? get saleGroupId;/// The delivery this sale line was taken from (0012). Null for undated
/// stock and for sales made before deliveries were tracked.
 String? get batchId;/// That delivery's expiry date, read from the embedded
/// `batch:product_batches(expiry_date)` History selects. Display only:
/// never written back, since it is not a column of `transactions`.
@JsonKey(readValue: _readBatchExpiry, includeToJson: false) DateTime? get batchExpiry; DateTime? get createdAt;
/// Create a copy of Transaction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TransactionCopyWith<Transaction> get copyWith => _$TransactionCopyWithImpl<Transaction>(this as Transaction, _$identity);

  /// Serializes this Transaction to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Transaction&&(identical(other.id, id) || other.id == id)&&(identical(other.shopId, shopId) || other.shopId == shopId)&&(identical(other.productId, productId) || other.productId == productId)&&(identical(other.type, type) || other.type == type)&&(identical(other.quantity, quantity) || other.quantity == quantity)&&(identical(other.buyingPrice, buyingPrice) || other.buyingPrice == buyingPrice)&&(identical(other.sellingPrice, sellingPrice) || other.sellingPrice == sellingPrice)&&(identical(other.discountAmount, discountAmount) || other.discountAmount == discountAmount)&&(identical(other.source, source) || other.source == source)&&(identical(other.saleGroupId, saleGroupId) || other.saleGroupId == saleGroupId)&&(identical(other.batchId, batchId) || other.batchId == batchId)&&(identical(other.batchExpiry, batchExpiry) || other.batchExpiry == batchExpiry)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,shopId,productId,type,quantity,buyingPrice,sellingPrice,discountAmount,source,saleGroupId,batchId,batchExpiry,createdAt);

@override
String toString() {
  return 'Transaction(id: $id, shopId: $shopId, productId: $productId, type: $type, quantity: $quantity, buyingPrice: $buyingPrice, sellingPrice: $sellingPrice, discountAmount: $discountAmount, source: $source, saleGroupId: $saleGroupId, batchId: $batchId, batchExpiry: $batchExpiry, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class $TransactionCopyWith<$Res>  {
  factory $TransactionCopyWith(Transaction value, $Res Function(Transaction) _then) = _$TransactionCopyWithImpl;
@useResult
$Res call({
 String id, String shopId, String productId, String type, double quantity, double buyingPrice, double sellingPrice, double discountAmount, String? source, String? saleGroupId, String? batchId,@JsonKey(readValue: _readBatchExpiry, includeToJson: false) DateTime? batchExpiry, DateTime? createdAt
});




}
/// @nodoc
class _$TransactionCopyWithImpl<$Res>
    implements $TransactionCopyWith<$Res> {
  _$TransactionCopyWithImpl(this._self, this._then);

  final Transaction _self;
  final $Res Function(Transaction) _then;

/// Create a copy of Transaction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? shopId = null,Object? productId = null,Object? type = null,Object? quantity = null,Object? buyingPrice = null,Object? sellingPrice = null,Object? discountAmount = null,Object? source = freezed,Object? saleGroupId = freezed,Object? batchId = freezed,Object? batchExpiry = freezed,Object? createdAt = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,shopId: null == shopId ? _self.shopId : shopId // ignore: cast_nullable_to_non_nullable
as String,productId: null == productId ? _self.productId : productId // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,quantity: null == quantity ? _self.quantity : quantity // ignore: cast_nullable_to_non_nullable
as double,buyingPrice: null == buyingPrice ? _self.buyingPrice : buyingPrice // ignore: cast_nullable_to_non_nullable
as double,sellingPrice: null == sellingPrice ? _self.sellingPrice : sellingPrice // ignore: cast_nullable_to_non_nullable
as double,discountAmount: null == discountAmount ? _self.discountAmount : discountAmount // ignore: cast_nullable_to_non_nullable
as double,source: freezed == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String?,saleGroupId: freezed == saleGroupId ? _self.saleGroupId : saleGroupId // ignore: cast_nullable_to_non_nullable
as String?,batchId: freezed == batchId ? _self.batchId : batchId // ignore: cast_nullable_to_non_nullable
as String?,batchExpiry: freezed == batchExpiry ? _self.batchExpiry : batchExpiry // ignore: cast_nullable_to_non_nullable
as DateTime?,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [Transaction].
extension TransactionPatterns on Transaction {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Transaction value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Transaction() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Transaction value)  $default,){
final _that = this;
switch (_that) {
case _Transaction():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Transaction value)?  $default,){
final _that = this;
switch (_that) {
case _Transaction() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String shopId,  String productId,  String type,  double quantity,  double buyingPrice,  double sellingPrice,  double discountAmount,  String? source,  String? saleGroupId,  String? batchId, @JsonKey(readValue: _readBatchExpiry, includeToJson: false)  DateTime? batchExpiry,  DateTime? createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Transaction() when $default != null:
return $default(_that.id,_that.shopId,_that.productId,_that.type,_that.quantity,_that.buyingPrice,_that.sellingPrice,_that.discountAmount,_that.source,_that.saleGroupId,_that.batchId,_that.batchExpiry,_that.createdAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String shopId,  String productId,  String type,  double quantity,  double buyingPrice,  double sellingPrice,  double discountAmount,  String? source,  String? saleGroupId,  String? batchId, @JsonKey(readValue: _readBatchExpiry, includeToJson: false)  DateTime? batchExpiry,  DateTime? createdAt)  $default,) {final _that = this;
switch (_that) {
case _Transaction():
return $default(_that.id,_that.shopId,_that.productId,_that.type,_that.quantity,_that.buyingPrice,_that.sellingPrice,_that.discountAmount,_that.source,_that.saleGroupId,_that.batchId,_that.batchExpiry,_that.createdAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String shopId,  String productId,  String type,  double quantity,  double buyingPrice,  double sellingPrice,  double discountAmount,  String? source,  String? saleGroupId,  String? batchId, @JsonKey(readValue: _readBatchExpiry, includeToJson: false)  DateTime? batchExpiry,  DateTime? createdAt)?  $default,) {final _that = this;
switch (_that) {
case _Transaction() when $default != null:
return $default(_that.id,_that.shopId,_that.productId,_that.type,_that.quantity,_that.buyingPrice,_that.sellingPrice,_that.discountAmount,_that.source,_that.saleGroupId,_that.batchId,_that.batchExpiry,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Transaction extends Transaction {
  const _Transaction({required this.id, required this.shopId, required this.productId, required this.type, required this.quantity, this.buyingPrice = 0, this.sellingPrice = 0, this.discountAmount = 0, this.source, this.saleGroupId, this.batchId, @JsonKey(readValue: _readBatchExpiry, includeToJson: false) this.batchExpiry, this.createdAt}): super._();
  factory _Transaction.fromJson(Map<String, dynamic> json) => _$TransactionFromJson(json);

@override final  String id;
@override final  String shopId;
@override final  String productId;
@override final  String type;
@override final  double quantity;
@override@JsonKey() final  double buyingPrice;
@override@JsonKey() final  double sellingPrice;
/// This line's share of a cart-level discount, allocated by
/// `record_sale_cart`. Summing it over a `saleGroupId` reproduces the
/// discount the shopkeeper typed, exactly -- the split floors and then
/// hands the remainder out a paisa at a time, so nothing is lost to
/// rounding and the receipt total never needs storing separately.
@override@JsonKey() final  double discountAmount;
@override final  String? source;
@override final  String? saleGroupId;
/// The delivery this sale line was taken from (0012). Null for undated
/// stock and for sales made before deliveries were tracked.
@override final  String? batchId;
/// That delivery's expiry date, read from the embedded
/// `batch:product_batches(expiry_date)` History selects. Display only:
/// never written back, since it is not a column of `transactions`.
@override@JsonKey(readValue: _readBatchExpiry, includeToJson: false) final  DateTime? batchExpiry;
@override final  DateTime? createdAt;

/// Create a copy of Transaction
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TransactionCopyWith<_Transaction> get copyWith => __$TransactionCopyWithImpl<_Transaction>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TransactionToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Transaction&&(identical(other.id, id) || other.id == id)&&(identical(other.shopId, shopId) || other.shopId == shopId)&&(identical(other.productId, productId) || other.productId == productId)&&(identical(other.type, type) || other.type == type)&&(identical(other.quantity, quantity) || other.quantity == quantity)&&(identical(other.buyingPrice, buyingPrice) || other.buyingPrice == buyingPrice)&&(identical(other.sellingPrice, sellingPrice) || other.sellingPrice == sellingPrice)&&(identical(other.discountAmount, discountAmount) || other.discountAmount == discountAmount)&&(identical(other.source, source) || other.source == source)&&(identical(other.saleGroupId, saleGroupId) || other.saleGroupId == saleGroupId)&&(identical(other.batchId, batchId) || other.batchId == batchId)&&(identical(other.batchExpiry, batchExpiry) || other.batchExpiry == batchExpiry)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,shopId,productId,type,quantity,buyingPrice,sellingPrice,discountAmount,source,saleGroupId,batchId,batchExpiry,createdAt);

@override
String toString() {
  return 'Transaction(id: $id, shopId: $shopId, productId: $productId, type: $type, quantity: $quantity, buyingPrice: $buyingPrice, sellingPrice: $sellingPrice, discountAmount: $discountAmount, source: $source, saleGroupId: $saleGroupId, batchId: $batchId, batchExpiry: $batchExpiry, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class _$TransactionCopyWith<$Res> implements $TransactionCopyWith<$Res> {
  factory _$TransactionCopyWith(_Transaction value, $Res Function(_Transaction) _then) = __$TransactionCopyWithImpl;
@override @useResult
$Res call({
 String id, String shopId, String productId, String type, double quantity, double buyingPrice, double sellingPrice, double discountAmount, String? source, String? saleGroupId, String? batchId,@JsonKey(readValue: _readBatchExpiry, includeToJson: false) DateTime? batchExpiry, DateTime? createdAt
});




}
/// @nodoc
class __$TransactionCopyWithImpl<$Res>
    implements _$TransactionCopyWith<$Res> {
  __$TransactionCopyWithImpl(this._self, this._then);

  final _Transaction _self;
  final $Res Function(_Transaction) _then;

/// Create a copy of Transaction
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? shopId = null,Object? productId = null,Object? type = null,Object? quantity = null,Object? buyingPrice = null,Object? sellingPrice = null,Object? discountAmount = null,Object? source = freezed,Object? saleGroupId = freezed,Object? batchId = freezed,Object? batchExpiry = freezed,Object? createdAt = freezed,}) {
  return _then(_Transaction(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,shopId: null == shopId ? _self.shopId : shopId // ignore: cast_nullable_to_non_nullable
as String,productId: null == productId ? _self.productId : productId // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,quantity: null == quantity ? _self.quantity : quantity // ignore: cast_nullable_to_non_nullable
as double,buyingPrice: null == buyingPrice ? _self.buyingPrice : buyingPrice // ignore: cast_nullable_to_non_nullable
as double,sellingPrice: null == sellingPrice ? _self.sellingPrice : sellingPrice // ignore: cast_nullable_to_non_nullable
as double,discountAmount: null == discountAmount ? _self.discountAmount : discountAmount // ignore: cast_nullable_to_non_nullable
as double,source: freezed == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String?,saleGroupId: freezed == saleGroupId ? _self.saleGroupId : saleGroupId // ignore: cast_nullable_to_non_nullable
as String?,batchId: freezed == batchId ? _self.batchId : batchId // ignore: cast_nullable_to_non_nullable
as String?,batchExpiry: freezed == batchExpiry ? _self.batchExpiry : batchExpiry // ignore: cast_nullable_to_non_nullable
as DateTime?,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
