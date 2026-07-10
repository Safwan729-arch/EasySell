import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_bn.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('bn'),
    Locale('en'),
  ];

  /// No description provided for @settings_title.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings_title;

  /// No description provided for @common_signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get common_signOut;

  /// No description provided for @settings_sectionProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get settings_sectionProfile;

  /// No description provided for @settings_sectionShop.
  ///
  /// In en, this message translates to:
  /// **'Shop'**
  String get settings_sectionShop;

  /// No description provided for @settings_sectionAssistant.
  ///
  /// In en, this message translates to:
  /// **'Assistant'**
  String get settings_sectionAssistant;

  /// No description provided for @settings_sectionAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settings_sectionAppearance;

  /// No description provided for @settings_sectionInventory.
  ///
  /// In en, this message translates to:
  /// **'Inventory'**
  String get settings_sectionInventory;

  /// No description provided for @settings_sectionLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settings_sectionLanguage;

  /// No description provided for @settings_appLanguage.
  ///
  /// In en, this message translates to:
  /// **'App language'**
  String get settings_appLanguage;

  /// No description provided for @settings_guestSession.
  ///
  /// In en, this message translates to:
  /// **'Guest session'**
  String get settings_guestSession;

  /// No description provided for @settings_signedIn.
  ///
  /// In en, this message translates to:
  /// **'Signed in'**
  String get settings_signedIn;

  /// No description provided for @settings_anonymousData.
  ///
  /// In en, this message translates to:
  /// **'Anonymous — data is tied to this device'**
  String get settings_anonymousData;

  /// No description provided for @settings_shopName.
  ///
  /// In en, this message translates to:
  /// **'Shop name'**
  String get settings_shopName;

  /// No description provided for @settings_address.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get settings_address;

  /// No description provided for @settings_phone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get settings_phone;

  /// No description provided for @settings_currency.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get settings_currency;

  /// No description provided for @settings_aiInsights.
  ///
  /// In en, this message translates to:
  /// **'AI Insights'**
  String get settings_aiInsights;

  /// No description provided for @settings_aiInsightsSub.
  ///
  /// In en, this message translates to:
  /// **'Suggestions from the assistant'**
  String get settings_aiInsightsSub;

  /// No description provided for @settings_trends.
  ///
  /// In en, this message translates to:
  /// **'Trends'**
  String get settings_trends;

  /// No description provided for @settings_trendsSub.
  ///
  /// In en, this message translates to:
  /// **'Sales trend dashboards'**
  String get settings_trendsSub;

  /// No description provided for @settings_themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settings_themeLight;

  /// No description provided for @settings_themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settings_themeDark;

  /// No description provided for @settings_manageCategories.
  ///
  /// In en, this message translates to:
  /// **'Manage categories'**
  String get settings_manageCategories;

  /// No description provided for @settings_manageCategoriesSub.
  ///
  /// In en, this message translates to:
  /// **'Rename, add, or remove categories'**
  String get settings_manageCategoriesSub;

  /// No description provided for @settings_archivedProducts.
  ///
  /// In en, this message translates to:
  /// **'Archived products'**
  String get settings_archivedProducts;

  /// No description provided for @settings_archivedProductsSub.
  ///
  /// In en, this message translates to:
  /// **'View and restore removed products'**
  String get settings_archivedProductsSub;

  /// No description provided for @common_restock.
  ///
  /// In en, this message translates to:
  /// **'Restock'**
  String get common_restock;

  /// No description provided for @common_sell.
  ///
  /// In en, this message translates to:
  /// **'Sell'**
  String get common_sell;

  /// No description provided for @common_period_today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get common_period_today;

  /// No description provided for @common_period_week.
  ///
  /// In en, this message translates to:
  /// **'Week'**
  String get common_period_week;

  /// No description provided for @common_period_month.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get common_period_month;

  /// No description provided for @common_period_all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get common_period_all;

  /// No description provided for @dashboard_yourShop.
  ///
  /// In en, this message translates to:
  /// **'Your shop'**
  String get dashboard_yourShop;

  /// No description provided for @dashboard_notificationsCaughtUp.
  ///
  /// In en, this message translates to:
  /// **'You\'re all caught up'**
  String get dashboard_notificationsCaughtUp;

  /// No description provided for @dashboard_notificationsHint.
  ///
  /// In en, this message translates to:
  /// **'We\'ll alert you about low stock and sales here.'**
  String get dashboard_notificationsHint;

  /// No description provided for @dashboard_salesLast7.
  ///
  /// In en, this message translates to:
  /// **'Sales · last 7 days'**
  String get dashboard_salesLast7;

  /// No description provided for @dashboard_bestDay.
  ///
  /// In en, this message translates to:
  /// **'{day} best'**
  String dashboard_bestDay(String day);

  /// No description provided for @dashboard_topPerformer.
  ///
  /// In en, this message translates to:
  /// **'TOP PERFORMER'**
  String get dashboard_topPerformer;

  /// No description provided for @dashboard_mvpBadge.
  ///
  /// In en, this message translates to:
  /// **'MVP'**
  String get dashboard_mvpBadge;

  /// No description provided for @dashboard_noSalesYet.
  ///
  /// In en, this message translates to:
  /// **'No sales yet — your best seller will appear here.'**
  String get dashboard_noSalesYet;

  /// No description provided for @dashboard_soldRevenue.
  ///
  /// In en, this message translates to:
  /// **'{units} sold · {revenue} revenue'**
  String dashboard_soldRevenue(String units, String revenue);

  /// No description provided for @dashboard_lowStock.
  ///
  /// In en, this message translates to:
  /// **'Low stock'**
  String get dashboard_lowStock;

  /// No description provided for @dashboard_viewAll.
  ///
  /// In en, this message translates to:
  /// **'View all'**
  String get dashboard_viewAll;

  /// No description provided for @dashboard_fullyStocked.
  ///
  /// In en, this message translates to:
  /// **'You\'re fully stocked — nothing needs reordering.'**
  String get dashboard_fullyStocked;

  /// No description provided for @dashboard_leftReorder.
  ///
  /// In en, this message translates to:
  /// **'{qty} left · reorder'**
  String dashboard_leftReorder(String qty);

  /// No description provided for @dashboard_couldNotLoadSummary.
  ///
  /// In en, this message translates to:
  /// **'Could not load summary.'**
  String get dashboard_couldNotLoadSummary;

  /// No description provided for @dashboard_couldNotLoadSales.
  ///
  /// In en, this message translates to:
  /// **'Could not load sales.'**
  String get dashboard_couldNotLoadSales;

  /// No description provided for @dashboard_revenuePeriod.
  ///
  /// In en, this message translates to:
  /// **'Revenue · {period}'**
  String dashboard_revenuePeriod(String period);

  /// No description provided for @dashboard_profit.
  ///
  /// In en, this message translates to:
  /// **'Profit'**
  String get dashboard_profit;

  /// No description provided for @dashboard_margin.
  ///
  /// In en, this message translates to:
  /// **'Margin'**
  String get dashboard_margin;

  /// No description provided for @dashboard_itemsSold.
  ///
  /// In en, this message translates to:
  /// **'Items sold'**
  String get dashboard_itemsSold;

  /// No description provided for @dashboard_vsYesterday.
  ///
  /// In en, this message translates to:
  /// **'vs yesterday'**
  String get dashboard_vsYesterday;

  /// No description provided for @dashboard_breakdown.
  ///
  /// In en, this message translates to:
  /// **'Breakdown'**
  String get dashboard_breakdown;

  /// No description provided for @dashboard_exactFigures.
  ///
  /// In en, this message translates to:
  /// **'{period} · exact figures'**
  String dashboard_exactFigures(String period);

  /// No description provided for @dashboard_revenue.
  ///
  /// In en, this message translates to:
  /// **'Revenue'**
  String get dashboard_revenue;

  /// No description provided for @dashboard_costOfGoods.
  ///
  /// In en, this message translates to:
  /// **'Cost of goods'**
  String get dashboard_costOfGoods;

  /// No description provided for @dashboard_grossProfit.
  ///
  /// In en, this message translates to:
  /// **'Gross profit'**
  String get dashboard_grossProfit;

  /// No description provided for @dashboard_avgItemPrice.
  ///
  /// In en, this message translates to:
  /// **'Avg item price'**
  String get dashboard_avgItemPrice;

  /// No description provided for @dashboard_viewFullReport.
  ///
  /// In en, this message translates to:
  /// **'View full report'**
  String get dashboard_viewFullReport;

  /// No description provided for @common_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get common_cancel;

  /// No description provided for @common_delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get common_delete;

  /// No description provided for @common_edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get common_edit;

  /// No description provided for @common_retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get common_retry;

  /// No description provided for @common_undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get common_undo;

  /// No description provided for @common_off.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get common_off;

  /// No description provided for @common_addToCart.
  ///
  /// In en, this message translates to:
  /// **'Add to cart'**
  String get common_addToCart;

  /// No description provided for @common_addedToCart.
  ///
  /// In en, this message translates to:
  /// **'Added to cart'**
  String get common_addedToCart;

  /// No description provided for @common_stockAdded.
  ///
  /// In en, this message translates to:
  /// **'Stock added'**
  String get common_stockAdded;

  /// No description provided for @common_somethingWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get common_somethingWrong;

  /// No description provided for @common_searchItems.
  ///
  /// In en, this message translates to:
  /// **'Search items'**
  String get common_searchItems;

  /// No description provided for @common_restore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get common_restore;

  /// No description provided for @inventory_title.
  ///
  /// In en, this message translates to:
  /// **'Inventory'**
  String get inventory_title;

  /// No description provided for @inventory_itemsValue.
  ///
  /// In en, this message translates to:
  /// **'{count} items · {value} value'**
  String inventory_itemsValue(int count, String value);

  /// No description provided for @inventory_filterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get inventory_filterAll;

  /// No description provided for @inventory_filterLowStock.
  ///
  /// In en, this message translates to:
  /// **'Low stock'**
  String get inventory_filterLowStock;

  /// No description provided for @inventory_inStock.
  ///
  /// In en, this message translates to:
  /// **'{qty} in stock'**
  String inventory_inStock(String qty);

  /// No description provided for @inventory_noProducts.
  ///
  /// In en, this message translates to:
  /// **'No products yet.\nTap \"Add product\" to start.'**
  String get inventory_noProducts;

  /// No description provided for @inventory_noMatch.
  ///
  /// In en, this message translates to:
  /// **'No products match your filters.'**
  String get inventory_noMatch;

  /// No description provided for @inventory_couldNotLoad.
  ///
  /// In en, this message translates to:
  /// **'Could not load inventory. Pull to retry.'**
  String get inventory_couldNotLoad;

  /// No description provided for @inventory_addProduct.
  ///
  /// In en, this message translates to:
  /// **'Add product'**
  String get inventory_addProduct;

  /// No description provided for @inventory_scanProduct.
  ///
  /// In en, this message translates to:
  /// **'Scan product'**
  String get inventory_scanProduct;

  /// No description provided for @inventory_couldNotLoadProduct.
  ///
  /// In en, this message translates to:
  /// **'Could not load product.'**
  String get inventory_couldNotLoadProduct;

  /// No description provided for @inventory_productGone.
  ///
  /// In en, this message translates to:
  /// **'This product no longer exists.'**
  String get inventory_productGone;

  /// No description provided for @inventory_removeTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove product?'**
  String get inventory_removeTitle;

  /// No description provided for @inventory_removeBody.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" will be removed from your inventory. Its past sales stay in your records.'**
  String inventory_removeBody(String name);

  /// No description provided for @inventory_removed.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" removed'**
  String inventory_removed(String name);

  /// No description provided for @inventory_lowStock.
  ///
  /// In en, this message translates to:
  /// **'Low stock'**
  String get inventory_lowStock;

  /// No description provided for @inventory_reorderThresholdNote.
  ///
  /// In en, this message translates to:
  /// **'At or below reorder threshold ({threshold}).'**
  String inventory_reorderThresholdNote(String threshold);

  /// No description provided for @inventory_statInStock.
  ///
  /// In en, this message translates to:
  /// **'In stock'**
  String get inventory_statInStock;

  /// No description provided for @inventory_statBuyingPrice.
  ///
  /// In en, this message translates to:
  /// **'Buying price'**
  String get inventory_statBuyingPrice;

  /// No description provided for @inventory_statSellingPrice.
  ///
  /// In en, this message translates to:
  /// **'Selling price'**
  String get inventory_statSellingPrice;

  /// No description provided for @inventory_statMarginPerUnit.
  ///
  /// In en, this message translates to:
  /// **'Margin / unit'**
  String get inventory_statMarginPerUnit;

  /// No description provided for @inventory_statInventoryValue.
  ///
  /// In en, this message translates to:
  /// **'Inventory value (cost)'**
  String get inventory_statInventoryValue;

  /// No description provided for @inventory_statReorderThreshold.
  ///
  /// In en, this message translates to:
  /// **'Reorder threshold'**
  String get inventory_statReorderThreshold;

  /// No description provided for @inventory_couldNotLoadArchived.
  ///
  /// In en, this message translates to:
  /// **'Could not load archived products. Pull to retry.'**
  String get inventory_couldNotLoadArchived;

  /// No description provided for @inventory_restored.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" restored to inventory.'**
  String inventory_restored(String name);

  /// No description provided for @inventory_couldNotRestore.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t restore \"{name}\". Please try again.'**
  String inventory_couldNotRestore(String name);

  /// No description provided for @inventory_noArchived.
  ///
  /// In en, this message translates to:
  /// **'No archived products.'**
  String get inventory_noArchived;

  /// No description provided for @inventory_archivedHint.
  ///
  /// In en, this message translates to:
  /// **'Products you remove from inventory show up here.'**
  String get inventory_archivedHint;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['bn', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'bn':
      return AppLocalizationsBn();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
