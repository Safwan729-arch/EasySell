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
  String get common_noInternet => 'ইন্টারনেট সংযোগ নেই';

  @override
  String get common_searchItems => 'পণ্য খুঁজুন';

  @override
  String get common_restore => 'ফেরান';

  @override
  String get inventory_title => 'পণ্যতালিকা';

  @override
  String inventory_itemsValue(int count, String value) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return '$countStringটি পণ্য · $value';
  }

  @override
  String get inventory_valueTitle => 'স্টকের মূল্য';

  @override
  String get inventory_valueExact => 'সঠিক হিসাব';

  @override
  String get inventory_valueProducts => 'পণ্য';

  @override
  String get inventory_valueRetail => 'বিক্রয় মূল্য';

  @override
  String get inventory_valuePotentialProfit => 'সম্ভাব্য লাভ';

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

  @override
  String get form_required => 'আবশ্যক';

  @override
  String get form_enterNumber => 'একটি সংখ্যা দিন';

  @override
  String get form_cannotBeNegative => 'ঋণাত্মক হতে পারে না';

  @override
  String get form_wholeNumberOnly => 'শুধু পূর্ণ সংখ্যা';

  @override
  String get form_enterValidAmount => 'সঠিক পরিমাণ দিন';

  @override
  String get unit_byPiece => 'পিস হিসেবে';

  @override
  String get unit_byWeight => 'ওজন হিসেবে';

  @override
  String get unit_byVolume => 'আয়তন হিসেবে';

  @override
  String get unit_hintPiece =>
      'পুরো পিস হিসেবে গোনা — সাবান, বোতলজাত পানীয়, প্যাকেট।';

  @override
  String get unit_hintWeight => 'ওজনে বিক্রি — চাল, আলু, ডাল, চিনি।';

  @override
  String get unit_hintVolume => 'আয়তনে বিক্রি — খোলা তেল, দুধ, কেরোসিন।';

  @override
  String get inventory_formAddTitle => 'পণ্য যোগ';

  @override
  String get inventory_formEditTitle => 'পণ্য এডিট';

  @override
  String get inventory_formHowSold => 'এই পণ্য কীভাবে বিক্রি হয়?';

  @override
  String get inventory_formName => 'নাম *';

  @override
  String get inventory_formBrand => 'ব্র্যান্ড';

  @override
  String get inventory_formVariant =>
      'ভ্যারিয়েন্ট (যেমন ৫০০ মিলি, ১ কেজি প্যাক)';

  @override
  String get inventory_formReorderAt => 'রিঅর্ডার সীমা';

  @override
  String inventory_formBuyingPrice(String perUnit) {
    return 'কেনা দাম$perUnit *';
  }

  @override
  String inventory_formSellingPrice(String perUnit) {
    return 'বিক্রি দাম$perUnit *';
  }

  @override
  String get inventory_formCreate => 'তৈরি করুন';

  @override
  String get inventory_formSaveChanges => 'পরিবর্তন সংরক্ষণ';

  @override
  String get inventory_formTryExample => 'একটি উদাহরণ দেখুন';

  @override
  String get inventory_formStockPieces => 'স্টক (পিস) *';

  @override
  String get inventory_formStock => 'স্টক *';

  @override
  String get common_save => 'সংরক্ষণ';

  @override
  String get common_add => 'যোগ';

  @override
  String get common_rename => 'নাম বদল';

  @override
  String get category_noShop => 'এই অ্যাকাউন্টে কোনো দোকান নেই।';

  @override
  String get category_renameTitle => 'ক্যাটাগরির নাম বদল';

  @override
  String get category_deleteTitle => 'ক্যাটাগরি মুছবেন?';

  @override
  String category_deleteBodyEmpty(String name) {
    return '\"$name\" সরিয়ে ফেলা হবে।';
  }

  @override
  String category_deleteBodyUsed(String name, int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countStringটি পণ্য',
      one: '১টি পণ্য',
    );
    return '\"$name\" সরিয়ে ফেলা হবে। $_temp0 ক্যাটাগরিহীন হবে (মুছে যাবে না)।';
  }

  @override
  String get category_addTooltip => 'ক্যাটাগরি যোগ';

  @override
  String get category_couldNotLoad => 'ক্যাটাগরি লোড করা যায়নি। রিফ্রেশ করুন।';

  @override
  String category_productCount(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countStringটি পণ্য',
      one: '১টি পণ্য',
    );
    return '$_temp0';
  }

  @override
  String get category_noneYet => 'এখনো কোনো ক্যাটাগরি নেই।';

  @override
  String get category_tapToAdd => 'যোগ করতে + চাপুন।';

  @override
  String get category_fieldLabel => 'ক্যাটাগরি';

  @override
  String get category_none => 'কোনো ক্যাটাগরি নয়';

  @override
  String get category_addNew => 'নতুন ক্যাটাগরি যোগ';

  @override
  String get category_alreadyExists => 'আগে থেকেই আছে — বেছে দেওয়া হলো';

  @override
  String get category_newTitle => 'নতুন ক্যাটাগরি';

  @override
  String get category_nameLabel => 'ক্যাটাগরির নাম';

  @override
  String get category_nameHint => 'যেমন ফ্রোজেন আইটেম';

  @override
  String get common_clear => 'খালি করুন';

  @override
  String get common_remove => 'মুছুন';

  @override
  String get common_quantity => 'পরিমাণ';

  @override
  String get common_subtotal => 'সাবটোটাল';

  @override
  String get common_couldNotRecognize =>
      'পণ্য শনাক্ত করা যায়নি। আবার চেষ্টা করুন।';

  @override
  String get cart_title => 'কার্ট';

  @override
  String cart_itemsInCart(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countStringটি পণ্য কার্টে',
      one: '১টি পণ্য কার্টে',
    );
    return '$_temp0';
  }

  @override
  String get cart_clearTitle => 'কার্ট খালি করবেন?';

  @override
  String get cart_clearBody =>
      'এটি কার্টের সব পণ্য সরিয়ে দেবে। কিছু বিক্রি হবে না।';

  @override
  String get cart_keep => 'থাক';

  @override
  String cart_totalItems(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countStringটি পণ্য',
      one: '১টি পণ্য',
    );
    return 'মোট · $_temp0';
  }

  @override
  String get cart_checkout => 'চেকআউট';

  @override
  String get cart_selling => 'বিক্রি হচ্ছে…';

  @override
  String get cart_empty => 'আপনার কার্ট খালি';

  @override
  String get cart_emptyHint =>
      'পণ্য বা স্ক্যান থেকে পণ্য যোগ করে বিক্রি শুরু করুন, তারপর এখানে চেকআউট করুন।';

  @override
  String cart_itemsSold(int count, String total) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countStringটি পণ্য বিক্রি',
      one: '১টি পণ্য বিক্রি',
    );
    return '$_temp0 · $total';
  }

  @override
  String get cart_checkoutFailed => 'চেকআউট ব্যর্থ। আবার চেষ্টা করুন।';

  @override
  String get cart_addDiscount => 'ছাড় দিন';

  @override
  String get cart_discount => 'ছাড়';

  @override
  String get cart_discountTitle => 'ছাড়';

  @override
  String get cart_discountAmount => 'ছাড়ের পরিমাণ';

  @override
  String get cart_discountRemove => 'ছাড় সরান';

  @override
  String cart_discountBelowCost(String amount) {
    return 'এই বিক্রিতে $amount লোকসান হবে';
  }

  @override
  String get cart_apply => 'প্রয়োগ করুন';

  @override
  String cart_pricePerUnit(String price, String unit) {
    return '$price / $unit';
  }

  @override
  String cart_barSummary(int count, String total) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countStringটি পণ্য',
      one: '১টি পণ্য',
    );
    return '$_temp0 · $total';
  }

  @override
  String get addToCart_noMore => 'যোগ করার মতো আর নেই।';

  @override
  String addToCart_available(String qty, String unit) {
    return '$qty $unit যোগ করা যাবে';
  }

  @override
  String get restock_confirmTitle => 'রিস্টক নিশ্চিত করুন';

  @override
  String restock_inStock(String qty) {
    return 'স্টকে: $qty';
  }

  @override
  String get restock_unitCost => 'একক খরচ';

  @override
  String get restock_totalCost => 'মোট খরচ';

  @override
  String get scan_failed => 'স্ক্যান ব্যর্থ। আবার চেষ্টা করুন।';

  @override
  String scan_addedToCart(String name) {
    return '$name কার্টে যোগ হয়েছে';
  }

  @override
  String scan_read(String details) {
    return 'পড়া হয়েছে: $details';
  }

  @override
  String get scan_didYouMean => 'আপনি কি এটি বোঝাতে চেয়েছেন?';

  @override
  String get scan_noMatchPick => 'মেলেনি — পণ্য বেছে নিন';

  @override
  String get scan_searchProducts => 'পণ্য খুঁজুন';

  @override
  String get history_title => 'বিক্রির হিসাব';

  @override
  String get history_search => 'বিক্রি খুঁজুন';

  @override
  String get history_couldNotLoad =>
      'বিক্রির হিসাব লোড করা যায়নি। রিফ্রেশ করুন।';

  @override
  String get history_noSalesYet => 'এখনো কোনো বিক্রি হয়নি।';

  @override
  String history_noSalesOnDay(String date) {
    return '$date তারিখে কোনো বিক্রি নেই।';
  }

  @override
  String get history_emptyHint =>
      'পণ্য থেকে একটি পণ্যে চাপ দিন → কার্টে যোগ করুন, অথবা কার্ট বার দিয়ে চেকআউট করে বিক্রি রেকর্ড করুন।';

  @override
  String get history_noMatch => 'আপনার খোঁজার সাথে কোনো বিক্রি মেলেনি।';

  @override
  String get history_saleFallback => 'বিক্রি';

  @override
  String get history_colTime => 'সময়';

  @override
  String get history_colItem => 'পণ্য';

  @override
  String get history_colQty => 'পরিমাণ';

  @override
  String get history_colAmount => 'মোট';

  @override
  String get saleDetail_title => 'বিক্রির বিবরণ';

  @override
  String get saleDetail_soldOn => 'বিক্রির সময়';

  @override
  String get saleDetail_quantity => 'পরিমাণ';

  @override
  String get saleDetail_priceEach => 'প্রতি একক দাম';

  @override
  String get saleDetail_total => 'মোট';

  @override
  String get saleDetail_cost => 'খরচ';

  @override
  String get saleDetail_profit => 'লাভ';

  @override
  String get saleDetail_enteredBy => 'যেভাবে এন্ট্রি হয়েছে';

  @override
  String get saleDetail_frozenNote => 'দাম বিক্রির মুহূর্তেই স্থির হয়ে যায়।';

  @override
  String get saleDetail_notFound => 'বিক্রি খুঁজে পাওয়া যায়নি।';

  @override
  String get saleDetail_sourceManual => 'ম্যানুয়াল';

  @override
  String get saleDetail_sourceVoice => 'ভয়েস';

  @override
  String get saleDetail_sourcePhoto => 'ছবি স্ক্যান';

  @override
  String get analytics_kicker => 'ব্যবসার রিপোর্ট';

  @override
  String get analytics_title => 'রিপোর্ট';

  @override
  String get analytics_noSalesPeriod => 'এই সময়ে এখনো কোনো বিক্রি নেই।';

  @override
  String get analytics_revenueSource => 'আয় কোথা থেকে আসছে';

  @override
  String get analytics_topShare => 'সেরা অংশ';

  @override
  String get analytics_biggestWins => 'সেরা বিক্রি';

  @override
  String analytics_carrying(String name, String scope) {
    return '$scope $name সবচেয়ে এগিয়ে।';
  }

  @override
  String get analytics_scopeToday => 'আজ';

  @override
  String get analytics_scopeWeek => 'এই সপ্তাহে';

  @override
  String get analytics_scopeMonth => 'এই মাসে';

  @override
  String get analytics_scopeAll => 'সব সময়';

  @override
  String analytics_scopeDay(String date) {
    return '$date তারিখে';
  }

  @override
  String analytics_units(String qty) {
    return '$qty একক';
  }

  @override
  String get insights_title => 'এআই ইনসাইট';

  @override
  String get insights_couldNotLoad => 'ইনসাইট লোড করা যায়নি।';

  @override
  String get insights_empty =>
      'এখনো কোনো ইনসাইট নেই।\nঅ্যাসিস্ট্যান্ট আপনার বিক্রি বিশ্লেষণ করলে এখানে ইনসাইট দেখাবে।';

  @override
  String get trends_title => 'ট্রেন্ড';

  @override
  String get trends_couldNotLoad => 'ট্রেন্ড লোড করা যায়নি।';

  @override
  String get trends_empty =>
      'এখনো কোনো ট্রেন্ড নেই।\nঅ্যাসিস্ট্যান্ট আপনার বিক্রি বিশ্লেষণ করলে এখানে ট্রেন্ড দেখাবে।';

  @override
  String get trends_noData => 'কোনো ডেটা নেই।';

  @override
  String get auth_createAccount => 'আপনার অ্যাকাউন্ট তৈরি করুন';

  @override
  String get auth_welcomeBack => 'আবার স্বাগতম';

  @override
  String get auth_noInternet =>
      'ইন্টারনেট সংযোগ নেই। ইন্টারনেটে সংযুক্ত হয়ে আবার চেষ্টা করুন।';

  @override
  String get auth_fullName => 'পুরো নাম';

  @override
  String get auth_nameRequired => 'নাম দিতে হবে';

  @override
  String get auth_email => 'ইমেইল';

  @override
  String get auth_emailRequired => 'ইমেইল দিতে হবে';

  @override
  String get auth_emailInvalid => 'সঠিক ইমেইল দিন';

  @override
  String get auth_password => 'পাসওয়ার্ড';

  @override
  String get auth_passwordRequired => 'পাসওয়ার্ড দিতে হবে';

  @override
  String get auth_passwordMin => 'কমপক্ষে ৬ অক্ষর';

  @override
  String get auth_signUp => 'সাইন আপ';

  @override
  String get auth_signIn => 'সাইন ইন';

  @override
  String get auth_continueGoogle => 'Google দিয়ে চালিয়ে যান';

  @override
  String get auth_haveAccount => 'অ্যাকাউন্ট আছে? সাইন ইন করুন';

  @override
  String get auth_noAccount => 'অ্যাকাউন্ট নেই? সাইন আপ করুন';

  @override
  String get profile_tellUs => 'আপনার দোকান সম্পর্কে বলুন';

  @override
  String get profile_shopName => 'দোকানের নাম *';

  @override
  String get profile_shopNameRequired => 'দোকানের নাম দিতে হবে';

  @override
  String get profile_address => 'ঠিকানা (ঐচ্ছিক)';

  @override
  String get profile_phone => 'ফোন (ঐচ্ছিক)';

  @override
  String get profile_createShop => 'দোকান তৈরি করুন';

  @override
  String get welcome_headline => 'আপনার দোকান\nআরও স্মার্টভাবে চালান';

  @override
  String get welcome_subtitle =>
      'পণ্য হিসাব রাখুন, কথা বা ছবিতে বিক্রি রেকর্ড করুন, আর এক নজরে লাভ দেখুন।';

  @override
  String get welcome_getStarted => 'শুরু করুন';

  @override
  String get nav_home => 'হোম';

  @override
  String get nav_items => 'পণ্য';

  @override
  String get nav_reports => 'রিপোর্ট';

  @override
  String get nav_history => 'হিসাব';

  @override
  String get common_continue => 'চালিয়ে যান';

  @override
  String get onboarding_languageTitle => 'আপনার ভাষা বেছে নিন';

  @override
  String get onboarding_languageSubtitle =>
      'পরে যেকোনো সময় সেটিংসে এটি বদলাতে পারবেন।';

  @override
  String onboarding_step(int current, int total) {
    final intl.NumberFormat currentNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String currentString = currentNumberFormat.format(current);
    final intl.NumberFormat totalNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String totalString = totalNumberFormat.format(total);

    return 'ধাপ $currentString/$totalString';
  }

  @override
  String get onboarding_defaultCurrency => 'ডিফল্ট মুদ্রা *';

  @override
  String get customers_title => 'গ্রাহক';

  @override
  String customers_receivablesHeader(String amount, int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString জন গ্রাহকের',
      one: '১ জন গ্রাহকের',
    );
    return '$_temp0 কাছে $amount পাওনা';
  }

  @override
  String get customers_empty => 'এখনো কোনো গ্রাহক নেই';

  @override
  String get customers_emptyHint =>
      'খাতা শুরু করতে একজন গ্রাহক যোগ করুন, অথবা চেকআউটে বাকি বেছে নিন।';

  @override
  String get customers_searchHint => 'নাম বা ফোন নম্বর দিয়ে খুঁজুন';

  @override
  String get customers_add => 'গ্রাহক যোগ';

  @override
  String get customers_edit => 'গ্রাহক এডিট';

  @override
  String get customers_fieldName => 'নাম';

  @override
  String get customers_fieldPhone => 'ফোন';

  @override
  String get customers_fieldNote => 'নোট (ঐচ্ছিক)';

  @override
  String get customers_nameRequired => 'নাম দিন';

  @override
  String get customers_phoneRequired => 'ফোন নম্বর দিন';

  @override
  String get customers_save => 'সংরক্ষণ';

  @override
  String get customers_delete => 'গ্রাহক মুছুন';

  @override
  String customers_deleteConfirmTitle(String name) {
    return '$name মুছবেন?';
  }

  @override
  String get customers_deleteConfirmBody =>
      'এটি গ্রাহক এবং তার খাতার হিসাব মুছে দেবে। শুধু হিসাব মেটানো গ্রাহকদের মুছা যাবে।';

  @override
  String customers_owes(String amount) {
    return '$amount বাকি';
  }

  @override
  String get customers_settled => 'পরিশোধিত';

  @override
  String get customers_balance => 'ব্যালেন্স';

  @override
  String get customers_ledgerEmpty => 'এখনো খাতায় কোনো হিসাব নেই';

  @override
  String get customers_recordPayment => 'টাকা জমা করুন';

  @override
  String get customers_paymentAmount => 'পরিমাণ';

  @override
  String get customers_paymentNote => 'নোট (ঐচ্ছিক)';

  @override
  String get customers_paymentAmountRequired => 'পরিমাণ দিন';

  @override
  String get customers_paymentTooLarge => 'বাকির চেয়ে বেশি';

  @override
  String get customers_paymentRecorded => 'টাকা জমা হয়েছে';

  @override
  String get customers_ledgerCreditSale => 'বাকিতে বিক্রি';

  @override
  String get customers_ledgerPayment => 'জমা';

  @override
  String get cart_paymentCash => 'নগদ';

  @override
  String get cart_paymentCredit => 'বাকি';

  @override
  String get cart_selectCustomer => 'গ্রাহক বেছে নিন';

  @override
  String cart_addToKhata(String name) {
    return '$name-এর খাতায় যোগ করুন';
  }

  @override
  String cart_addedToKhata(String name, String total) {
    return '$name-এর খাতায় যোগ হয়েছে · $total';
  }

  @override
  String get dashboard_receivablesTitle => 'পাওনা';

  @override
  String get voice_title => 'বিক্রির কথা বলুন';

  @override
  String get voice_hintIdle => 'মাইকে ট্যাপ করে বলুন কী বিক্রি হয়েছে';

  @override
  String get voice_recording => 'শুনছি…';

  @override
  String get voice_thinking => 'বুঝে নিচ্ছি…';

  @override
  String get voice_stageHeard => 'শুনেছি';

  @override
  String get voice_stageUnderstanding => 'কী বললেন বুঝছি';

  @override
  String get voice_stageMatching => 'আপনার পণ্য খুঁজছি';

  @override
  String get voice_thinkingDismissHint => 'তৈরি হলে জানিয়ে দেব';

  @override
  String get voice_thinkingMinimize => 'পিছনে চলতে থাকুক';

  @override
  String get voice_bannerWorking => 'ভয়েস বিক্রি নিয়ে কাজ চলছে…';

  @override
  String get voice_bannerCancel => 'এই ভয়েস বিক্রি বাতিল করুন';

  @override
  String get voice_bannerReady => 'আপনার ভয়েস বিক্রি তৈরি';

  @override
  String get voice_bannerFailed => 'ভয়েস বিক্রিটি একবার দেখুন';

  @override
  String get voice_bannerAction => 'দেখুন';

  @override
  String get voice_heard => 'আমি শুনেছি';

  @override
  String get voice_recheck => 'আবার দেখুন';

  @override
  String get voice_whichOne => 'কোনটি?';

  @override
  String get voice_pick => 'বেছে নিন';

  @override
  String get voice_addToCart => 'কার্টে যোগ করুন';

  @override
  String get voice_assumedQty => '১ ধরে নেওয়া হয়েছে — দেখে নিন';

  @override
  String voice_lowStock(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'স্টকে আছে মাত্র $countStringটি';
  }

  @override
  String get voice_errNoSpeech => 'শুনতে পাইনি। আবার চেষ্টা করুন।';

  @override
  String get voice_errNoMatch => 'আপনার বলা কিছুই মেলাতে পারিনি।';

  @override
  String get voice_errMicDenied =>
      'মাইক্রোফোনের অনুমতি বন্ধ আছে। সেটিংসে গিয়ে চালু করুন।';

  @override
  String get voice_errOffline =>
      'আপনি অফলাইনে আছেন। ইন্টারনেট চালু করে আবার চেষ্টা করুন।';

  @override
  String get voice_errTooQuiet =>
      'মাইক্রোফোন কোনো শব্দ পায়নি। ফোনটি আরও কাছে ধরে আবার চেষ্টা করুন।';

  @override
  String get voice_retry => 'আবার চেষ্টা করুন';

  @override
  String get voice_recordAgain => 'আবার রেকর্ড করুন';

  @override
  String get voice_typeInstead => 'লিখে দিন';

  @override
  String voice_stoppingIn(int seconds) {
    return '$seconds সেকেন্ডে বন্ধ হবে';
  }

  @override
  String get voice_speakCloser => 'শুনতে পাচ্ছি না — ফোনটি আরও কাছে ধরুন';

  @override
  String get voice_levelLabel => 'মাইক্রোফোনের মাত্রা';
}
