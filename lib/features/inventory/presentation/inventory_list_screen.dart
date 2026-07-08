import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/feature_flags.dart';
import '../../../core/config/theme.dart';
import '../../../core/error/failure.dart';
import '../../../core/widgets/entrance.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/rounded_icon_tile.dart';
import '../../../core/widgets/segment_pills.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../shared/extensions/format.dart';
import '../../../shared/providers/branch_scroll_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/product.dart';
import 'category_controller.dart';
import 'inventory_controller.dart';

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

  List<Product> _filter(List<Product> products, _InvFilter active) {
    final q = _query.trim().toLowerCase();
    return products.where((p) {
      final matchesQuery =
          q.isEmpty ||
          p.name.toLowerCase().contains(q) ||
          (p.brand?.toLowerCase().contains(q) ?? false) ||
          (p.variant?.toLowerCase().contains(q) ?? false);
      final matchesFilter = switch (active) {
        _InvFilter(lowOnly: true) => p.isLowStock,
        _InvFilter(categoryId: final id?) => p.categoryId == id,
        _ => true, // All
      };
      return matchesQuery && matchesFilter;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final productsAsync = ref.watch(productsStreamProvider);
    final categories = ref.watch(usedCategoriesProvider);
    final currency = ref.watch(myShopProvider).value?.currency ?? 'USD';
    final categoryNames = {for (final c in categories) c.id: c.name};

    // Filter pills: All, Low stock, then one per in-use category.
    final filters = <_InvFilter>[
      const _InvFilter.all(),
      const _InvFilter.low(),
      for (final c in categories) _InvFilter.category(c.id, c.name),
    ];
    // If the selected category stopped having products (so its pill is gone),
    // fall back to "All" rather than showing an orphaned selection.
    final activeFilter = filters.contains(_selected)
        ? _selected
        : const _InvFilter.all();

    final products = productsAsync.value ?? const <Product>[];
    final totalValue = products.fold<double>(
      0,
      (sum, p) => sum + p.inventoryValue,
    );

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
                        Text(
                          'Inventory',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${products.length} items · '
                          '${Money.compact(totalValue, currencyCode: currency)} value',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (FeatureFlags.visionScanEnabled) ...[
                    IconButton.filled(
                      onPressed: () => context.push('/scan'),
                      icon: const Icon(Icons.qr_code_scanner),
                      tooltip: 'Scan product',
                    ),
                    const SizedBox(width: 8),
                  ],
                  IconButton.filled(
                    onPressed: () => context.push('/inventory/new'),
                    icon: const Icon(Icons.add),
                    tooltip: 'Add product',
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
                  hintText: 'Search items',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
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
                labelOf: (f) => f.label,
                onChanged: (f) => setState(() => _selected = f),
              ),
            ),
            Expanded(
              child: productsAsync.when(
                loading: () => const _ListSkeleton(),
                error: (e, _) => _ErrorState(
                  message: e is Failure
                      ? e.message
                      : 'Could not load inventory. Pull to retry.',
                  onRetry: () => ref.invalidate(productsStreamProvider),
                ),
                data: (products) {
                  final filtered = _filter(products, activeFilter);
                  if (products.isEmpty) {
                    return const _EmptyState(
                      icon: Icons.inventory_2_outlined,
                      message: 'No products yet.\nTap "Add product" to start.',
                    );
                  }
                  if (filtered.isEmpty) {
                    return const _EmptyState(
                      icon: Icons.search_off,
                      message: 'No products match your filters.',
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
  const _InvFilter.all() : label = 'All', categoryId = null, lowOnly = false;
  const _InvFilter.low()
    : label = 'Low stock',
      categoryId = null,
      lowOnly = true;
  const _InvFilter.category(this.categoryId, this.label) : lowOnly = false;

  final String label;
  final String? categoryId; // non-null only for a category filter
  final bool lowOnly;

  // Stable identity for selection matching: low stock, a category id, or "all".
  String get _key => lowOnly ? 'low' : (categoryId ?? 'all');

  @override
  bool operator ==(Object other) => other is _InvFilter && other._key == _key;

  @override
  int get hashCode => _key.hashCode;
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
class _StockText extends StatelessWidget {
  const _StockText({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final color = product.isLowStock ? colors.warning : colors.positive;
    return Text(
      '${product.quantityLabel} in stock',
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
          FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
