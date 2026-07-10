import 'package:ai_shopkeeper/l10n/app_localizations.dart';

import '../../features/analytics/domain/analytics.dart';
import '../../features/inventory/domain/product.dart';

/// Localized word for an [AnalyticsPeriod], shared by the dashboard pills, the
/// revenue hero, the breakdown sheet, and analytics — so the period vocabulary
/// stays consistent in both languages.
String periodLabel(AppLocalizations l10n, AnalyticsPeriod p) => switch (p) {
  AnalyticsPeriod.today => l10n.common_period_today,
  AnalyticsPeriod.week => l10n.common_period_week,
  AnalyticsPeriod.month => l10n.common_period_month,
  AnalyticsPeriod.all => l10n.common_period_all,
};

/// Localized "By piece / By weight / By volume" selling-mode label for the
/// product form. (The short unit abbreviations — pcs, kg, ml — stay as-is, as
/// they are used pervasively via domain getters and read the same in-shop.)
String unitTypeLabel(AppLocalizations l10n, UnitType t) => switch (t) {
  UnitType.piece => l10n.unit_byPiece,
  UnitType.weight => l10n.unit_byWeight,
  UnitType.volume => l10n.unit_byVolume,
};

/// Localized one-line hint describing a selling mode.
String unitTypeHint(AppLocalizations l10n, UnitType t) => switch (t) {
  UnitType.piece => l10n.unit_hintPiece,
  UnitType.weight => l10n.unit_hintWeight,
  UnitType.volume => l10n.unit_hintVolume,
};
