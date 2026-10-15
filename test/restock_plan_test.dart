import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/restock/domain/restock_plan.dart';
import 'package:flutter_test/flutter_test.dart';

Product _p(String id, {double qty = 0, UnitType unit = UnitType.piece}) =>
    Product(id: id, shopId: 's', name: id, quantity: qty, unitType: unit);

RestockPlan _plan(
  List<Product> products,
  Map<String, RestockSpeed> speeds, {
  int days = 7,
}) => planRestock(
  products: products,
  speeds: speeds,
  goodStock: (p) => p.quantity,
  restockDays: days,
);

RestockSpeed _s(String id, double speed, [double? w0]) =>
    RestockSpeed(productId: id, speed: speed, week0Rate: w0);

void main() {
  test('spec §3.6 Mojo: 5/day, 10 in stock, every 7 days → buy 35', () {
    final plan = _plan([_p('Mojo', qty: 10)], {'Mojo': _s('Mojo', 5, 8)});
    final m = plan.buyNow.single;
    expect(m.daysLeft, 2);
    expect(m.suggestion, 35);
    expect(m.trend, RestockTrend.up);
  });

  test('a float just over a whole number does not round up', () {
    // 5 × 9 − 10 may come out as 35.000000000004.
    final plan = _plan([_p('A', qty: 10)], {'A': _s('A', 5.0000000000004)});
    expect(plan.buyNow.single.suggestion, 35);
  });

  test('trend thresholds: >1.2× up, <0.8× down, else and null flat', () {
    RestockTrend t(double? w0) =>
        _plan([_p('A', qty: 0)], {'A': _s('A', 10, w0)}).buyNow.single.trend;
    expect(t(12.1), RestockTrend.up);
    expect(t(12), RestockTrend.flat);
    expect(t(8), RestockTrend.flat);
    expect(t(7.9), RestockTrend.down);
    expect(t(null), RestockTrend.flat);
  });

  test('zero good stock: days left 0 and the full period is suggested', () {
    final item = _plan([_p('A')], {'A': _s('A', 2)}).buyNow.single;
    expect(item.daysLeft, 0);
    expect(item.suggestion, 18);
  });

  test('negative stock is treated as zero', () {
    final item = _plan([_p('A', qty: -3)], {'A': _s('A', 1)}).buyNow.single;
    expect(item.goodStock, 0);
    expect(item.suggestion, 9);
  });

  test('suggestion of exactly 1 is Buy now; 0 or less is Enough', () {
    final plan = _plan(
      [_p('One', qty: 8), _p('Zero', qty: 9), _p('Over', qty: 50)],
      {'One': _s('One', 1), 'Zero': _s('Zero', 1), 'Over': _s('Over', 1)},
    );
    expect(plan.buyNow.map((i) => i.product.id), ['One']);
    expect(plan.enough.map((i) => i.product.id), ['Zero', 'Over']);
    expect(plan.enough.first.suggestion, 0);
  });

  test('ordered by days left, ties by name', () {
    final plan = _plan(
      [_p('b', qty: 2), _p('a', qty: 2), _p('c', qty: 1)],
      {'a': _s('a', 1), 'b': _s('b', 1), 'c': _s('c', 1)},
    );
    expect(plan.buyNow.map((i) => i.product.id), ['c', 'a', 'b']);
  });

  test('speed 0 or no speed row: not planned', () {
    final plan = _plan([_p('A', qty: 1), _p('B', qty: 1)], {'A': _s('A', 0)});
    expect(plan.buyNow, isEmpty);
    expect(plan.enough, isEmpty);
  });

  test('decimal units: suggestion rounds up to a whole unit', () {
    final plan = _plan(
      [_p('Rice', qty: 1.5, unit: UnitType.weight)],
      {'Rice': _s('Rice', 0.75)},
    );
    // 0.75 × 9 − 1.5 = 5.25 → 6
    expect(plan.buyNow.single.suggestion, 6);
    expect(plan.buyNow.single.daysLeft, 2);
  });

  test('restock days changes the cover', () {
    final plan = _plan([_p('A', qty: 0)], {'A': _s('A', 1)}, days: 3);
    expect(plan.buyNow.single.suggestion, 5);
  });

  test('RestockSpeed.fromMap reads numerics as num or string', () {
    final s = RestockSpeed.fromMap({
      'product_id': 'p1',
      'speed': '2.5',
      'week0_rate': null,
    });
    expect(s.productId, 'p1');
    expect(s.speed, 2.5);
    expect(s.week0Rate, isNull);
    expect(
      RestockSpeed.fromMap({
        'product_id': 'p2',
        'speed': 3,
        'week0_rate': 4,
      }).week0Rate,
      4,
    );
  });
}
