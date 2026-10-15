import 'dart:math' as math;

import '../../inventory/domain/product.dart';

/// Days of stock added on top of the restock period, to cover a late trip
/// (spec §3.4).
const restockBufferDays = 2;

/// One product's speed from `get_restock_speeds` (0017).
class RestockSpeed {
  const RestockSpeed({
    required this.productId,
    required this.speed,
    this.week0Rate,
  });

  factory RestockSpeed.fromMap(Map<String, dynamic> m) => RestockSpeed(
    productId: m['product_id'] as String,
    speed: _num(m['speed']) ?? 0,
    week0Rate: _num(m['week0_rate']),
  );

  final String productId;

  /// Units per in-stock day, weeks weighted 0.4/0.3/0.2/0.1.
  final double speed;

  /// Last week's units per in-stock day; null when it had no in-stock day.
  final double? week0Rate;

  static double? _num(Object? v) => switch (v) {
    final num n => n.toDouble(),
    final String s => double.tryParse(s),
    _ => null,
  };
}

enum RestockTrend { up, down, flat }

class RestockItem {
  const RestockItem({
    required this.product,
    required this.speed,
    required this.goodStock,
    required this.daysLeft,
    required this.suggestion,
    required this.trend,
    this.belowReorder = false,
  });

  final Product product;

  /// Units per day; 0 for a product listed only by its reorder level.
  final double speed;
  final double goodStock;

  /// Infinite when [speed] is 0: no sales to run out by.
  final double daysLeft;

  /// Whole units to buy; 0 when there is enough.
  final double suggestion;
  final RestockTrend trend;

  /// At or below the reorder level the shopkeeper set on the product.
  final bool belowReorder;

  /// Red: runs out within 2 whole days. Whole days because that is what the
  /// text shows -- 2.5 days reads "Runs out in 2 days" and must be red too.
  bool get isUrgent => daysLeft < 3;
}

class RestockPlan {
  const RestockPlan({required this.buyNow, required this.enough});

  static const empty = RestockPlan(buyNow: [], enough: []);

  final List<RestockItem> buyNow;
  final List<RestockItem> enough;

  bool get isEmpty => buyNow.isEmpty && enough.isEmpty;
}

/// Spec §3.4–3.5, plus the reorder level the old Home "Low stock" card used
/// (merged 2026-10-15, spec §10): a product at or below its level is always
/// Buy now, with at least enough to get back above it -- even with no sales,
/// so "keep 5 on the shelf" items are not lost. Anything else without a speed
/// above zero is left out: there is nothing to plan from.
RestockPlan planRestock({
  required List<Product> products,
  required Map<String, RestockSpeed> speeds,
  required double Function(Product) goodStock,
  required int restockDays,
}) {
  final items = <RestockItem>[];
  for (final p in products) {
    final speed = math.max(0.0, speeds[p.id]?.speed ?? 0);
    final good = math.max(0.0, goodStock(p));
    final low = p.isLowStockAt(good);
    if (speed <= 0 && !low) continue;
    final raw = speed * (restockDays + restockBufferDays) - good;
    // 1e-9: 5 × 9 − 10 can come out a hair over 35 and must not become 36.
    var suggestion = math.max(0, (raw - 1e-9).ceil()).toDouble();
    if (low) {
      final backAbove = (p.reorderThreshold - good - 1e-9).ceil() + 1;
      suggestion = math.max(suggestion, backAbove.toDouble());
    }
    final w0 = speeds[p.id]?.week0Rate;
    final trend = speed <= 0 || w0 == null
        ? RestockTrend.flat
        : w0 > 1.2 * speed
        ? RestockTrend.up
        : w0 < 0.8 * speed
        ? RestockTrend.down
        : RestockTrend.flat;
    items.add(
      RestockItem(
        product: p,
        speed: speed,
        goodStock: good,
        daysLeft: speed > 0 ? good / speed : double.infinity,
        suggestion: suggestion,
        trend: trend,
        belowReorder: low,
      ),
    );
  }
  items.sort((a, b) {
    final c = a.daysLeft.compareTo(b.daysLeft);
    if (c != 0) return c;
    return a.product.name.toLowerCase().compareTo(b.product.name.toLowerCase());
  });
  return RestockPlan(
    buyNow: [
      for (final i in items)
        if (i.suggestion >= 1) i,
    ],
    enough: [
      for (final i in items)
        if (i.suggestion < 1) i,
    ],
  );
}
