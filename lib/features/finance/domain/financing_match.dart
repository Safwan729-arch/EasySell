import 'dart:math' as math;

import 'finance_health.dart';

/// Example loan types (spec §5). Illustrative only -- generic types, no
/// lender names -- and listed easiest/smallest first: each step needs a
/// longer, steadier record.
enum FinancingKind { supplierCredit, walletLoan, microfinance, smeLoan }

/// Why an option does not fit yet, phrased as what the shop can do about it.
sealed class FinancingGap {
  const FinancingGap();
}

class TradeLongerGap extends FinancingGap {
  const TradeLongerGap(this.monthsMore);

  final int monthsMore;
}

class RestockFirstGap extends FinancingGap {
  const RestockFirstGap();
}

class SellMoreWeeksGap extends FinancingGap {
  const SellMoreWeeksGap({required this.needed, required this.have});

  final int needed;
  final int have;
}

class GoDigitalGap extends FinancingGap {
  const GoDigitalGap({required this.targetPercent, required this.havePercent});

  final double targetPercent;
  final double havePercent;
}

class RaiseMarginGap extends FinancingGap {
  const RaiseMarginGap({
    required this.targetPercent,
    required this.havePercent,
  });

  final double targetPercent;
  final double havePercent;
}

class CollectCreditGap extends FinancingGap {
  const CollectCreditGap();
}

class FinancingMatch {
  const FinancingMatch({required this.kind, required this.upTo, this.gap});

  final FinancingKind kind;

  /// A rough ceiling, rounded down to two significant figures so it never
  /// reads like a quote. 0 when there is nothing to base it on.
  final double upTo;

  /// Null when the option fits.
  final FinancingGap? gap;

  bool get fits => gap == null;
}

const _daysPerMonth = 30;

// Thresholds (spec §5). All relative: months, weeks, percentages.
const _supplierMonths = 3;
const _supplierWeeks = 8;
const _walletMonths = 3;
const _walletDigitalPercent = 10.0;
const _microMonths = 6;
const _microWeeks = 10;
const _smeMonths = 12;
const _smeMarginPercent = 10.0;
const _smeMaxOwedShare = 0.5;

/// Every option, fits first, catalogue order within each group.
List<FinancingMatch> matchFinancing(FinanceHealth h) {
  final salesPct = h.sales90d > 0 ? 1 / h.sales90d * 100 : 0.0;
  final digitalPercent = h.digitalSales90d * salesPct;
  final marginPercent = h.profit90d * salesPct;

  TradeLongerGap? tradeFor(int months) {
    final short = months * _daysPerMonth - h.tradingDays;
    return short > 0 ? TradeLongerGap((short / _daysPerMonth).ceil()) : null;
  }

  FinancingGap? firstGap(List<FinancingGap? Function()> checks) {
    for (final c in checks) {
      final g = c();
      if (g != null) return g;
    }
    return null;
  }

  final all = [
    FinancingMatch(
      kind: FinancingKind.supplierCredit,
      upTo: roundDownTwoSig(h.monthlyRestockSpend),
      gap: firstGap([
        () => tradeFor(_supplierMonths),
        () => h.restockSpend90d > 0 ? null : const RestockFirstGap(),
        () => h.activeWeeks12 >= _supplierWeeks
            ? null
            : SellMoreWeeksGap(needed: _supplierWeeks, have: h.activeWeeks12),
      ]),
    ),
    FinancingMatch(
      kind: FinancingKind.walletLoan,
      upTo: roundDownTwoSig(h.monthlyDigitalSales),
      gap: firstGap([
        () => tradeFor(_walletMonths),
        () => digitalPercent >= _walletDigitalPercent
            ? null
            : GoDigitalGap(
                targetPercent: _walletDigitalPercent,
                havePercent: digitalPercent,
              ),
      ]),
    ),
    FinancingMatch(
      kind: FinancingKind.microfinance,
      upTo: roundDownTwoSig(h.monthlySales),
      gap: firstGap([
        () => tradeFor(_microMonths),
        () => h.activeWeeks12 >= _microWeeks
            ? null
            : SellMoreWeeksGap(needed: _microWeeks, have: h.activeWeeks12),
      ]),
    ),
    FinancingMatch(
      kind: FinancingKind.smeLoan,
      upTo: roundDownTwoSig(h.monthlySales * 3),
      gap: firstGap([
        () => tradeFor(_smeMonths),
        () => marginPercent >= _smeMarginPercent
            ? null
            : RaiseMarginGap(
                targetPercent: _smeMarginPercent,
                havePercent: marginPercent,
              ),
        () => h.owedNow <= h.monthlySales * _smeMaxOwedShare
            ? null
            : const CollectCreditGap(),
      ]),
    ),
  ];

  return [...all.where((m) => m.fits), ...all.where((m) => !m.fits)];
}

/// 37842 -> 37000, 999 -> 990. Below 100 just drops the fraction.
double roundDownTwoSig(double x) {
  if (x <= 0) return 0;
  if (x < 100) return x.floorToDouble();
  final step = math.pow(10, (math.log(x) / math.ln10).floor() - 1).toDouble();
  return (x / step).floorToDouble() * step;
}
