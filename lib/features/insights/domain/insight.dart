/// An AI-generated insight, WRITTEN BY Member B into the `insights` table.
/// I only read/render it.
///
/// // MEMBER B — proposed contract (flag if yours differs):
/// ```jsonc
/// {
///   "id":        "uuid",
///   "shop_id":   "uuid",
///   "type":      "restock" | "pricing" | "summary" | string, // optional
///   "title":     "Restock Pepsi 500ml",                       // required
///   "body":      "Sells ~12/day; 2 days of stock left.",      // required
///   "severity":  "info" | "warning" | "critical",            // optional
///   "created_at":"timestamptz"
/// }
/// ```
class Insight {
  const Insight({
    required this.id,
    required this.title,
    required this.body,
    this.type,
    this.severity,
    this.createdAt,
  });

  final String id;
  final String title;
  final String body;
  final String? type;
  final String? severity;
  final DateTime? createdAt;

  factory Insight.fromMap(Map<String, dynamic> map) {
    return Insight(
      id: map['id']?.toString() ?? '',
      title: (map['title'] as String?) ?? 'Insight',
      body: (map['body'] as String?) ?? '',
      type: map['type'] as String?,
      severity: map['severity'] as String?,
      createdAt: map['created_at'] == null
          ? null
          : DateTime.tryParse(map['created_at'].toString())?.toLocal(),
    );
  }
}
