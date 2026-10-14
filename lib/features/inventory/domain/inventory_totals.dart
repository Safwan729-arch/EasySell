import '../../expiry/domain/expiry_estimate.dart';
import 'product.dart';

/// Whole-inventory figures behind the `N items · value` line on the Items
/// screen, computed from the already-loaded product list — no extra query.
///
/// Deliberately omits a total unit count: stock mixes kilograms, litres and
/// pieces, and adding those together produces a number that means nothing. The
/// history screen refuses the same sum for the same reason.
class InventoryTotals {
  const InventoryTotals({
    required this.productCount,
    required this.costValue,
    required this.retailValue,
    required this.lowStockCount,
  });

  /// Distinct products in stock (not units).
  final int productCount;

  /// What the current stock cost to buy — the headline "inventory value".
  final double costValue;

  /// What the current stock would bring in at today's selling prices.
  final double retailValue;

  final int lowStockCount;

  /// Margin locked up in stock: what selling all of it at today's prices would
  /// earn over what it cost. Not a forecast — stock rarely sells out, and prices
  /// move — which is why the sheet labels it "potential".
  double get potentialProfit => retailValue - costValue;

  /// [expiry] (the estimate map) makes low stock judge GOOD stock, so 5
  /// expired + 1 good counts as low (expiry spec §5).
  static InventoryTotals of(
    List<Product> products, {
    Map<String, ProductExpiry> expiry = const {},
  }) {
    var cost = 0.0;
    var retail = 0.0;
    var low = 0;
    for (final p in products) {
      cost += p.inventoryValue;
      retail += p.sellingPrice * p.quantity;
      if (p.isLowStockAt(goodStockOf(p, expiry))) low++;
    }
    return InventoryTotals(
      productCount: products.length,
      costValue: cost,
      retailValue: retail,
      lowStockCount: low,
    );
  }
}
