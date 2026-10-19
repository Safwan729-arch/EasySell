import 'finance_health.dart';

/// Debt this old is late: khata is normally settled monthly. Sent to
/// `get_finance_health` as `p_overdue_days`.
const overdueDays = 30;

/// Credit owed must rise by this share of last week's balance...
const creditGrowthShare = 0.20;

/// ...and by this share of the week's sales, so a ৳20 rise on a tiny balance
/// does not alarm anyone. Relative only: shops use different currencies.
const creditGrowthSalesFloor = 0.05;

/// Sales at or below this share of last week's count as dropping (a 25 % fall
/// is beyond normal day-to-day noise).
const salesDropShare = 0.75;

/// A money-health warning (spec §4). Sorted most serious first by
/// [cashFlowAlerts].
sealed class CashFlowAlert {
  const CashFlowAlert();
}

/// Customers whose oldest unpaid credit is [overdueDays]+ days old. Names the
/// biggest one; [others] is how many more there are.
class OverdueAlert extends CashFlowAlert {
  const OverdueAlert({
    required this.name,
    required this.balance,
    required this.days,
    required this.others,
  });

  final String name;
  final double balance;
  final int days;
  final int others;
}

/// Restocks this week cost more than the money that came in.
class CashShortAlert extends CashFlowAlert {
  const CashShortAlert(this.shortBy);

  final double shortBy;
}

/// Credit owed went up by [rise] this week, to [owedNow].
class CreditGrowingAlert extends CashFlowAlert {
  const CreditGrowingAlert({required this.rise, required this.owedNow});

  final double rise;
  final double owedNow;
}

/// Last week's sales fell [dropPercent] % below the week before.
class SalesDropAlert extends CashFlowAlert {
  const SalesDropAlert(this.dropPercent);

  final double dropPercent;
}

List<CashFlowAlert> cashFlowAlerts(FinanceHealth h) {
  final alerts = <CashFlowAlert>[];

  if (h.overdueCount > 0 && h.overdueTopName != null) {
    alerts.add(
      OverdueAlert(
        name: h.overdueTopName!,
        balance: h.overdueTopBalance ?? 0,
        days: h.overdueTopDays ?? overdueDays,
        others: h.overdueCount - 1,
      ),
    );
  }

  if (h.cashOut7d > 0 && h.cashOut7d > h.cashIn7d) {
    alerts.add(CashShortAlert(h.cashOut7d - h.cashIn7d));
  }

  final rise = h.owedNow - h.owedWeekAgo;
  if (rise > 0 &&
      rise >= h.owedWeekAgo * creditGrowthShare &&
      rise >= h.sales7d * creditGrowthSalesFloor) {
    alerts.add(CreditGrowingAlert(rise: rise, owedNow: h.owedNow));
  }

  if (h.salesPrevWeek > 0 && h.salesWeek <= h.salesPrevWeek * salesDropShare) {
    alerts.add(SalesDropAlert((1 - h.salesWeek / h.salesPrevWeek) * 100));
  }

  return alerts;
}
