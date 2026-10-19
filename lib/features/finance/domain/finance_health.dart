/// One row of `get_finance_health` (migration 0019): plain sums the money
/// health alerts and financing matches are judged from. A query-shaped
/// projection, so a hand-written `fromMap` like `DashboardSummary`.
///
/// "7d" is the last 7 local days including today; "week"/"prevWeek" are the 7
/// full days ending yesterday and the 7 before; "90d" is the last 90 days.
class FinanceHealth {
  const FinanceHealth({
    required this.cashSales7d,
    required this.digitalSales7d,
    required this.creditSales7d,
    required this.collected7d,
    required this.restockSpend7d,
    required this.salesWeek,
    required this.salesPrevWeek,
    required this.owedNow,
    required this.owedWeekAgo,
    required this.overdueCount,
    this.overdueTopName,
    this.overdueTopBalance,
    this.overdueTopDays,
    required this.sales90d,
    required this.profit90d,
    required this.digitalSales90d,
    required this.restockSpend90d,
    required this.activeWeeks12,
    required this.tradingDays,
  });

  final double cashSales7d;
  final double digitalSales7d;
  final double creditSales7d;
  final double collected7d;
  final double restockSpend7d;
  final double salesWeek;
  final double salesPrevWeek;
  final double owedNow;
  final double owedWeekAgo;
  final int overdueCount;
  final String? overdueTopName;
  final double? overdueTopBalance;
  final int? overdueTopDays;
  final double sales90d;
  final double profit90d;
  final double digitalSales90d;
  final double restockSpend90d;
  final int activeWeeks12;
  final int tradingDays;

  /// No shop yet: nothing to judge.
  static const empty = FinanceHealth(
    cashSales7d: 0,
    digitalSales7d: 0,
    creditSales7d: 0,
    collected7d: 0,
    restockSpend7d: 0,
    salesWeek: 0,
    salesPrevWeek: 0,
    owedNow: 0,
    owedWeekAgo: 0,
    overdueCount: 0,
    sales90d: 0,
    profit90d: 0,
    digitalSales90d: 0,
    restockSpend90d: 0,
    activeWeeks12: 0,
    tradingDays: 0,
  );

  /// Money that actually arrived: credit sales are excluded, khata payments
  /// collected are included.
  double get cashIn7d => cashSales7d + digitalSales7d + collected7d;

  /// Restocks are the only spending the app records (spec §3).
  double get cashOut7d => restockSpend7d;

  double get net7d => cashIn7d - cashOut7d;

  /// Every sale of the last 7 days, however it was paid.
  double get sales7d => cashSales7d + digitalSales7d + creditSales7d;

  /// The 90-day total spread over the days actually traded (a 30-day-old
  /// shop's 90-day total is one month).
  double get monthlySales => _perMonth(sales90d);

  double get monthlyDigitalSales => _perMonth(digitalSales90d);

  double get monthlyRestockSpend => _perMonth(restockSpend90d);

  double _perMonth(double total90) {
    if (tradingDays <= 0) return 0;
    return total90 / tradingDays.clamp(1, 90) * 30;
  }

  /// False for a brand-new shop: nothing moved this week and nobody owes.
  bool get hasActivity =>
      sales7d > 0 || collected7d > 0 || restockSpend7d > 0 || owedNow > 0;

  factory FinanceHealth.fromMap(Map<String, dynamic> m) {
    double d(String k) => (m[k] as num?)?.toDouble() ?? 0;
    int i(String k) => (m[k] as num?)?.toInt() ?? 0;
    return FinanceHealth(
      cashSales7d: d('cash_sales_7d'),
      digitalSales7d: d('digital_sales_7d'),
      creditSales7d: d('credit_sales_7d'),
      collected7d: d('collected_7d'),
      restockSpend7d: d('restock_spend_7d'),
      salesWeek: d('sales_week'),
      salesPrevWeek: d('sales_prev_week'),
      owedNow: d('owed_now'),
      owedWeekAgo: d('owed_week_ago'),
      overdueCount: i('overdue_count'),
      overdueTopName: m['overdue_top_name'] as String?,
      overdueTopBalance: (m['overdue_top_balance'] as num?)?.toDouble(),
      overdueTopDays: (m['overdue_top_days'] as num?)?.toInt(),
      sales90d: d('sales_90d'),
      profit90d: d('profit_90d'),
      digitalSales90d: d('digital_sales_90d'),
      restockSpend90d: d('restock_spend_90d'),
      activeWeeks12: i('active_weeks_12'),
      tradingDays: i('trading_days'),
    );
  }
}
