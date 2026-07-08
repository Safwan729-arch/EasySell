import 'package:freezed_annotation/freezed_annotation.dart';

part 'product.freezed.dart';
part 'product.g.dart';

/// How a product is stocked, priced, and sold (CLAUDE.md inventory redesign).
/// Serialized by name to the `products.unit_type` column ('piece'/'weight'/'volume').
enum UnitType { piece, weight, volume }

/// The measurement unit for a product. Serialized by name to `products.unit`.
enum ProductUnit { pcs, kg, g, litre, ml }

extension UnitTypeX on UnitType {
  /// Segmented-control label.
  String get label => switch (this) {
    UnitType.piece => 'By piece',
    UnitType.weight => 'By weight',
    UnitType.volume => 'By volume',
  };

  /// One-line hint describing what this selling mode is for.
  String get hint => switch (this) {
    UnitType.piece =>
      'Counted as whole pieces — soap, bottled drinks, packets.',
    UnitType.weight => 'Sold by weight — rice, potato, lentils, sugar.',
    UnitType.volume => 'Sold by volume — loose oil, milk, kerosene.',
  };

  /// Units a user can choose from for this selling mode.
  List<ProductUnit> get units => switch (this) {
    UnitType.piece => const [ProductUnit.pcs],
    UnitType.weight => const [ProductUnit.kg, ProductUnit.g],
    UnitType.volume => const [ProductUnit.litre, ProductUnit.ml],
  };

  /// The default unit when this mode is first selected.
  ProductUnit get defaultUnit => units.first;

  /// Whole pieces don't take decimals; weight/volume do.
  bool get allowsDecimal => this != UnitType.piece;

  /// Brand and variant only make sense for discrete, branded pieces.
  bool get showsBrandVariant => this == UnitType.piece;
}

extension ProductUnitX on ProductUnit {
  /// Short display label ('pcs', 'kg', 'litre', …).
  String get label => switch (this) {
    ProductUnit.pcs => 'pcs',
    ProductUnit.kg => 'kg',
    ProductUnit.g => 'g',
    ProductUnit.litre => 'litre',
    ProductUnit.ml => 'ml',
  };
}

/// A product in a shop's inventory. JSON keys are snake_case (Supabase columns);
/// the mapping is handled by `field_rename: snake` in build.yaml. Enums serialize
/// by name, matching the DB CHECK constraints.
///
/// This is the feature TEMPLATE model — other domain models follow this shape.
@freezed
abstract class Product with _$Product {
  const Product._();

  const factory Product({
    required String id,
    required String shopId,
    required String name,
    // How the item is sold. Drives the adaptive form and unit-aware display.
    @Default(UnitType.piece) UnitType unitType,
    @Default(ProductUnit.pcs) ProductUnit unit,
    // Brand/variant only apply to 'piece' items (kept nullable for all).
    String? brand,
    String? variant,
    // Reusable, shop-scoped category. `category` (free text) is DEPRECATED —
    // retained only to read legacy rows; new writes use `categoryId`.
    String? categoryId,
    // LEGACY free-text category — read-only for old rows; new writes use
    // categoryId. Remove once the deprecated DB column is dropped.
    String? category,
    // Decimal so it holds both 12 (pcs) and 2.5 (kg/litre).
    @Default(0) double quantity,
    // Per-unit prices (per pcs / per kg / per litre …).
    @Default(0) double buyingPrice,
    @Default(0) double sellingPrice,
    // Expressed in the same unit as quantity.
    @Default(0) double reorderThreshold,
    @Default(<String>[]) List<String> imageUrls,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) = _Product;

  factory Product.fromJson(Map<String, dynamic> json) =>
      _$ProductFromJson(json);

  /// At or below the reorder threshold (threshold of 0 disables the alert).
  bool get isLowStock => reorderThreshold > 0 && quantity <= reorderThreshold;

  /// Current stock valued at cost.
  double get inventoryValue => buyingPrice * quantity;

  /// Margin per unit at current prices.
  double get marginPerUnit => sellingPrice - buyingPrice;

  /// Short unit label, e.g. 'kg'.
  String get unitLabel => unit.label;

  /// Quantity with its unit, trailing zeros stripped: "12 pcs", "2.5 kg".
  String get quantityLabel => '${trimNum(quantity)} ${unit.label}';

  /// Reorder threshold with its unit (or empty when disabled).
  String get reorderLabel =>
      reorderThreshold <= 0 ? '' : '${trimNum(reorderThreshold)} ${unit.label}';

  /// Drops a trailing ".0" / trailing zeros for clean display.
  static String trimNum(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toString();
  }

  /// Column payload for INSERT/UPDATE. `id`/`created_at`/`updated_at` are
  /// DB-managed and intentionally omitted. The deprecated free-text `category`
  /// column is no longer written — products are categorized via `category_id`.
  Map<String, dynamic> toRow() => {
    'shop_id': shopId,
    'name': name,
    'unit_type': unitType.name,
    'unit': unit.name,
    'brand': brand,
    'variant': variant,
    'category_id': categoryId,
    'quantity': quantity,
    'buying_price': buyingPrice,
    'selling_price': sellingPrice,
    'reorder_threshold': reorderThreshold,
    'image_urls': imageUrls,
  };
}
