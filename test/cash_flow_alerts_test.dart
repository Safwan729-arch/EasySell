import 'package:ai_shopkeeper/features/finance/domain/cash_flow_alerts.dart';
import 'package:ai_shopkeeper/features/finance/domain/finance_health.dart';
import 'package:flutter_test/flutter_test.dart';

FinanceHealth _h({
  double cash = 0,
  double digital = 0,
  double credit = 0,
  double collected = 0,
  double restock = 0,
  double week = 0,
  double prevWeek = 0,
  double owedNow = 0,
  double owedWeekAgo = 0,
  int overdueCount = 0,
  String? topName,
  double? topBalance,
  int? topDays,
}) => FinanceHealth(
  cashSales7d: cash,
  digitalSales7d: digital,
  creditSales7d: credit,
  collected7d: collected,
  restockSpend7d: restock,
  salesWeek: week,
  salesPrevWeek: prevWeek,
  owedNow: owedNow,
  owedWeekAgo: owedWeekAgo,
  overdueCount: overdueCount,
  overdueTopName: topName,
  overdueTopBalance: topBalance,
  overdueTopDays: topDays,
  sales90d: 0,
  profit90d: 0,
  digitalSales90d: 0,
  restockSpend90d: 0,
  activeWeeks12: 0,
  tradingDays: 0,
);

void main() {
  test('cash in is cash + digital + collected; credit is not money in', () {
    final h = _h(
      cash: 100,
      digital: 50,
      credit: 999,
      collected: 20,
      restock: 70,
    );
    expect(h.cashIn7d, 170);
    expect(h.net7d, 100);
  });

  test('a quiet healthy week raises nothing', () {
    expect(
      cashFlowAlerts(_h(cash: 500, restock: 200, week: 500, prevWeek: 480)),
      isEmpty,
    );
  });

  group('overdue', () {
    test('names the biggest late debtor and how many others', () {
      final a = cashFlowAlerts(
        _h(overdueCount: 3, topName: 'Rahim', topBalance: 1200, topDays: 34),
      );
      expect(a.first, isA<OverdueAlert>());
      final o = a.first as OverdueAlert;
      expect(o.name, 'Rahim');
      expect(o.balance, 1200);
      expect(o.days, 34);
      expect(o.others, 2);
    });
  });

  group('cash out exceeds in', () {
    test('fires when restocks beat money received', () {
      final a = cashFlowAlerts(_h(cash: 300, collected: 100, restock: 900));
      final c = a.whereType<CashShortAlert>().single;
      expect(c.shortBy, 500);
    });

    test('equal is not short', () {
      expect(
        cashFlowAlerts(_h(cash: 300, restock: 300)).whereType<CashShortAlert>(),
        isEmpty,
      );
    });

    test('credit sales do not count as money received', () {
      expect(
        cashFlowAlerts(
          _h(credit: 5000, restock: 100),
        ).whereType<CashShortAlert>(),
        hasLength(1),
      );
    });
  });

  group('credit growing', () {
    test('fires at a 20% rise that is also 5% of the week\'s sales', () {
      // rise 200 = 20% of 1000; week sales 4000 -> floor 200.
      final a = cashFlowAlerts(
        _h(cash: 3800, credit: 200, owedWeekAgo: 1000, owedNow: 1200),
      );
      final g = a.whereType<CreditGrowingAlert>().single;
      expect(g.rise, 200);
      expect(g.owedNow, 1200);
    });

    test('a rise under 20% of last week\'s balance is noise', () {
      expect(
        cashFlowAlerts(
          _h(cash: 100, owedWeekAgo: 1000, owedNow: 1190),
        ).whereType<CreditGrowingAlert>(),
        isEmpty,
      );
    });

    test('a tiny rise against big sales is not alarming', () {
      // rise 30 from 0, but week sales 1000 -> floor 50.
      expect(
        cashFlowAlerts(
          _h(cash: 970, credit: 30, owedNow: 30),
        ).whereType<CreditGrowingAlert>(),
        isEmpty,
      );
    });

    test('from nothing owed, any rise above the sales floor fires', () {
      expect(
        cashFlowAlerts(
          _h(cash: 900, credit: 100, owedNow: 100),
        ).whereType<CreditGrowingAlert>(),
        hasLength(1),
      );
    });

    test('falling credit never fires', () {
      expect(
        cashFlowAlerts(
          _h(owedWeekAgo: 500, owedNow: 300),
        ).whereType<CreditGrowingAlert>(),
        isEmpty,
      );
    });
  });

  group('sales dropping', () {
    test('fires at 25% below last week, with the percentage', () {
      final d = cashFlowAlerts(
        _h(week: 750, prevWeek: 1000),
      ).whereType<SalesDropAlert>().single;
      expect(d.dropPercent, 25);
    });

    test('a 24% dip is normal noise', () {
      expect(
        cashFlowAlerts(
          _h(week: 760, prevWeek: 1000),
        ).whereType<SalesDropAlert>(),
        isEmpty,
      );
    });

    test('no previous week, no comparison', () {
      expect(
        cashFlowAlerts(_h(week: 0, prevWeek: 0)).whereType<SalesDropAlert>(),
        isEmpty,
      );
    });
  });

  test('most serious first: overdue, cash short, credit, sales', () {
    final a = cashFlowAlerts(
      _h(
        cash: 100,
        credit: 900,
        restock: 500,
        owedNow: 900,
        week: 100,
        prevWeek: 1000,
        overdueCount: 1,
        topName: 'A',
        topBalance: 50,
        topDays: 40,
      ),
    );
    expect(a.map((x) => x.runtimeType).toList(), [
      OverdueAlert,
      CashShortAlert,
      CreditGrowingAlert,
      SalesDropAlert,
    ]);
  });

  test('hasActivity is false for a brand-new shop', () {
    expect(_h().hasActivity, isFalse);
    expect(_h(owedNow: 10).hasActivity, isTrue);
    expect(_h(restock: 10).hasActivity, isTrue);
  });
}
