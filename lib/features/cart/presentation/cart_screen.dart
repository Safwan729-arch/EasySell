import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/haptics.dart';
import '../../../core/error/failure.dart';
import '../../../shared/extensions/format.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/cart_line.dart';
import '../domain/cart_math.dart';
import 'cart_checkout_controller.dart';
import 'cart_controller.dart';

/// Full-screen cart review + checkout. This IS the review-before-commit step
/// for a multi-item sale -- there is no second confirmation modal, the same
/// principle as the single-item sheet just scaled to N lines.
class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  Future<void> _checkout(BuildContext context, WidgetRef ref) async {
    final lines = ref.read(cartControllerProvider);
    final itemCount = lines.length;
    final total = cartTotal(lines);
    final currency = ref.read(myShopProvider).value?.currency ?? 'USD';

    final ok = await ref
        .read(cartCheckoutControllerProvider.notifier)
        .checkout();
    if (!context.mounted || !ok) return;

    AppHaptics.success();
    context.pop();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '$itemCount ${itemCount == 1 ? 'item' : 'items'} sold · '
            '${Money.format(total, currencyCode: currency)}',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final lines = ref.watch(cartControllerProvider);
    final currency = ref.watch(myShopProvider).value?.currency ?? 'USD';
    final checkoutState = ref.watch(cartCheckoutControllerProvider);

    ref.listen<AsyncValue<void>>(cartCheckoutControllerProvider, (_, next) {
      if (next is AsyncError) {
        AppHaptics.warning();
        final message = switch (next.error) {
          Failure(:final message) => message,
          _ => 'Checkout failed. Please try again.',
        };
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Cart')),
      body: lines.isEmpty
          ? Center(
              child: Text(
                'Your cart is empty.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: lines.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) => _CartLineCard(
                line: lines[i],
                currency: currency,
                isCheckingOut: checkoutState.isLoading,
              ),
            ),
      bottomNavigationBar: lines.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            Money.format(cartTotal(lines), currencyCode: currency),
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 52),
                      ),
                      onPressed: checkoutState.isLoading
                          ? null
                          : () => _checkout(context, ref),
                      child: checkoutState.isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Checkout'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _CartLineCard extends ConsumerWidget {
  const _CartLineCard({
    required this.line,
    required this.currency,
    required this.isCheckingOut,
  });

  final CartLine line;
  final String currency;
  final bool isCheckingOut;

  double get _step => stepForUnit(line.product.unit);

  String _fmtQty(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final product = line.product;
    final subtitle = [
      if (product.brand?.isNotEmpty ?? false) product.brand!,
      if (product.variant?.isNotEmpty ?? false) product.variant!,
    ].join(' · ');
    // Exactly one line per product (see cart_math.dart), so the ceiling is
    // just the product's own stock.
    final maxQty = line.product.quantity;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    Money.format(line.subtotal, currencyCode: currency),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            IconButton.filledTonal(
              onPressed: (isCheckingOut || line.quantity <= _step)
                  ? null
                  : () {
                      AppHaptics.tap();
                      ref
                          .read(cartControllerProvider.notifier)
                          .updateQuantity(product.id, line.quantity - _step);
                    },
              icon: const Icon(Icons.remove),
            ),
            SizedBox(
              width: 64,
              child: Text(
                '${_fmtQty(line.quantity)} ${product.unitLabel}',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall,
              ),
            ),
            IconButton.filledTonal(
              onPressed: (isCheckingOut || line.quantity + _step > maxQty + 1e-9)
                  ? null
                  : () {
                      AppHaptics.tap();
                      ref
                          .read(cartControllerProvider.notifier)
                          .updateQuantity(product.id, line.quantity + _step);
                    },
              icon: const Icon(Icons.add),
            ),
            IconButton(
              tooltip: 'Remove',
              onPressed: isCheckingOut
                  ? null
                  : () => ref
                        .read(cartControllerProvider.notifier)
                        .remove(product.id),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }
}
