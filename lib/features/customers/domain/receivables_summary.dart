/// Total outstanding receivables + how many customers owe, from the
/// `get_receivables_summary` RPC. Backs the dashboard card.
class ReceivablesSummary {
  const ReceivablesSummary({
    required this.totalOwed,
    required this.debtorCount,
  });

  final double totalOwed;
  final int debtorCount;

  static const empty = ReceivablesSummary(totalOwed: 0, debtorCount: 0);

  factory ReceivablesSummary.fromMap(Map<String, dynamic> map) {
    return ReceivablesSummary(
      totalOwed: (map['total_owed'] as num?)?.toDouble() ?? 0,
      debtorCount: (map['debtor_count'] as num?)?.toInt() ?? 0,
    );
  }
}
