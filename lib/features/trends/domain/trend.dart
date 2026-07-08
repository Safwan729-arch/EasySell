/// A trend dataset, WRITTEN BY Member B into the `trend_data` table. Read-only.
///
/// // MEMBER B — proposed contract (flag if yours differs):
/// ```jsonc
/// {
///   "id":        "uuid",
///   "shop_id":   "uuid",
///   "title":     "Top sellers this week",        // required
///   "metric":    "units" | "revenue" | string,   // optional, for labelling
///   "points":    [ {"label": "Pepsi", "value": 42}, ... ], // required
///   "created_at":"timestamptz"
/// }
/// ```
class Trend {
  const Trend({
    required this.id,
    required this.title,
    required this.points,
    this.metric,
    this.createdAt,
  });

  final String id;
  final String title;
  final String? metric;
  final List<TrendPoint> points;
  final DateTime? createdAt;

  /// Largest value in the set — used to scale the bars.
  double get maxValue => points.isEmpty
      ? 0
      : points.map((p) => p.value).reduce((a, b) => a > b ? a : b);

  factory Trend.fromMap(Map<String, dynamic> map) {
    final rawPoints = (map['points'] as List?) ?? const [];
    return Trend(
      id: map['id']?.toString() ?? '',
      title: (map['title'] as String?) ?? 'Trend',
      metric: map['metric'] as String?,
      points: rawPoints
          .map((p) => TrendPoint.fromMap(Map<String, dynamic>.from(p as Map)))
          .toList(),
      createdAt: map['created_at'] == null
          ? null
          : DateTime.tryParse(map['created_at'].toString())?.toLocal(),
    );
  }
}

class TrendPoint {
  const TrendPoint({required this.label, required this.value});

  final String label;
  final double value;

  factory TrendPoint.fromMap(Map<String, dynamic> map) {
    return TrendPoint(
      label: (map['label'] as String?) ?? '',
      value: (map['value'] as num?)?.toDouble() ?? 0,
    );
  }
}
