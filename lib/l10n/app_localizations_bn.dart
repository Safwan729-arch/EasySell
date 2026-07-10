// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Bengali Bangla (`bn`).
class AppLocalizationsBn extends AppLocalizations {
  AppLocalizationsBn([String locale = 'bn']) : super(locale);

  @override
  String get settings_title => 'সেটিংস';

  @override
  String get common_signOut => 'লগ আউট';

  @override
  String get settings_sectionProfile => 'প্রোফাইল';

  @override
  String get settings_sectionShop => 'দোকান';

  @override
  String get settings_sectionAssistant => 'অ্যাসিস্ট্যান্ট';

  @override
  String get settings_sectionAppearance => 'চেহারা';

  @override
  String get settings_sectionInventory => 'পণ্য';

  @override
  String get settings_sectionLanguage => 'ভাষা';

  @override
  String get settings_appLanguage => 'অ্যাপের ভাষা';

  @override
  String get settings_guestSession => 'গেস্ট সেশন';

  @override
  String get settings_signedIn => 'সাইন ইন করা আছে';

  @override
  String get settings_anonymousData => 'বেনামী — ডেটা এই ডিভাইসে সংরক্ষিত';

  @override
  String get settings_shopName => 'দোকানের নাম';

  @override
  String get settings_address => 'ঠিকানা';

  @override
  String get settings_phone => 'ফোন';

  @override
  String get settings_currency => 'মুদ্রা';

  @override
  String get settings_aiInsights => 'এআই ইনসাইট';

  @override
  String get settings_aiInsightsSub => 'অ্যাসিস্ট্যান্টের পরামর্শ';

  @override
  String get settings_trends => 'ট্রেন্ড';

  @override
  String get settings_trendsSub => 'বিক্রির ট্রেন্ড';

  @override
  String get settings_themeLight => 'লাইট';

  @override
  String get settings_themeDark => 'ডার্ক';

  @override
  String get settings_manageCategories => 'ক্যাটাগরি পরিচালনা';

  @override
  String get settings_manageCategoriesSub => 'যোগ, নাম বদল বা মুছুন';

  @override
  String get settings_archivedProducts => 'আর্কাইভ পণ্য';

  @override
  String get settings_archivedProductsSub => 'সরানো পণ্য দেখুন ও ফেরান';

  @override
  String get common_restock => 'রিস্টক';

  @override
  String get common_sell => 'বিক্রি';

  @override
  String get common_period_today => 'আজ';

  @override
  String get common_period_week => 'সপ্তাহ';

  @override
  String get common_period_month => 'মাস';

  @override
  String get common_period_all => 'সব';

  @override
  String get dashboard_yourShop => 'আপনার দোকান';

  @override
  String get dashboard_notificationsCaughtUp => 'সব দেখা হয়ে গেছে';

  @override
  String get dashboard_notificationsHint =>
      'কম স্টক আর বিক্রির খবর এখানে পাবেন।';

  @override
  String get dashboard_salesLast7 => 'বিক্রি · গত ৭ দিন';

  @override
  String dashboard_bestDay(String day) {
    return '$day সেরা';
  }

  @override
  String get dashboard_topPerformer => 'সেরা বিক্রেতা';

  @override
  String get dashboard_mvpBadge => 'সেরা';

  @override
  String get dashboard_noSalesYet =>
      'এখনো বিক্রি নেই — সেরা বিক্রেতা এখানে দেখাবে।';

  @override
  String dashboard_soldRevenue(String units, String revenue) {
    return '$units বিক্রি · $revenue আয়';
  }

  @override
  String get dashboard_lowStock => 'কম স্টক';

  @override
  String get dashboard_viewAll => 'সব দেখুন';

  @override
  String get dashboard_fullyStocked => 'স্টক ভরা — কিছু রিঅর্ডার করতে হবে না।';

  @override
  String dashboard_leftReorder(String qty) {
    return '$qty বাকি · রিঅর্ডার';
  }

  @override
  String get dashboard_couldNotLoadSummary => 'সারসংক্ষেপ লোড করা যায়নি।';

  @override
  String get dashboard_couldNotLoadSales => 'বিক্রি লোড করা যায়নি।';

  @override
  String dashboard_revenuePeriod(String period) {
    return 'আয় · $period';
  }

  @override
  String get dashboard_profit => 'লাভ';

  @override
  String get dashboard_margin => 'মার্জিন';

  @override
  String get dashboard_itemsSold => 'বিক্রি';

  @override
  String get dashboard_vsYesterday => 'গতকালের চেয়ে';

  @override
  String get dashboard_breakdown => 'বিস্তারিত';

  @override
  String dashboard_exactFigures(String period) {
    return '$period · সঠিক হিসাব';
  }

  @override
  String get dashboard_revenue => 'আয়';

  @override
  String get dashboard_costOfGoods => 'পণ্যের খরচ';

  @override
  String get dashboard_grossProfit => 'মোট লাভ';

  @override
  String get dashboard_avgItemPrice => 'গড় দাম';

  @override
  String get dashboard_viewFullReport => 'পূর্ণ রিপোর্ট দেখুন';
}
