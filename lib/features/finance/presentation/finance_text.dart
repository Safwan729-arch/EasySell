import '../../../l10n/app_localizations.dart';
import '../../../shared/extensions/format.dart';
import '../domain/cash_flow_alerts.dart';
import '../domain/finance_health.dart';
import '../domain/financing_match.dart';

// MEMBER B: Gemini could reword these lines more naturally. Keep the numbers
// from these rules so every explanation stays true.

String alertText(AppLocalizations l10n, CashFlowAlert a, String currency) {
  String money(double v) => Money.format(v, currencyCode: currency);
  return switch (a) {
    OverdueAlert() => l10n.finance_alertOverdue(
      a.name,
      money(a.balance),
      Qty.format(a.days),
    ),
    CashShortAlert() => l10n.finance_alertCashShort(money(a.shortBy)),
    CreditGrowingAlert() => l10n.finance_alertCreditGrowing(
      money(a.rise),
      money(a.owedNow),
    ),
    SalesDropAlert() => l10n.finance_alertSalesDrop(
      Pct.format(a.dropPercent.roundToDouble()),
    ),
  };
}

/// The second line of an overdue alert, or null.
String? alertDetail(AppLocalizations l10n, CashFlowAlert a) =>
    a is OverdueAlert && a.others > 0
    ? l10n.finance_alertOverdueMore(a.others)
    : null;

String financingName(AppLocalizations l10n, FinancingKind k) => switch (k) {
  FinancingKind.supplierCredit => l10n.finance_kindSupplier,
  FinancingKind.walletLoan => l10n.finance_kindWallet,
  FinancingKind.microfinance => l10n.finance_kindMicro,
  FinancingKind.smeLoan => l10n.finance_kindSme,
};

String financingSubtitle(AppLocalizations l10n, FinancingKind k) => switch (k) {
  FinancingKind.supplierCredit => l10n.finance_kindSupplierSub,
  FinancingKind.walletLoan => l10n.finance_kindWalletSub,
  FinancingKind.microfinance => l10n.finance_kindMicroSub,
  FinancingKind.smeLoan => l10n.finance_kindSmeSub,
};

/// Why it fits (from the shop's own numbers), or what to do to get there.
String financingReason(
  AppLocalizations l10n,
  FinancingMatch m,
  FinanceHealth h,
  String currency,
) {
  final gap = m.gap;
  if (gap != null) return _gapText(l10n, gap);
  final pct = h.sales90d > 0 ? 100 / h.sales90d : 0.0;
  return switch (m.kind) {
    FinancingKind.supplierCredit => l10n.finance_whySupplier(
      Money.format(
        roundDownTwoSig(h.monthlyRestockSpend),
        currencyCode: currency,
      ),
    ),
    FinancingKind.walletLoan => l10n.finance_whyWallet(
      Pct.format((h.digitalSales90d * pct).roundToDouble()),
    ),
    FinancingKind.microfinance => l10n.finance_whyMicro(
      Qty.format(h.activeWeeks12),
    ),
    FinancingKind.smeLoan => l10n.finance_whySme(
      Qty.format(h.tradingDays ~/ 30),
      Pct.format((h.profit90d * pct).roundToDouble()),
    ),
  };
}

String _gapText(AppLocalizations l10n, FinancingGap g) => switch (g) {
  TradeLongerGap() => l10n.finance_gapTrade(g.monthsMore),
  RestockFirstGap() => l10n.finance_gapRestock,
  SellMoreWeeksGap() => l10n.finance_gapWeeks(
    Qty.format(g.needed),
    Qty.format(g.have),
  ),
  GoDigitalGap() => l10n.finance_gapDigital(
    Pct.format(g.targetPercent),
    Pct.format(g.havePercent.floorToDouble()),
  ),
  RaiseMarginGap() => l10n.finance_gapMargin(
    Pct.format(g.targetPercent),
    Pct.format(g.havePercent.floorToDouble()),
  ),
  CollectCreditGap() => l10n.finance_gapCredit,
};
