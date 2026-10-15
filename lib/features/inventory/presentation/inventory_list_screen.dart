import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/feature_flags.dart';
import '../../../core/config/theme.dart';
import '../../../core/error/failure.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../core/router/app_router.dart';
import '../../restock/presentation/restock_providers.dart';
import '../../../core/widgets/entrance.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/rounded_icon_tile.dart';
import '../../../core/widgets/segment_pills.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../shared/extensions/format.dart';
import '../../../shared/providers/branch_scroll_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../../expiry/domain/expiry_estimate.dart';
import '../../expiry/presentation/expiry_providers.dart';
import '../../voice/presentation/voice_sale_sheet.dart';
import '../domain/inventory_totals.dart';
import '../domain/product.dart';
import 'category_controller.dart';
import 'inventory_controller.dart';
import 'inventory_value_sheet.dart';

/// Live inventory list with search, category filter, and a low-stock indicator.
class InventoryListScreen extends ConsumerStatefulWidget {
  const InventoryListScreen({super.key});

  @override
  ConsumerState<InventoryListScreen> createState() =>
      _InventoryListScreenState();
}

class _InventoryListScreenState extends ConsumerState<InventoryListScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  _InvFilter _selected = const _InvFilter.all();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Re-filters ~250ms after the last keystroke so a fast typist doesn't trigger
  /// a rebuild per character. The clear button bypasses this for an instant reset.
  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = value);
    });
  }

  List<Product> _filter(
    List<Product> products,
    _InvFilter active,
    Map<String, ProductExpiry> expiry,
    Set<String> alertIds,
  ) {
    final q = _query.trim().toLowerCase();
    return products.where((p) {
      final matchesQuery =
          q.isEmpty ||
          p.name.toLowerCase().contains(q) ||
          (p.brand?.toLowerCase().contains(q) ?? false) ||
          (p.variant?.toLowerCase().contains(q) ?? false);
      final matchesFilter = switch (active) {
        _InvFilter(lowOnly: true) => p.isLowStockAt(goodStockOf(p, expiry)),
        _InvFilter(expiringOnly: true) => alertIds.contains(p.id),
        _InvFilter(categoryId: final id?) => p.categoryId == id,
        _ => true, // All
      };
      return matchesQuery && matchesFilter;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final productsAsync = ref.watch(productsStreamProvider);
    final categories = ref.watch(usedCategoriesProvider);
    final currency = ref.watch(myShopProvider).value?.currency ?? 'USD';
    final expiry = ref.watch(productExpiryProvider);
    final alertIds = {
      for (final a in ref.watch(expiryAlertsProvider)) a.product.id,
    };
    final categoryNames = {for (final c in categories) c.id: c.name};

    // Filter pills: All, Low stock, then one per in-use category.
    final filters = <_InvFilter>[
      const _InvFilter.all(),
      const _InvFilter.low(),
      const _InvFilter.expiring(),
      for (final c in categories) _InvFilter.category(c.id, c.name),
    ];
    // If the selected category stopped having products (so its pill is gone),
    // fall back to "All" rather than showing an orphaned selection.
    final activeFilter = filters.contains(_selected)
        ? _selected
        : const _InvFilter.all();

    final products = productsAsync.value ?? const <Product>[];
    // Whole-inventory figures, not the filtered view: the header describes the
    // shop, and the value must not change when a category pill is tapped.
    final totals = InventoryTotals.of(products, expiry: expiry);
    final restockCount =
        ref.watch(restockPlanProvider).value?.buyNow.length ?? 0;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title + subtitle and a blue "Add" button.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // One line always: shrinks a little on a narrow phone
                        // or a long translation instead of wrapping or cutting.
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            l10n.inventory_title,
                            maxLines: 1,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        _InventoryValueLine(totals: totals, currency: currency),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Only two actions here. With scan and voice too, four
                  // buttons squeezed the title into "Inven / tory" on a 360 dp
                  // phone; those two now sit inside the search bar.
                  Badge.count(
                    count: restockCount,
                    isLabelVisible: restockCount > 0,
                    child: IconButton.filled(
                      onPressed: () => context.push(AppRoutes.restock),
                      icon: const Icon(Icons.shopping_basket_outlined),
                      tooltip: l10n.restockPlan_title,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: () => context.push('/inventory/new'),
                    icon: const Icon(Icons.add),
                    tooltip: l10n.inventory_addProduct,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: l10n.common_searchItems,
                  prefixIcon: const Icon(Icons.search),
                  // Scan and voice live here, like the camera and mic in a
                  // phone's search bar, so the title row keeps room for the
                  // title. While typing, Clear takes their place.
                  suffixIcon: _query.isEmpty
                      ? (FeatureFlags.visionScanEnabled ||
                                FeatureFlags.voiceSaleEnabled
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (FeatureFlags.visionScanEnabled)
                                    IconButton(
                                      onPressed: () => context.push('/scan'),
                                      icon: const Icon(Icons.qr_code_scanner),
                                      tooltip: l10n.inventory_scanProduct,
                                    ),
                                  if (FeatureFlags.voiceSaleEnabled)
                                    IconButton(
                                      onPressed: () =>
                                          showVoiceSaleSheet(context, ref),
                                      icon: const Icon(Icons.mic_none),
                                      tooltip: l10n.voice_title,
                                    ),
                                  const SizedBox(width: 4),
                                ],
                              )
                            : null)
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _debounce?.cancel();
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SegmentPills<_InvFilter>(
                values: filters,
                selected: activeFilter,
                labelOf: (f) => f.lowOnly
                    ? l10n.inventory_filterLowStock
                    : f.expiringOnly
                    ? l10n.expiry_filter
                    : (f.categoryId == null
                          ? l10n.inventory_filterAll
                          : f.label),
                onChanged: (f) => setState(() => _selected = f),
              ),
            ),
            Expanded(
              child: productsAsync.when(
                loading: () => const _ListSkeleton(),
                error: (e, _) => _ErrorState(
                  message: e is Failure
                      ? e.message
                      : l10n.inventory_couldNotLoad,
                  onRetry: () => ref.invalidate(productsStreamProvider),
                ),
                data: (products) {
                  final filtered = _filter(
                    products,
                    activeFilter,
                    expiry,
                    alertIds,
                  );
                  if (products.isEmpty) {
                    return _EmptyState(
                      icon: Icons.inventory_2_outlined,
                      message: l10n.inventory_noProducts,
                    );
                  }
                  if (filtered.isEmpty) {
                    return _EmptyState(
                      icon: Icons.search_off,
                      message: l10n.inventory_noMatch,
                    );
                  }
                  return ListView.builder(
                    controller: ref.watch(branchScrollControllerProvider(1)),
                    // Bottom padding clears the floating bottom nav so the last
                    // tile is never trapped behind it.
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) => Entrance(
                      // Clamp so tiles scrolled far down don't inherit a long
                      // staggered delay; only the first screenful staggers.
                      index: i.clamp(0, 8),
                      child: _ProductTile(
                        product: filtered[i],
                        currency: currency,
                        categoryName: categoryNames[filtered[i].categoryId],
                        onTap: () =>
                            context.push('/inventory/${filtered[i].id}'),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A selectable inventory filter pill: "All", "Low stock", or a single category.
/// Equality is keyed so a rebuilt list still matches the stored selection.
@immutable
class _InvFilter {
  const _InvFilter.all()
    : label = 'All',
      categoryId = null,
      lowOnly = false,
      expiringOnly = false;
  const _InvFilter.low()
    : label = 'Low stock',
      categoryId = null,
      lowOnly = true,
      expiringOnly = false;
  const _InvFilter.expiring()
    : label = 'Expiring',
      categoryId = null,
      lowOnly = false,
      expiringOnly = true;
  const _InvFilter.category(this.categoryId, this.label)
    : lowOnly = false,
      expiringOnly = false;

  final String label;
  final String? categoryId; // non-null only for a category filter
  final bool lowOnly;
  final bool expiringOnly;

  // Stable identity for selection matching: low stock, expiring, a category
  // id, or "all".
  String get _key =>
      lowOnly ? 'low' : (expiringOnly ? 'expiring' : (categoryId ?? 'all'));

  @override
  bool operator ==(Object other) => other is _InvFilter && other._key == _key;

  @override
  int get hashCode => _key.hashCode;
}

/// The `N items · value` line under the Items title, tappable to reveal the
/// exact figures.
///
/// This line shares a narrow row with up to three action buttons, and Bengali
/// runs wider than English, so the full string frequently did not fit and was
/// silently chopped mid-number ("২৬,৫১০…"). Two things fix that, in order:
/// [Money.compact] keeps large totals short, and [FittedBox] shrinks whatever is
/// left to fit rather than truncating it — the same technique [RevenueHero] uses
/// on the dashboard. The exact figure is always one tap away regardless.
class _InventoryValueLine extends StatelessWidget {
  const _InventoryValueLine({required this.totals, required this.currency});

  final InventoryTotals totals;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: () =>
          showInventoryValueSheet(context, totals: totals, currency: currency),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        // Vertical padding only: a horizontal inset would misalign this line
        // with the title directly above it.
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  context.l10n.inventory_itemsValue(
                    totals.productCount,
                    Money.compact(totals.costValue, currencyCode: currency),
                  ),
                  maxLines: 1,
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                ),
              ),
            ),
            const SizedBox(width: 5),
            // Same affordance as the dashboard hero's expand chip, sized down to
            // sit on a subtitle without competing with it.
            Icon(Icons.open_in_full_rounded, size: 11, color: muted),
          ],
        ),
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({
    required this.product,
    required this.currency,
    required this.categoryName,
    required this.onTap,
  });

  final Product product;
  final String currency;
  final String? categoryName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle =
        categoryName ??
        [
          if (product.brand?.isNotEmpty ?? false) product.brand!,
          if (product.variant?.isNotEmpty ?? false) product.variant!,
        ].join(' · ');
    return PressableScale(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 6,
          ),
          leading: RoundedTextTile(
            text: product.name.isNotEmpty ? product.name[0].toUpperCase() : '?',
          ),
          title: Text(
            product.name,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: subtitle.isEmpty ? null : Text(subtitle),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                Money.format(product.sellingPrice, currencyCode: currency),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              _StockText(product: product),
            ],
          ),
        ),
      ),
    );
  }
}

/// In-line stock count, green when healthy and amber when at/below the reorder
/// threshold (e.g. "24 in stock" / "6 in stock").
class _StockText extends ConsumerWidget {
  const _StockText({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final isLow = product.isLowStockAt(ref.watch(goodStockProvider(product)));
    final color = isLow ? colors.warning : colors.positive;
    return Text(
      context.l10n.inventory_inStock(product.quantityLabel),
      style: theme.textTheme.labelMedium?.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// Shimmer placeholder list shown while products load — mirrors the real tile
/// layout so the screen doesn't jump when data arrives.
class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
      itemCount: 7,
      itemBuilder: (context, _) => const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Skeleton.card(height: 76),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 56,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(message, textAlign: TextAlign.center),
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: onRetry,
            child: Text(context.l10n.common_retry),
          ),
        ],
      ),
    );
  }
}
