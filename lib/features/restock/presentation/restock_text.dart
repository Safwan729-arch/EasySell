import '../../../l10n/app_localizations.dart';
import '../../../shared/extensions/format.dart';
import '../domain/restock_plan.dart';

/// "Runs out today" under one day, else "Runs out in N days" (whole days).
String runsOutText(AppLocalizations l10n, RestockItem i) => i.daysLeft < 1
    ? l10n.restockPlan_runsOutToday
    : l10n.restockPlan_runsOutIn(Qty.format(i.daysLeft.floor()));

/// "today" / "N days", for the Home card's one-line list.
String daysLeftShort(AppLocalizations l10n, RestockItem i) => i.daysLeft < 1
    ? l10n.restockPlan_today
    : l10n.restockPlan_daysShort(Qty.format(i.daysLeft.floor()));
