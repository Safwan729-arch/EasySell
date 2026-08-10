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
  String get common_noInternet => 'No internet connection';

  @override
  String get common_searchItems => 'Search items';

  @override
  String get common_restore => 'Restore';

  @override
  String get inventory_title => 'Inventory';

  @override
  String inventory_itemsValue(int count, String value) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return '$countString items · $value';
  }

  @override
  String get inventory_valueTitle => 'Inventory value';

  @override
  String get inventory_valueExact => 'Exact figures';

  @override
  String get inventory_valueProducts => 'Products';

  @override
  String get inventory_valueRetail => 'Retail value';

  @override
  String get inventory_valuePotentialProfit => 'Potential profit';

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
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString products',
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
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString products',
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
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString items in cart',
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
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString items',
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
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString items sold',
      one: '1 item sold',
    );
    return '$_temp0 · $total';
  }

  @override
  String get cart_checkoutFailed => 'Checkout failed. Please try again.';

  @override
  String error_insufficientStock(String product) {
    return 'Not enough $product in stock';
  }

  @override
  String get error_cartEmpty => 'The cart is empty.';

  @override
  String get error_productNotFound => 'That product no longer exists.';

  @override
  String get error_customerNotFound => 'That customer no longer exists.';

  @override
  String get error_discountExceedsTotal =>
      'The discount is more than the bill.';

  @override
  String get error_discountNegative => 'A discount cannot be negative.';

  @override
  String get error_quantityNotPositive => 'Quantity must be more than zero.';

  @override
  String get cart_addDiscount => 'Add discount';

  @override
  String get cart_discount => 'Discount';

  @override
  String get cart_discountTitle => 'Discount';

  @override
  String get cart_discountAmount => 'Amount off';

  @override
  String get cart_discountEdit => 'Edit discount';

  @override
  String get cart_discountRemove => 'Remove discount';

  @override
  String cart_discountBelowCost(String amount) {
    return 'You\'d lose $amount on this sale';
  }

  @override
  String get cart_discountInvalid => 'Enter a valid amount';

  @override
  String get cart_apply => 'Apply';

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
      other: '$countString items',
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
  String scan_read(String details) {
    return 'Read: $details';
  }

  @override
  String get scan_didYouMean => 'Did you mean?';

  @override
  String get scan_noMatchPick => 'No match — pick the product';

  @override
  String get scan_searchProducts => 'Search products';

  @override
  String scan_recognizing(int count) {
    return 'Recognizing $count…';
  }

  @override
  String scan_addItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Add $count items',
      one: 'Add 1 item',
    );
    return '$_temp0';
  }

  @override
  String get scan_addEmpty => 'Add';

  @override
  String get scan_nothingYet => 'Scan something to begin';

  @override
  String get scan_tapToPick => 'Tap to pick';

  @override
  String get scan_notIdentified => 'Not identified';

  @override
  String get scan_topSellers => 'Top sellers';

  @override
  String get scan_outOfStock => 'Out of stock';

  @override
  String get scan_cameraDenied =>
      'Camera access is needed to scan. Open Settings and allow it, then try again.';

  @override
  String get scan_openSettings => 'Try again';

  @override
  String get scan_cameraUnavailable =>
      'This device has no camera to scan with.';

  @override
  String get scan_leaveTitle => 'Leave without adding?';

  @override
  String scan_leaveBody(int count) {
    return '$count scanned items have not been added to the cart.';
  }

  @override
  String get scan_discardTitle => 'Add the rest?';

  @override
  String scan_discardBody(int count) {
    return '$count items are not ready to add (unresolved or out of stock) and will be discarded.';
  }

  @override
  String get common_discard => 'Discard';

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
  String get saleDetail_title => 'Sale details';

  @override
  String get saleDetail_soldOn => 'Sold on';

  @override
  String get saleDetail_quantity => 'Quantity';

  @override
  String get saleDetail_priceEach => 'Price each';

  @override
  String get saleDetail_total => 'Total';

  @override
  String get saleDetail_discount => 'Discount';

  @override
  String get saleDetail_cost => 'Cost';

  @override
  String get saleDetail_profit => 'Profit';

  @override
  String get saleDetail_enteredBy => 'Entered by';

  @override
  String get saleDetail_frozenNote =>
      'Prices are locked in from the moment of sale.';

  @override
  String get saleDetail_notFound => 'Sale not found.';

  @override
  String get saleDetail_sourceManual => 'Manual';

  @override
  String get saleDetail_sourceVoice => 'Voice';

  @override
  String get saleDetail_sourcePhoto => 'Photo scan';

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

  @override
  String get auth_createAccount => 'Create your account';

  @override
  String get auth_welcomeBack => 'Welcome back';

  @override
  String get auth_noInternet =>
      'No internet connection. Connect to the internet and try again.';

  @override
  String get auth_fullName => 'Full name';

  @override
  String get auth_nameRequired => 'Name is required';

  @override
  String get auth_email => 'Email';

  @override
  String get auth_emailRequired => 'Email is required';

  @override
  String get auth_emailInvalid => 'Enter a valid email';

  @override
  String get auth_password => 'Password';

  @override
  String get auth_passwordRequired => 'Password is required';

  @override
  String get auth_passwordMin => 'At least 6 characters';

  @override
  String get auth_signUp => 'Sign up';

  @override
  String get auth_signIn => 'Sign in';

  @override
  String get auth_continueGoogle => 'Continue with Google';

  @override
  String get auth_haveAccount => 'Already have an account? Sign in';

  @override
  String get auth_noAccount => 'Don\'t have an account? Sign up';

  @override
  String get profile_tellUs => 'Tell us about your shop';

  @override
  String get profile_shopName => 'Shop name *';

  @override
  String get profile_shopNameRequired => 'Shop name is required';

  @override
  String get profile_address => 'Address (optional)';

  @override
  String get profile_phone => 'Phone (optional)';

  @override
  String get profile_createShop => 'Create shop';

  @override
  String get welcome_headline => 'Run your shop\nsmarter';

  @override
  String get welcome_subtitle =>
      'Track inventory, record sales by voice or photo, and see your profit at a glance.';

  @override
  String get welcome_getStarted => 'Get started';

  @override
  String get nav_home => 'Home';

  @override
  String get nav_items => 'Items';

  @override
  String get nav_reports => 'Reports';

  @override
  String get nav_history => 'History';

  @override
  String get common_continue => 'Continue';

  @override
  String get onboarding_languageTitle => 'Choose your language';

  @override
  String get onboarding_languageSubtitle =>
      'You can change this anytime in Settings.';

  @override
  String onboarding_step(int current, int total) {
    final intl.NumberFormat currentNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String currentString = currentNumberFormat.format(current);
    final intl.NumberFormat totalNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String totalString = totalNumberFormat.format(total);

    return 'Step $currentString of $totalString';
  }

  @override
  String get onboarding_defaultCurrency => 'Default currency *';

  @override
  String get customers_title => 'Customers';

  @override
  String customers_receivablesHeader(String amount, int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString customers',
      one: '1 customer',
    );
    return '$amount owed by $_temp0';
  }

  @override
  String get customers_empty => 'No customers yet';

  @override
  String get customers_emptyHint =>
      'Add a customer to start a khata, or choose Credit at checkout.';

  @override
  String get customers_searchHint => 'Search by name or phone';

  @override
  String get customers_add => 'Add customer';

  @override
  String get customers_edit => 'Edit customer';

  @override
  String get customers_fieldName => 'Name';

  @override
  String get customers_fieldPhone => 'Phone';

  @override
  String get customers_fieldNote => 'Note (optional)';

  @override
  String get customers_nameRequired => 'Enter a name';

  @override
  String get customers_phoneRequired => 'Enter a phone number';

  @override
  String get customers_save => 'Save';

  @override
  String get customers_delete => 'Delete customer';

  @override
  String customers_deleteConfirmTitle(String name) {
    return 'Delete $name?';
  }

  @override
  String get customers_deleteConfirmBody =>
      'This removes the customer and their khata history. Only settled customers can be deleted.';

  @override
  String customers_owes(String amount) {
    return 'Owes $amount';
  }

  @override
  String get customers_settled => 'Settled';

  @override
  String get customers_balance => 'Balance';

  @override
  String get customers_ledgerEmpty => 'No khata activity yet';

  @override
  String get customers_recordPayment => 'Record payment';

  @override
  String get customers_paymentAmount => 'Amount';

  @override
  String get customers_paymentNote => 'Note (optional)';

  @override
  String get customers_paymentAmountRequired => 'Enter an amount';

  @override
  String get customers_paymentTooLarge => 'More than what is owed';

  @override
  String get customers_paymentRecorded => 'Payment recorded';

  @override
  String get customers_ledgerCreditSale => 'Credit sale';

  @override
  String get customers_ledgerPayment => 'Payment';

  @override
  String get cart_paymentCash => 'Cash';

  @override
  String get cart_paymentCredit => 'Credit';

  @override
  String get cart_selectCustomer => 'Select customer';

  @override
  String cart_addToKhata(String name) {
    return 'Add to $name\'s khata';
  }

  @override
  String cart_addedToKhata(String name, String total) {
    return 'Added to $name\'s khata · $total';
  }

  @override
  String get dashboard_receivablesTitle => 'Receivables';

  @override
  String get voice_title => 'Speak a sale';

  @override
  String get voice_hintIdle => 'Tap the mic and say what you sold';

  @override
  String get voice_recording => 'Listening…';

  @override
  String get voice_thinking => 'Working it out…';

  @override
  String get voice_stageHeard => 'Heard you';

  @override
  String get voice_stageUnderstanding => 'Understanding what you said';

  @override
  String get voice_stageMatching => 'Finding your items';

  @override
  String get voice_thinkingDismissHint => 'We\'ll buzz you when it\'s ready';

  @override
  String get voice_thinkingMinimize => 'Continue in background';

  @override
  String get voice_bannerWorking => 'Working on your voice sale…';

  @override
  String get voice_bannerCancel => 'Discard this voice sale';

  @override
  String get voice_bannerReady => 'Your voice sale is ready';

  @override
  String get voice_bannerFailed => 'Your voice sale needs a look';

  @override
  String get voice_bannerAction => 'Review';

  @override
  String get voice_heard => 'I heard';

  @override
  String get voice_recheck => 'Re-check';

  @override
  String get voice_whichOne => 'Which one?';

  @override
  String get voice_pick => 'Pick';

  @override
  String get voice_addToCart => 'Add to cart';

  @override
  String get voice_assumedQty => 'Assumed 1 — check this';

  @override
  String voice_lowStock(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'Only $countString in stock';
  }

  @override
  String get voice_errNoSpeech => 'Didn\'t catch that. Try again.';

  @override
  String get voice_errNoMatch => 'Couldn\'t match anything you said.';

  @override
  String get voice_errMicDenied =>
      'Microphone access is off. Turn it on in Settings.';

  @override
  String get voice_errOffline => 'You\'re offline. Reconnect and try again.';

  @override
  String get voice_errTooQuiet =>
      'The microphone didn\'t pick up any sound. Hold the phone closer and try again.';

  @override
  String get voice_retry => 'Try again';

  @override
  String get voice_recordAgain => 'Record again';

  @override
  String get voice_typeInstead => 'Type it instead';

  @override
  String voice_stoppingIn(int seconds) {
    return 'Stopping in ${seconds}s';
  }

  @override
  String get voice_speakCloser => 'Can\'t hear you — hold the phone closer';

  @override
  String get voice_levelLabel => 'Microphone level';
}
