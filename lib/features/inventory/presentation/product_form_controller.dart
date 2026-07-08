import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/product.dart';

/// The unit selection for the product form: how the item is sold ([unitType])
/// and the measurement [unit]. The form watches this so its field set rebuilds
/// when the selling mode changes (brand/variant show/hide, decimal vs. whole
/// stock, price-label suffixes).
class ProductFormUnit {
  const ProductFormUnit(this.unitType, this.unit);

  final UnitType unitType;
  final ProductUnit unit;
}

class ProductFormUnitController extends Notifier<ProductFormUnit> {
  @override
  ProductFormUnit build() =>
      const ProductFormUnit(UnitType.piece, ProductUnit.pcs);

  /// Seed from an existing product when editing (call once in initState).
  void seed(UnitType type, ProductUnit unit) =>
      state = ProductFormUnit(type, unit);

  /// Switch selling mode; the unit resets to that mode's default so an invalid
  /// pairing (e.g. weight + 'pcs') can never occur.
  void selectType(UnitType type) =>
      state = ProductFormUnit(type, type.defaultUnit);

  /// Change only the measurement unit within the current mode.
  void selectUnit(ProductUnit unit) =>
      state = ProductFormUnit(state.unitType, unit);
}

/// AutoDispose so each time the form opens it starts fresh (then seeds from the
/// edited product, if any).
final productFormUnitProvider =
    NotifierProvider.autoDispose<ProductFormUnitController, ProductFormUnit>(
      ProductFormUnitController.new,
    );
