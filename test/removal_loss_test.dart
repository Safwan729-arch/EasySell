import 'package:ai_shopkeeper/features/expiry/domain/removal_loss.dart';
import 'package:flutter_test/flutter_test.dart';

/// The product page's "Thrown away" line replaced the Closed list, which only
/// said "Removed (expired)" with no amount or money (2026-10-15). Removals are
/// the `adjustment` rows 0011/0013/0014/0015 write: units removed at the
/// delivery's (or the product's) buying price.
void main() {
  test('adds up units and cost across every removal', () {
    final loss = RemovalLoss.fromRows([
      {'quantity': 10, 'buying_price': 20},
      {'quantity': 2.5, 'buying_price': '12.00'},
    ]);
    expect(loss.units, 12.5);
    expect(loss.cost, 230);
    expect(loss.isEmpty, isFalse);
  });

  test('no removals is empty, so the line stays hidden', () {
    final loss = RemovalLoss.fromRows(const []);
    expect(loss.units, 0);
    expect(loss.cost, 0);
    expect(loss.isEmpty, isTrue);
  });
}
