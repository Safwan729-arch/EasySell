import '../../../l10n/app_localizations.dart';
import '../domain/restock_plan.dart';

/// "Runs out today" under one day, else "Runs out in N days" (whole days).
/// A product listed only by its reorder level has no speed to run out by.
String runsOutText(AppLocalizations l10n, RestockItem i) => i.speed <= 0
    ? l10n.restockPlan_atReorderLevel
    : i.daysLeft < 1
    ? l10n.restockPlan_runsOutToday
    : l10n.restockPlan_runsOutIn(i.daysLeft.floor());

/// "today" / "N days" / "low stock", for the Home card's one-line list.
String daysLeftShort(AppLocalizations l10n, RestockItem i) => i.speed <= 0
    ? l10n.restockPlan_lowShort
    : i.daysLeft < 1
    ? l10n.restockPlan_today
    : l10n.restockPlan_daysShort(i.daysLeft.floor());
