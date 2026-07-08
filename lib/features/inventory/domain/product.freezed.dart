// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'product.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Product {

 String get id; String get shopId; String get name; UnitType get unitType; ProductUnit get unit; String? get brand; String? get variant; String? get categoryId; String? get category; double get quantity; double get buyingPrice; double get sellingPrice; double get reorderThreshold; List<String> get imageUrls; DateTime? get createdAt; DateTime? get updatedAt;
/// Create a copy of Product
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProductCopyWith<Product> get copyWith => _$ProductCopyWithImpl<Product>(this as Product, _$identity);

  /// Serializes this Product to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Product&&(identical(other.id, id) || other.id == id)&&(identical(other.shopId, shopId) || other.shopId == shopId)&&(identical(other.name, name) || other.name == name)&&(identical(other.unitType, unitType) || other.unitType == unitType)&&(identical(other.unit, unit) || other.unit == unit)&&(identical(other.brand, brand) || other.brand == brand)&&(identical(other.variant, variant) || other.variant == variant)&&(identical(other.categoryId, categoryId) || other.categoryId == categoryId)&&(identical(other.category, category) || other.category == category)&&(identical(other.quantity, quantity) || other.quantity == quantity)&&(identical(other.buyingPrice, buyingPrice) || other.buyingPrice == buyingPrice)&&(identical(other.sellingPrice, sellingPrice) || other.sellingPrice == sellingPrice)&&(identical(other.reorderThreshold, reorderThreshold) || other.reorderThreshold == reorderThreshold)&&const DeepCollectionEquality().equals(other.imageUrls, imageUrls)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,shopId,name,unitType,unit,brand,variant,categoryId,category,quantity,buyingPrice,sellingPrice,reorderThreshold,const DeepCollectionEquality().hash(imageUrls),createdAt,updatedAt);

@override
String toString() {
  return 'Product(id: $id, shopId: $shopId, name: $name, unitType: $unitType, unit: $unit, brand: $brand, variant: $variant, categoryId: $categoryId, category: $category, quantity: $quantity, buyingPrice: $buyingPrice, sellingPrice: $sellingPrice, reorderThreshold: $reorderThreshold, imageUrls: $imageUrls, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $ProductCopyWith<$Res>  {
  factory $ProductCopyWith(Product value, $Res Function(Product) _then) = _$ProductCopyWithImpl;
@useResult
$Res call({
 String id, String shopId, String name, UnitType unitType, ProductUnit unit, String? brand, String? variant, String? categoryId, String? category, double quantity, double buyingPrice, double sellingPrice, double reorderThreshold, List<String> imageUrls, DateTime? createdAt, DateTime? updatedAt
});




}
/// @nodoc
class _$ProductCopyWithImpl<$Res>
    implements $ProductCopyWith<$Res> {
  _$ProductCopyWithImpl(this._self, this._then);

  final Product _self;
  final $Res Function(Product) _then;

/// Create a copy of Product
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? shopId = null,Object? name = null,Object? unitType = null,Object? unit = null,Object? brand = freezed,Object? variant = freezed,Object? categoryId = freezed,Object? category = freezed,Object? quantity = null,Object? buyingPrice = null,Object? sellingPrice = null,Object? reorderThreshold = null,Object? imageUrls = null,Object? createdAt = freezed,Object? updatedAt = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,shopId: null == shopId ? _self.shopId : shopId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,unitType: null == unitType ? _self.unitType : unitType // ignore: cast_nullable_to_non_nullable
as UnitType,unit: null == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as ProductUnit,brand: freezed == brand ? _self.brand : brand // ignore: cast_nullable_to_non_nullable
as String?,variant: freezed == variant ? _self.variant : variant // ignore: cast_nullable_to_non_nullable
as String?,categoryId: freezed == categoryId ? _self.categoryId : categoryId // ignore: cast_nullable_to_non_nullable
as String?,category: freezed == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String?,quantity: null == quantity ? _self.quantity : quantity // ignore: cast_nullable_to_non_nullable
as double,buyingPrice: null == buyingPrice ? _self.buyingPrice : buyingPrice // ignore: cast_nullable_to_non_nullable
as double,sellingPrice: null == sellingPrice ? _self.sellingPrice : sellingPrice // ignore: cast_nullable_to_non_nullable
as double,reorderThreshold: null == reorderThreshold ? _self.reorderThreshold : reorderThreshold // ignore: cast_nullable_to_non_nullable
as double,imageUrls: null == imageUrls ? _self.imageUrls : imageUrls // ignore: cast_nullable_to_non_nullable
as List<String>,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [Product].
extension ProductPatterns on Product {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Product value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Product() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Product value)  $default,){
final _that = this;
switch (_that) {
case _Product():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Product value)?  $default,){
final _that = this;
switch (_that) {
case _Product() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String shopId,  String name,  UnitType unitType,  ProductUnit unit,  String? brand,  String? variant,  String? categoryId,  String? category,  double quantity,  double buyingPrice,  double sellingPrice,  double reorderThreshold,  List<String> imageUrls,  DateTime? createdAt,  DateTime? updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Product() when $default != null:
return $default(_that.id,_that.shopId,_that.name,_that.unitType,_that.unit,_that.brand,_that.variant,_that.categoryId,_that.category,_that.quantity,_that.buyingPrice,_that.sellingPrice,_that.reorderThreshold,_that.imageUrls,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String shopId,  String name,  UnitType unitType,  ProductUnit unit,  String? brand,  String? variant,  String? categoryId,  String? category,  double quantity,  double buyingPrice,  double sellingPrice,  double reorderThreshold,  List<String> imageUrls,  DateTime? createdAt,  DateTime? updatedAt)  $default,) {final _that = this;
switch (_that) {
case _Product():
return $default(_that.id,_that.shopId,_that.name,_that.unitType,_that.unit,_that.brand,_that.variant,_that.categoryId,_that.category,_that.quantity,_that.buyingPrice,_that.sellingPrice,_that.reorderThreshold,_that.imageUrls,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String shopId,  String name,  UnitType unitType,  ProductUnit unit,  String? brand,  String? variant,  String? categoryId,  String? category,  double quantity,  double buyingPrice,  double sellingPrice,  double reorderThreshold,  List<String> imageUrls,  DateTime? createdAt,  DateTime? updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _Product() when $default != null:
return $default(_that.id,_that.shopId,_that.name,_that.unitType,_that.unit,_that.brand,_that.variant,_that.categoryId,_that.category,_that.quantity,_that.buyingPrice,_that.sellingPrice,_that.reorderThreshold,_that.imageUrls,_that.createdAt,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Product extends Product {
  const _Product({required this.id, required this.shopId, required this.name, this.unitType = UnitType.piece, this.unit = ProductUnit.pcs, this.brand, this.variant, this.categoryId, this.category, this.quantity = 0, this.buyingPrice = 0, this.sellingPrice = 0, this.reorderThreshold = 0, final  List<String> imageUrls = const <String>[], this.createdAt, this.updatedAt}): _imageUrls = imageUrls,super._();
  factory _Product.fromJson(Map<String, dynamic> json) => _$ProductFromJson(json);

@override final  String id;
@override final  String shopId;
@override final  String name;
@override@JsonKey() final  UnitType unitType;
@override@JsonKey() final  ProductUnit unit;
@override final  String? brand;
@override final  String? variant;
@override final  String? categoryId;
@override final  String? category;
@override@JsonKey() final  double quantity;
@override@JsonKey() final  double buyingPrice;
@override@JsonKey() final  double sellingPrice;
@override@JsonKey() final  double reorderThreshold;
 final  List<String> _imageUrls;
@override@JsonKey() List<String> get imageUrls {
  if (_imageUrls is EqualUnmodifiableListView) return _imageUrls;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_imageUrls);
}

@override final  DateTime? createdAt;
@override final  DateTime? updatedAt;

/// Create a copy of Product
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProductCopyWith<_Product> get copyWith => __$ProductCopyWithImpl<_Product>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ProductToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Product&&(identical(other.id, id) || other.id == id)&&(identical(other.shopId, shopId) || other.shopId == shopId)&&(identical(other.name, name) || other.name == name)&&(identical(other.unitType, unitType) || other.unitType == unitType)&&(identical(other.unit, unit) || other.unit == unit)&&(identical(other.brand, brand) || other.brand == brand)&&(identical(other.variant, variant) || other.variant == variant)&&(identical(other.categoryId, categoryId) || other.categoryId == categoryId)&&(identical(other.category, category) || other.category == category)&&(identical(other.quantity, quantity) || other.quantity == quantity)&&(identical(other.buyingPrice, buyingPrice) || other.buyingPrice == buyingPrice)&&(identical(other.sellingPrice, sellingPrice) || other.sellingPrice == sellingPrice)&&(identical(other.reorderThreshold, reorderThreshold) || other.reorderThreshold == reorderThreshold)&&const DeepCollectionEquality().equals(other._imageUrls, _imageUrls)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,shopId,name,unitType,unit,brand,variant,categoryId,category,quantity,buyingPrice,sellingPrice,reorderThreshold,const DeepCollectionEquality().hash(_imageUrls),createdAt,updatedAt);

@override
String toString() {
  return 'Product(id: $id, shopId: $shopId, name: $name, unitType: $unitType, unit: $unit, brand: $brand, variant: $variant, categoryId: $categoryId, category: $category, quantity: $quantity, buyingPrice: $buyingPrice, sellingPrice: $sellingPrice, reorderThreshold: $reorderThreshold, imageUrls: $imageUrls, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$ProductCopyWith<$Res> implements $ProductCopyWith<$Res> {
  factory _$ProductCopyWith(_Product value, $Res Function(_Product) _then) = __$ProductCopyWithImpl;
@override @useResult
$Res call({
 String id, String shopId, String name, UnitType unitType, ProductUnit unit, String? brand, String? variant, String? categoryId, String? category, double quantity, double buyingPrice, double sellingPrice, double reorderThreshold, List<String> imageUrls, DateTime? createdAt, DateTime? updatedAt
});




}
/// @nodoc
class __$ProductCopyWithImpl<$Res>
    implements _$ProductCopyWith<$Res> {
  __$ProductCopyWithImpl(this._self, this._then);

  final _Product _self;
  final $Res Function(_Product) _then;

/// Create a copy of Product
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? shopId = null,Object? name = null,Object? unitType = null,Object? unit = null,Object? brand = freezed,Object? variant = freezed,Object? categoryId = freezed,Object? category = freezed,Object? quantity = null,Object? buyingPrice = null,Object? sellingPrice = null,Object? reorderThreshold = null,Object? imageUrls = null,Object? createdAt = freezed,Object? updatedAt = freezed,}) {
  return _then(_Product(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,shopId: null == shopId ? _self.shopId : shopId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,unitType: null == unitType ? _self.unitType : unitType // ignore: cast_nullable_to_non_nullable
as UnitType,unit: null == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as ProductUnit,brand: freezed == brand ? _self.brand : brand // ignore: cast_nullable_to_non_nullable
as String?,variant: freezed == variant ? _self.variant : variant // ignore: cast_nullable_to_non_nullable
as String?,categoryId: freezed == categoryId ? _self.categoryId : categoryId // ignore: cast_nullable_to_non_nullable
as String?,category: freezed == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String?,quantity: null == quantity ? _self.quantity : quantity // ignore: cast_nullable_to_non_nullable
as double,buyingPrice: null == buyingPrice ? _self.buyingPrice : buyingPrice // ignore: cast_nullable_to_non_nullable
as double,sellingPrice: null == sellingPrice ? _self.sellingPrice : sellingPrice // ignore: cast_nullable_to_non_nullable
as double,reorderThreshold: null == reorderThreshold ? _self.reorderThreshold : reorderThreshold // ignore: cast_nullable_to_non_nullable
as double,imageUrls: null == imageUrls ? _self._imageUrls : imageUrls // ignore: cast_nullable_to_non_nullable
as List<String>,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
