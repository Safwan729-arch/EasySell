import '../../../l10n/app_localizations.dart';
import '../../../shared/extensions/format.dart';
import '../domain/cash_flow_alerts.dart';
import '../domain/finance_health.dart';
import '../domain/financing_match.dart';
import 'finance_text.dart';

/// What `money-tips` may talk about: the Money health numbers, already
/// calculated and formatted in the app's language. Gemini is told to copy
/// these and never compute its own, so a tip can't carry a wrong figure.
/// The same sentences the seller sees on screen go in as the warnings and
/// financing reasons, so the advice can't contradict the card.
Map<String, dynamic> moneyTipsFacts({
  required FinanceHealth health,
  required AppLocalizations l10n,
  required String currency,
}) {
  String money(double v) => Money.compact(v, currencyCode: currency);
  return {
    'last_7_days': {
      'money_in': money(health.cashIn7d),
      'money_out_restocks_only': money(health.cashOut7d),
      'net': money(health.net7d),
      'cash_sales': money(health.cashSales7d),
      'digital_sales': money(health.digitalSales7d),
      'credit_collected': money(health.collected7d),
      'sold_on_credit_not_paid_yet': money(health.creditSales7d),
    },
    'credit_owed_now': money(health.owedNow),
    'sales_last_full_week': money(health.salesWeek),
    'sales_week_before': money(health.salesPrevWeek),
    'warnings': [
      for (final a in cashFlowAlerts(health))
        [alertText(l10n, a, currency), ?alertDetail(l10n, a)].join(' '),
    ],
    'financing_examples': [
      for (final m in matchFinancing(health))
        {
          'option': financingName(l10n, m.kind),
          'fits': m.fits,
          'why': financingReason(l10n, m, health, currency),
        },
    ],
  };
}
