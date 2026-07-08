import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/haptics.dart';
import '../../../core/error/failure.dart';
import '../../../shared/extensions/format.dart';
import '../../auth/data/auth_repository.dart';
import '../../cart/presentation/add_to_cart_sheet.dart';
import '../../transactions/presentation/transaction_confirmation_sheet.dart';
import '../domain/product.dart';
import 'category_controller.dart';
import 'inventory_controller.dart';

/// Read-only product details with edit/delete and sale/restock actions. Looks
/// the product up by id from the realtime stream so it reflects live edits and
/// stock changes.
class ProductDetailScreen extends ConsumerWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsStreamProvider);
    final currency = ref.watch(myShopProvider).value?.currency ?? 'USD';

    ref.listen<AsyncValue<void>>(inventoryControllerProvider, (_, next) {
      if (next is AsyncError) {
        final message = switch (next.error) {
          Failure(:final message) => message,
          _ => 'Something went wrong. Please try again.',
        };
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      }
    });

    return productsAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Could not load product.')),
      ),
      data: (products) {
        final matches = products.where((p) => p.id == productId);
        if (matches.isEmpty) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('This product no longer exists.')),
          );
        }
        return _DetailView(product: matches.first, currency: currency);
      },
    );
  }
}

class _DetailView extends ConsumerWidget {
  const _DetailView({required this.product, required this.currency});

  final Product product;
  final String currency;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove product?'),
        content: Text(
          '"${product.name}" will be removed from your inventory. '
          'Its past sales stay in your records.',
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text(
                    'Cancel',
                    maxLines: 1,
                    overflow: TextOverflow.visible,
                    softWrap: false,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text(
                    'Delete',
                    maxLines: 1,
                    overflow: TextOverflow.visible,
                    softWrap: false,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final controller = ref.read(inventoryControllerProvider.notifier);
    final ok = await controller.delete(product.id);
    if (!ok) return; // failure SnackBar is surfaced by the screen's listener

    if (context.mounted) context.pop();
    // Soft delete → offer a one-tap Undo that restores it. The notifier (not
    // autoDispose) and the app-level messenger both outlive the popped screen.
    //
    // The framework's built-in auto-dismiss timer doesn't fire for this SnackBar
    // on device (action SnackBars stay up under accessible navigation), so we
    // run our own 5s timer and close it. Swipe-to-dismiss still works; the
    // `dismissed` guard makes closing an already-gone SnackBar a no-op, and the
    // long `duration` is just a backstop so the framework never races our timer.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!messenger.mounted) return;
      messenger.clearSnackBars();
      final snackBar = messenger.showSnackBar(
        SnackBar(
          content: Text('"${product.name}" removed'),
          duration: const Duration(seconds: 30),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              AppHaptics.tap();
              controller.restore(product.id);
            },
          ),
        ),
      );
      var dismissed = false;
      snackBar.closed.whenComplete(() => dismissed = true);
      Timer(const Duration(seconds: 5), () {
        if (!dismissed && messenger.mounted) snackBar.close();
      });
    });
  }

  Future<void> _addToCart(BuildContext context) async {
    // Manual sale entry point. // MEMBER B: a parsed voice/image intent
    // resolves to this same product + a quantity, then stages it into the
    // cart the same way — the Cart screen's checkout is the only commit path,
    // so AI output is never auto-committed.
    final added = await showAddToCartSheet(context, product: product);
    if (added == true && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Added to cart')));
    }
  }

  Future<void> _restock(BuildContext context) async {
    final recorded = await showRestockSheet(context, product: product);
    if (recorded == true && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Stock added')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subtitle = [
      if (product.brand?.isNotEmpty ?? false) product.brand!,
      if (product.variant?.isNotEmpty ?? false) product.variant!,
    ].join(' · ');

    // Resolve the category name from its id (live).
    String? categoryName;
    if (product.categoryId != null) {
      final cats = ref.watch(categoriesStreamProvider).value ?? const [];
      for (final c in cats) {
        if (c.id == product.categoryId) {
          categoryName = c.name;
          break;
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(product.name),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () =>
                context.push('/inventory/${product.id}/edit', extra: product),
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _restock(context),
                  icon: const Icon(Icons.add_box_outlined),
                  label: const Text('Restock'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: product.quantity == 0
                      ? null
                      : () => _addToCart(context),
                  icon: const Icon(Icons.add_shopping_cart),
                  label: const Text('Add to cart'),
                ),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (subtitle.isNotEmpty)
            Text(subtitle, style: Theme.of(context).textTheme.titleMedium),
          if (categoryName != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Chip(label: Text(categoryName)),
            ),
          const SizedBox(height: 16),
          if (product.isLowStock)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.warning_amber_rounded),
                title: const Text('Low stock'),
                subtitle: Text(
                  'At or below reorder threshold (${product.reorderLabel}).',
                ),
              ),
            ),
          _statTile(context, 'In stock', product.quantityLabel),
          _statTile(
            context,
            'Buying price',
            Money.format(product.buyingPrice, currencyCode: currency),
          ),
          _statTile(
            context,
            'Selling price',
            Money.format(product.sellingPrice, currencyCode: currency),
          ),
          _statTile(
            context,
            'Margin / unit',
            Money.format(product.marginPerUnit, currencyCode: currency),
          ),
          _statTile(
            context,
            'Inventory value (cost)',
            Money.format(product.inventoryValue, currencyCode: currency),
          ),
          _statTile(
            context,
            'Reorder threshold',
            product.reorderThreshold <= 0 ? 'Off' : product.reorderLabel,
          ),
        ],
      ),
    );
  }

  Widget _statTile(BuildContext context, String label, String value) {
    return ListTile(
      dense: true,
      title: Text(label),
      trailing: Text(value, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
