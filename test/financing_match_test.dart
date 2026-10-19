import 'package:ai_shopkeeper/features/finance/domain/finance_health.dart';
import 'package:ai_shopkeeper/features/finance/domain/financing_match.dart';
import 'package:flutter_test/flutter_test.dart';

FinanceHealth _h({
  int tradingDays = 400,
  double sales90 = 90000,
  double profit90 = 18000,
  double digital90 = 0,
  double restock90 = 60000,
  int activeWeeks = 12,
  double owedNow = 0,
}) => FinanceHealth(
  cashSales7d: 0,
  digitalSales7d: 0,
  creditSales7d: 0,
  collected7d: 0,
  restockSpend7d: 0,
  salesWeek: 0,
  salesPrevWeek: 0,
  owedNow: owedNow,
  owedWeekAgo: 0,
  overdueCount: 0,
  sales90d: sales90,
  profit90d: profit90,
  digitalSales90d: digital90,
  restockSpend90d: restock90,
  activeWeeks12: activeWeeks,
  tradingDays: tradingDays,
);

FinancingMatch _of(List<FinancingMatch> l, FinancingKind k) =>
    l.firstWhere((m) => m.kind == k);

void main() {
  test('monthly sales spreads 90 days of sales over the days traded', () {
    expect(_h(sales90: 9000).monthlySales, 3000);
    // Only 30 days old: the 90-day total IS one month.
    expect(_h(tradingDays: 30, sales90: 3000).monthlySales, 3000);
    expect(_h(tradingDays: 0, sales90: 0).monthlySales, 0);
  });

  test('an established, steady, profitable shop fits all but wallet', () {
    final l = matchFinancing(_h());
    expect(_of(l, FinancingKind.supplierCredit).fits, isTrue);
    expect(_of(l, FinancingKind.microfinance).fits, isTrue);
    expect(_of(l, FinancingKind.smeLoan).fits, isTrue);
    final w = _of(l, FinancingKind.walletLoan);
    expect(w.fits, isFalse);
    expect(w.gap, isA<GoDigitalGap>());
  });

  test('fits are listed before not-yets', () {
    final l = matchFinancing(_h());
    final firstNo = l.indexWhere((m) => !m.fits);
    expect(l.skip(firstNo).every((m) => !m.fits), isTrue);
  });

  test('a 40-day-old shop is told how many more months to trade', () {
    final l = matchFinancing(_h(tradingDays: 40));
    final s = _of(l, FinancingKind.supplierCredit);
    expect(s.fits, isFalse);
    expect((s.gap! as TradeLongerGap).monthsMore, 2); // 90 - 40 = 50 days
    expect(
      (_of(l, FinancingKind.smeLoan).gap! as TradeLongerGap).monthsMore,
      11, // 360 - 40 = 320 days
    );
  });

  test(
    'wallet loan fits at 10% digital and lends a month of digital sales',
    () {
      final w = _of(
        matchFinancing(_h(digital90: 9000)),
        FinancingKind.walletLoan,
      );
      expect(w.fits, isTrue);
      expect(w.upTo, 3000);
    },
  );

  test('supplier credit needs restocking and 8 active weeks', () {
    expect(
      _of(matchFinancing(_h(restock90: 0)), FinancingKind.supplierCredit).gap,
      isA<RestockFirstGap>(),
    );
    final g =
        _of(
              matchFinancing(_h(activeWeeks: 7)),
              FinancingKind.supplierCredit,
            ).gap!
            as SellMoreWeeksGap;
    expect(g.needed, 8);
    expect(g.have, 7);
  });

  test('microfinance needs 10 of 12 active weeks', () {
    expect(
      _of(matchFinancing(_h(activeWeeks: 10)), FinancingKind.microfinance).fits,
      isTrue,
    );
    expect(
      _of(matchFinancing(_h(activeWeeks: 9)), FinancingKind.microfinance).gap,
      isA<SellMoreWeeksGap>(),
    );
  });

  test('SME loan: margin under 10% says so', () {
    final g =
        _of(matchFinancing(_h(profit90: 8000)), FinancingKind.smeLoan).gap!
            as RaiseMarginGap;
    expect(g.havePercent, closeTo(8.9, 0.1));
  });

  test('SME loan: too much credit owed says so', () {
    // monthly sales 30000; owed 16000 > 50%.
    expect(
      _of(matchFinancing(_h(owedNow: 16000)), FinancingKind.smeLoan).gap,
      isA<CollectCreditGap>(),
    );
    expect(
      _of(matchFinancing(_h(owedNow: 15000)), FinancingKind.smeLoan).fits,
      isTrue,
    );
  });

  test('amounts round down to two significant figures', () {
    expect(roundDownTwoSig(37842), 37000);
    expect(roundDownTwoSig(999), 990);
    expect(roundDownTwoSig(5), 5);
    expect(roundDownTwoSig(0), 0);
    expect(roundDownTwoSig(-3), 0);
  });

  test('SME amount is three months of sales', () {
    expect(_of(matchFinancing(_h()), FinancingKind.smeLoan).upTo, 90000);
  });
}
