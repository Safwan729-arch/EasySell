/// A customer plus their live balance, as returned by the
/// `get_customer_balances` RPC. Not a table row — a query-shaped projection,
/// so it uses a hand-written `fromMap` like `DashboardSummary`.
class CustomerBalance {
  const CustomerBalance({
    required this.id,
    required this.name,
    required this.phone,
    required this.balance,
    this.note,
    this.lastActivityAt,
  });

  final String id;
  final String name;
  final String phone;
  final String? note;
  final double balance;
  final DateTime? lastActivityAt;

  /// True when this customer currently owes money.
  bool get owes => balance > 0;

  factory CustomerBalance.fromMap(Map<String, dynamic> map) {
    final rawActivity = map['last_activity_at'] as String?;
    return CustomerBalance(
      id: map['id'] as String,
      name: map['name'] as String,
      phone: map['phone'] as String,
      note: map['note'] as String?,
      balance: (map['balance'] as num?)?.toDouble() ?? 0,
      lastActivityAt: rawActivity == null
          ? null
          : DateTime.parse(rawActivity).toLocal(),
    );
  }
}
