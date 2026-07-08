/// Aggregated totals for a period, returned by the `get_dashboard_summary` RPC.
/// All numbers are computed in Postgres — see CLAUDE.md §5.
class DashboardSummary {
  const DashboardSummary({
    required this.revenue,
    required this.cost,
    required this.profit,
    required this.unitsSold,
    required this.inventoryValue,
  });

  final double revenue;
  final double cost;
  final double profit;
  final int unitsSold;
  final double inventoryValue;

  static const empty = DashboardSummary(
    revenue: 0,
    cost: 0,
    profit: 0,
    unitsSold: 0,
    inventoryValue: 0,
  );

  factory DashboardSummary.fromMap(Map<String, dynamic> map) {
    double d(dynamic v) => (v as num?)?.toDouble() ?? 0;
    return DashboardSummary(
      revenue: d(map['revenue']),
      cost: d(map['cost']),
      profit: d(map['profit']),
      unitsSold: (map['units_sold'] as num?)?.toInt() ?? 0,
      inventoryValue: d(map['inventory_value']),
    );
  }
}

/// One bucket of the revenue/profit time series (`get_sales_series` RPC).
class SalesPoint {
  const SalesPoint({
    required this.bucket,
    required this.revenue,
    required this.profit,
  });

  final DateTime bucket;
  final double revenue;
  final double profit;

  factory SalesPoint.fromMap(Map<String, dynamic> map) {
    double d(dynamic v) => (v as num?)?.toDouble() ?? 0;
    return SalesPoint(
      bucket: DateTime.parse(map['bucket'] as String).toLocal(),
      revenue: d(map['revenue']),
      profit: d(map['profit']),
    );
  }
}

/// Period for the summary RPC.
enum AnalyticsPeriod {
  today('today', 'Today'),
  week('week', 'This week'),
  month('month', 'This month'),
  all('all', 'All time');

  const AnalyticsPeriod(this.value, this.label);
  final String value;
  final String label;
}

/// Bucket granularity for the chart series.
enum ChartBucket {
  daily('day', 'Daily', 7),
  weekly('week', 'Weekly', 8),
  monthly('month', 'Monthly', 6);

  const ChartBucket(this.value, this.label, this.points);
  final String value;
  final String label;
  final int points;
}

/// Formats [day] as the `p_day` argument (YYYY-MM-DD, date-only) for
/// `get_dashboard_summary`. Uses local year/month/day so the string matches the
/// calendar day the user tapped, ignoring the time component.
String dayParam(DateTime day) {
  final y = day.year.toString().padLeft(4, '0');
  final m = day.month.toString().padLeft(2, '0');
  final d = day.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}
