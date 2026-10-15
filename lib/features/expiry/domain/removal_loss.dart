/// What a product has lost to stock taken off the shelf: every removal
/// (expired, thrown away or returned) at the buying price it was recorded at.
///
/// Read from the `adjustment` rows that 0011/0013/0014/0015 write -- nothing
/// else writes that type -- so partial removals and stock with no date count
/// too. Replaced the Closed list, which only said "Removed (expired)" with no
/// amount or money (2026-10-15).
class RemovalLoss {
  const RemovalLoss({required this.units, required this.cost});

  static const none = RemovalLoss(units: 0, cost: 0);

  /// Sums `transactions` rows holding `quantity` and `buying_price`. Postgres
  /// numerics can arrive as int, double or string.
  factory RemovalLoss.fromRows(List<Map<String, dynamic>> rows) {
    var units = 0.0;
    var cost = 0.0;
    for (final r in rows) {
      final qty = _num(r['quantity']);
      units += qty;
      cost += qty * _num(r['buying_price']);
    }
    return RemovalLoss(units: units, cost: cost);
  }

  final double units;
  final double cost;

  bool get isEmpty => units <= 0;

  static double _num(Object? v) => switch (v) {
    final num n => n.toDouble(),
    final String s => double.tryParse(s) ?? 0,
    _ => 0,
  };
}
