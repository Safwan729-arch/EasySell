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

  @override
  String get common_cancel => 'বাতিল';

  @override
  String get common_delete => 'মুছুন';

  @override
  String get common_edit => 'এডিট';

  @override
  String get common_retry => 'আবার চেষ্টা';

  @override
  String get common_undo => 'ফিরিয়ে আনুন';

  @override
  String get common_off => 'বন্ধ';

  @override
  String get common_addToCart => 'কার্টে যোগ';

  @override
  String get common_addedToCart => 'কার্টে যোগ হয়েছে';

  @override
  String get common_stockAdded => 'স্টক যোগ হয়েছে';

  @override
  String get common_somethingWrong => 'কিছু ভুল হয়েছে। আবার চেষ্টা করুন।';

  @override
  String get common_searchItems => 'পণ্য খুঁজুন';

  @override
  String get common_restore => 'ফেরান';

  @override
  String get inventory_title => 'পণ্যতালিকা';

  @override
  String inventory_itemsValue(int count, String value) {
    return '$countটি পণ্য · $value মূল্য';
  }

  @override
  String get inventory_filterAll => 'সব';

  @override
  String get inventory_filterLowStock => 'কম স্টক';

  @override
  String inventory_inStock(String qty) {
    return '$qty স্টকে';
  }

  @override
  String get inventory_noProducts =>
      'এখনো কোনো পণ্য নেই।\nশুরু করতে \"পণ্য যোগ\" চাপুন।';

  @override
  String get inventory_noMatch => 'আপনার ফিল্টারে কোনো পণ্য মেলেনি।';

  @override
  String get inventory_couldNotLoad =>
      'পণ্যতালিকা লোড করা যায়নি। রিফ্রেশ করুন।';

  @override
  String get inventory_addProduct => 'পণ্য যোগ';

  @override
  String get inventory_scanProduct => 'পণ্য স্ক্যান';

  @override
  String get inventory_couldNotLoadProduct => 'পণ্য লোড করা যায়নি।';

  @override
  String get inventory_productGone => 'এই পণ্যটি আর নেই।';

  @override
  String get inventory_removeTitle => 'পণ্য সরাবেন?';

  @override
  String inventory_removeBody(String name) {
    return '\"$name\" আপনার পণ্যতালিকা থেকে সরে যাবে। এর আগের বিক্রি রেকর্ডে থাকবে।';
  }

  @override
  String inventory_removed(String name) {
    return '\"$name\" সরানো হয়েছে';
  }

  @override
  String get inventory_lowStock => 'কম স্টক';

  @override
  String inventory_reorderThresholdNote(String threshold) {
    return 'রিঅর্ডার সীমার নিচে বা সমান ($threshold)।';
  }

  @override
  String get inventory_statInStock => 'স্টকে আছে';

  @override
  String get inventory_statBuyingPrice => 'কেনা দাম';

  @override
  String get inventory_statSellingPrice => 'বিক্রি দাম';

  @override
  String get inventory_statMarginPerUnit => 'মার্জিন / একক';

  @override
  String get inventory_statInventoryValue => 'স্টকের মূল্য (খরচ)';

  @override
  String get inventory_statReorderThreshold => 'রিঅর্ডার সীমা';

  @override
  String get inventory_couldNotLoadArchived =>
      'আর্কাইভ পণ্য লোড করা যায়নি। রিফ্রেশ করুন।';

  @override
  String inventory_restored(String name) {
    return '\"$name\" পণ্যতালিকায় ফিরেছে।';
  }

  @override
  String inventory_couldNotRestore(String name) {
    return '\"$name\" ফেরানো যায়নি। আবার চেষ্টা করুন।';
  }

  @override
  String get inventory_noArchived => 'কোনো আর্কাইভ পণ্য নেই।';

  @override
  String get inventory_archivedHint =>
      'পণ্যতালিকা থেকে সরানো পণ্য এখানে দেখাবে।';
}
