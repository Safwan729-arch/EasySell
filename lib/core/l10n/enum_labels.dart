import 'package:ai_shopkeeper/l10n/app_localizations.dart';

import '../../features/analytics/domain/analytics.dart';

/// Localized word for an [AnalyticsPeriod], shared by the dashboard pills, the
/// revenue hero, the breakdown sheet, and analytics — so the period vocabulary
/// stays consistent in both languages.
String periodLabel(AppLocalizations l10n, AnalyticsPeriod p) => switch (p) {
  AnalyticsPeriod.today => l10n.common_period_today,
  AnalyticsPeriod.week => l10n.common_period_week,
  AnalyticsPeriod.month => l10n.common_period_month,
  AnalyticsPeriod.all => l10n.common_period_all,
};
