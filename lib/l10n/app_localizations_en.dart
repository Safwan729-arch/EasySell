// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get settings_title => 'Settings';

  @override
  String get common_signOut => 'Sign out';

  @override
  String get settings_sectionProfile => 'Profile';

  @override
  String get settings_sectionShop => 'Shop';

  @override
  String get settings_sectionAssistant => 'Assistant';

  @override
  String get settings_sectionAppearance => 'Appearance';

  @override
  String get settings_sectionInventory => 'Inventory';

  @override
  String get settings_sectionLanguage => 'Language';

  @override
  String get settings_appLanguage => 'App language';

  @override
  String get settings_guestSession => 'Guest session';

  @override
  String get settings_signedIn => 'Signed in';

  @override
  String get settings_anonymousData =>
      'Anonymous — data is tied to this device';

  @override
  String get settings_shopName => 'Shop name';

  @override
  String get settings_address => 'Address';

  @override
  String get settings_phone => 'Phone';

  @override
  String get settings_currency => 'Currency';

  @override
  String get settings_aiInsights => 'AI Insights';

  @override
  String get settings_aiInsightsSub => 'Suggestions from the assistant';

  @override
  String get settings_trends => 'Trends';

  @override
  String get settings_trendsSub => 'Sales trend dashboards';

  @override
  String get settings_themeLight => 'Light';

  @override
  String get settings_themeDark => 'Dark';

  @override
  String get settings_manageCategories => 'Manage categories';

  @override
  String get settings_manageCategoriesSub =>
      'Rename, add, or remove categories';

  @override
  String get settings_archivedProducts => 'Archived products';

  @override
  String get settings_archivedProductsSub =>
      'View and restore removed products';

  @override
  String get common_restock => 'Restock';

  @override
  String get common_sell => 'Sell';

  @override
  String get common_period_today => 'Today';

  @override
  String get common_period_week => 'Week';

  @override
  String get common_period_month => 'Month';

  @override
  String get common_period_all => 'All';

  @override
  String get dashboard_yourShop => 'Your shop';

  @override
  String get dashboard_notificationsCaughtUp => 'You\'re all caught up';

  @override
  String get dashboard_notificationsHint =>
      'We\'ll alert you about low stock and sales here.';

  @override
  String get dashboard_salesLast7 => 'Sales · last 7 days';

  @override
  String dashboard_bestDay(String day) {
    return '$day best';
  }

  @override
  String get dashboard_topPerformer => 'TOP PERFORMER';

  @override
  String get dashboard_mvpBadge => 'MVP';

  @override
  String get dashboard_noSalesYet =>
      'No sales yet — your best seller will appear here.';

  @override
  String dashboard_soldRevenue(String units, String revenue) {
    return '$units sold · $revenue revenue';
  }

  @override
  String get dashboard_lowStock => 'Low stock';

  @override
  String get dashboard_viewAll => 'View all';

  @override
  String get dashboard_fullyStocked =>
      'You\'re fully stocked — nothing needs reordering.';

  @override
  String dashboard_leftReorder(String qty) {
    return '$qty left · reorder';
  }

  @override
  String get dashboard_couldNotLoadSummary => 'Could not load summary.';

  @override
  String get dashboard_couldNotLoadSales => 'Could not load sales.';

  @override
  String dashboard_revenuePeriod(String period) {
    return 'Revenue · $period';
  }

  @override
  String get dashboard_profit => 'Profit';

  @override
  String get dashboard_margin => 'Margin';

  @override
  String get dashboard_itemsSold => 'Items sold';

  @override
  String get dashboard_vsYesterday => 'vs yesterday';

  @override
  String get dashboard_breakdown => 'Breakdown';

  @override
  String dashboard_exactFigures(String period) {
    return '$period · exact figures';
  }

  @override
  String get dashboard_revenue => 'Revenue';

  @override
  String get dashboard_costOfGoods => 'Cost of goods';

  @override
  String get dashboard_grossProfit => 'Gross profit';

  @override
  String get dashboard_avgItemPrice => 'Avg item price';

  @override
  String get dashboard_viewFullReport => 'View full report';
}
