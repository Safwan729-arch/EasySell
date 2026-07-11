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

  @override
  String get common_cancel => 'Cancel';

  @override
  String get common_delete => 'Delete';

  @override
  String get common_edit => 'Edit';

  @override
  String get common_retry => 'Retry';

  @override
  String get common_undo => 'Undo';

  @override
  String get common_off => 'Off';

  @override
  String get common_addToCart => 'Add to cart';

  @override
  String get common_addedToCart => 'Added to cart';

  @override
  String get common_stockAdded => 'Stock added';

  @override
  String get common_somethingWrong => 'Something went wrong. Please try again.';

  @override
  String get common_searchItems => 'Search items';

  @override
  String get common_restore => 'Restore';

  @override
  String get inventory_title => 'Inventory';

  @override
  String inventory_itemsValue(int count, String value) {
    return '$count items · $value value';
  }

  @override
  String get inventory_filterAll => 'All';

  @override
  String get inventory_filterLowStock => 'Low stock';

  @override
  String inventory_inStock(String qty) {
    return '$qty in stock';
  }

  @override
  String get inventory_noProducts =>
      'No products yet.\nTap \"Add product\" to start.';

  @override
  String get inventory_noMatch => 'No products match your filters.';

  @override
  String get inventory_couldNotLoad =>
      'Could not load inventory. Pull to retry.';

  @override
  String get inventory_addProduct => 'Add product';

  @override
  String get inventory_scanProduct => 'Scan product';

  @override
  String get inventory_couldNotLoadProduct => 'Could not load product.';

  @override
  String get inventory_productGone => 'This product no longer exists.';

  @override
  String get inventory_removeTitle => 'Remove product?';

  @override
  String inventory_removeBody(String name) {
    return '\"$name\" will be removed from your inventory. Its past sales stay in your records.';
  }

  @override
  String inventory_removed(String name) {
    return '\"$name\" removed';
  }

  @override
  String get inventory_lowStock => 'Low stock';

  @override
  String inventory_reorderThresholdNote(String threshold) {
    return 'At or below reorder threshold ($threshold).';
  }

  @override
  String get inventory_statInStock => 'In stock';

  @override
  String get inventory_statBuyingPrice => 'Buying price';

  @override
  String get inventory_statSellingPrice => 'Selling price';

  @override
  String get inventory_statMarginPerUnit => 'Margin / unit';

  @override
  String get inventory_statInventoryValue => 'Inventory value (cost)';

  @override
  String get inventory_statReorderThreshold => 'Reorder threshold';

  @override
  String get inventory_couldNotLoadArchived =>
      'Could not load archived products. Pull to retry.';

  @override
  String inventory_restored(String name) {
    return '\"$name\" restored to inventory.';
  }

  @override
  String inventory_couldNotRestore(String name) {
    return 'Couldn\'t restore \"$name\". Please try again.';
  }

  @override
  String get inventory_noArchived => 'No archived products.';

  @override
  String get inventory_archivedHint =>
      'Products you remove from inventory show up here.';

  @override
  String get form_required => 'Required';

  @override
  String get form_enterNumber => 'Enter a number';

  @override
  String get form_cannotBeNegative => 'Cannot be negative';

  @override
  String get form_wholeNumberOnly => 'Whole number only';

  @override
  String get form_enterValidAmount => 'Enter a valid amount';

  @override
  String get unit_byPiece => 'By piece';

  @override
  String get unit_byWeight => 'By weight';

  @override
  String get unit_byVolume => 'By volume';

  @override
  String get unit_hintPiece =>
      'Counted as whole pieces — soap, bottled drinks, packets.';

  @override
  String get unit_hintWeight =>
      'Sold by weight — rice, potato, lentils, sugar.';

  @override
  String get unit_hintVolume => 'Sold by volume — loose oil, milk, kerosene.';

  @override
  String get inventory_formAddTitle => 'Add product';

  @override
  String get inventory_formEditTitle => 'Edit product';

  @override
  String get inventory_formHowSold => 'How is this item sold?';

  @override
  String get inventory_formName => 'Name *';

  @override
  String get inventory_formBrand => 'Brand';

  @override
  String get inventory_formVariant => 'Variant (e.g. 500ml, 1kg pack)';

  @override
  String get inventory_formReorderAt => 'Reorder at';

  @override
  String inventory_formBuyingPrice(String perUnit) {
    return 'Buying price$perUnit *';
  }

  @override
  String inventory_formSellingPrice(String perUnit) {
    return 'Selling price$perUnit *';
  }

  @override
  String get inventory_formCreate => 'Create';

  @override
  String get inventory_formSaveChanges => 'Save changes';

  @override
  String get inventory_formTryExample => 'Try a real example';

  @override
  String get inventory_formStockPieces => 'Stock (pieces) *';

  @override
  String get inventory_formStock => 'Stock *';

  @override
  String get common_save => 'Save';

  @override
  String get common_add => 'Add';

  @override
  String get common_rename => 'Rename';

  @override
  String get category_noShop => 'No shop found for this account.';

  @override
  String get category_renameTitle => 'Rename category';

  @override
  String get category_deleteTitle => 'Delete category?';

  @override
  String category_deleteBodyEmpty(String name) {
    return '\"$name\" will be removed.';
  }

  @override
  String category_deleteBodyUsed(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count products',
      one: '1 product',
    );
    return '\"$name\" will be removed. $_temp0 will become uncategorized (not deleted).';
  }

  @override
  String get category_addTooltip => 'Add category';

  @override
  String get category_couldNotLoad =>
      'Could not load categories. Pull to retry.';

  @override
  String category_productCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count products',
      one: '1 product',
    );
    return '$_temp0';
  }

  @override
  String get category_noneYet => 'No categories yet.';

  @override
  String get category_tapToAdd => 'Tap + to add one.';

  @override
  String get category_fieldLabel => 'Category';

  @override
  String get category_none => 'No category';

  @override
  String get category_addNew => 'Add new category';

  @override
  String get category_alreadyExists => 'Already exists — selected it for you';

  @override
  String get category_newTitle => 'New category';

  @override
  String get category_nameLabel => 'Category name';

  @override
  String get category_nameHint => 'e.g. Frozen items';

  @override
  String get common_clear => 'Clear';

  @override
  String get common_remove => 'Remove';

  @override
  String get common_quantity => 'Quantity';

  @override
  String get common_subtotal => 'Subtotal';

  @override
  String get common_couldNotRecognize =>
      'Could not recognize the product. Please try again.';

  @override
  String get cart_title => 'Cart';

  @override
  String cart_itemsInCart(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items in cart',
      one: '1 item in cart',
    );
    return '$_temp0';
  }

  @override
  String get cart_clearTitle => 'Clear cart?';

  @override
  String get cart_clearBody =>
      'This removes every item from the cart. Nothing is sold.';

  @override
  String get cart_keep => 'Keep';

  @override
  String cart_totalItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return 'Total · $_temp0';
  }

  @override
  String get cart_checkout => 'Checkout';

  @override
  String get cart_selling => 'Selling…';

  @override
  String get cart_empty => 'Your cart is empty';

  @override
  String get cart_emptyHint =>
      'Add products from Items or Scan to build a sale, then check out here.';

  @override
  String cart_itemsSold(int count, String total) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items sold',
      one: '1 item sold',
    );
    return '$_temp0 · $total';
  }

  @override
  String get cart_checkoutFailed => 'Checkout failed. Please try again.';

  @override
  String cart_pricePerUnit(String price, String unit) {
    return '$price / $unit';
  }

  @override
  String cart_barSummary(int count, String total) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0 · $total';
  }

  @override
  String get addToCart_noMore => 'No more available to add.';

  @override
  String addToCart_available(String qty, String unit) {
    return '$qty $unit available to add';
  }

  @override
  String get restock_confirmTitle => 'Confirm restock';

  @override
  String restock_inStock(String qty) {
    return 'In stock: $qty';
  }

  @override
  String get restock_unitCost => 'Unit cost';

  @override
  String get restock_totalCost => 'Total cost';

  @override
  String get scan_failed => 'Scan failed. Try again.';

  @override
  String scan_addedToCart(String name) {
    return 'Added $name to cart';
  }

  @override
  String get scan_didYouMean => 'Did you mean?';

  @override
  String get scan_noMatchPick => 'No match — pick the product';

  @override
  String get scan_searchProducts => 'Search products';

  @override
  String get history_title => 'Sales history';

  @override
  String get history_search => 'Search sales';

  @override
  String get history_couldNotLoad =>
      'Could not load sales history. Pull to retry.';

  @override
  String get history_noSalesYet => 'No sales recorded yet.';

  @override
  String history_noSalesOnDay(String date) {
    return 'No sales on $date.';
  }

  @override
  String get history_emptyHint =>
      'Record a sale from Items → tap a product → Add to cart, or use the cart bar to checkout.';

  @override
  String get history_noMatch => 'No sales match your search.';

  @override
  String get history_saleFallback => 'Sale';

  @override
  String get history_colTime => 'Time';

  @override
  String get history_colItem => 'Item';

  @override
  String get history_colQty => 'Qty';

  @override
  String get history_colAmount => 'Amount';

  @override
  String get analytics_kicker => 'BUSINESS REPORT';

  @override
  String get analytics_title => 'Reports';

  @override
  String get analytics_noSalesPeriod => 'No sales in this period yet.';

  @override
  String get analytics_revenueSource => 'Where revenue comes from';

  @override
  String get analytics_topShare => 'top share';

  @override
  String get analytics_biggestWins => 'Biggest wins';

  @override
  String analytics_carrying(String name, String scope) {
    return '$name is carrying $scope.';
  }

  @override
  String get analytics_scopeToday => 'today';

  @override
  String get analytics_scopeWeek => 'this week';

  @override
  String get analytics_scopeMonth => 'this month';

  @override
  String get analytics_scopeAll => 'all time';

  @override
  String analytics_scopeDay(String date) {
    return 'on $date';
  }

  @override
  String analytics_units(String qty) {
    return '$qty units';
  }

  @override
  String get insights_title => 'AI Insights';

  @override
  String get insights_couldNotLoad => 'Could not load insights.';

  @override
  String get insights_empty =>
      'No insights yet.\nAI insights will appear here once the assistant has analyzed your sales.';

  @override
  String get trends_title => 'Trends';

  @override
  String get trends_couldNotLoad => 'Could not load trends.';

  @override
  String get trends_empty =>
      'No trends yet.\nTrend dashboards will appear here once the assistant has analyzed your sales.';

  @override
  String get trends_noData => 'No data points.';
}
