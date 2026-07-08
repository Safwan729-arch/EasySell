import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/haptics.dart';
import '../../../core/config/theme.dart';
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
          behavior: SnackBarBehavior.floating,
          content: Text(
            '$itemCount ${itemCount == 1 ? 'item' : 'items'} sold · '
            '${Money.format(total, currencyCode: currency)}',
          ),
        ),
      );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final cleared = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final colors = Theme.of(ctx).extension<AppColors>()!;
        return AlertDialog(
          title: const Text('Clear cart?'),
          content: const Text(
            'This removes every item from the cart. Nothing is sold.',
          ),
          // Natural-width actions: the theme forces FilledButton to a
          // full-width minimumSize, which makes a dialog's confirm button
          // dwarf the text "Keep". Reset it so both size to their content.
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Keep'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 44),
                backgroundColor: colors.negative,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Clear'),
            ),
          ],
        );
      },
    );
    if (cleared == true) {
      AppHaptics.warning();
      ref.read(cartControllerProvider.notifier).clear();
    }
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
          ..showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text(message),
            ),
          );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cart'),
        actions: [
          if (lines.isNotEmpty)
            TextButton(
              onPressed: checkoutState.isLoading
                  ? null
                  : () => _confirmClear(context, ref),
              child: const Text('Clear'),
            ),
        ],
      ),
      body: lines.isEmpty
          ? const _EmptyCart()
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemCount: lines.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      '${lines.length} ${lines.length == 1 ? 'item' : 'items'} in cart',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }
                final line = lines[i - 1];
                return _CartLineCard(
                  key: ValueKey(line.product.id),
                  line: line,
                  currency: currency,
                  isCheckingOut: checkoutState.isLoading,
                );
              },
            ),
      bottomNavigationBar: lines.isEmpty
          ? null
          : _CheckoutBar(
              total: cartTotal(lines),
              itemCount: lines.length,
              currency: currency,
              isLoading: checkoutState.isLoading,
              onCheckout: () => _checkout(context, ref),
            ),
    );
  }
}

/// The staged-item row: an icon tile, product identity + unit price, the line
/// subtotal, a quantity stepper, and an explicit Remove. Also swipe-to-delete
/// (end-to-start) for a faster gesture. Everything a shopkeeper needs to review
/// and adjust one line before checkout.
class _CartLineCard extends ConsumerWidget {
  const _CartLineCard({
    super.key,
    required this.line,
    required this.currency,
    required this.isCheckingOut,
  });

  final CartLine line;
  final String currency;
  final bool isCheckingOut;

  double get _step => stepForUnit(line.product.unit);

  void _remove(WidgetRef ref) {
    AppHaptics.tap();
    ref.read(cartControllerProvider.notifier).remove(line.product.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final scheme = theme.colorScheme;
    final product = line.product;
    final controller = ref.read(cartControllerProvider.notifier);

    final subtitle = [
      if (product.brand?.isNotEmpty ?? false) product.brand!,
      if (product.variant?.isNotEmpty ?? false) product.variant!,
    ].join(' · ');

    // Exactly one line per product (see cart_math.dart), so the ceiling is
    // just the product's own stock.
    final maxQty = product.quantity;
    final canDecrement = !isCheckingOut && line.quantity > _step;
    final canIncrement = !isCheckingOut && line.quantity + _step <= maxQty + 1e-9;

    final card = Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InitialTile(
                  label: product.name.isNotEmpty
                      ? product.name.characters.first.toUpperCase()
                      : '?',
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      const SizedBox(height: 3),
                      Text(
                        '${Money.format(product.sellingPrice, currencyCode: currency)} / ${product.unitLabel}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  Money.format(line.subtotal, currencyCode: currency),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _QtyStepper(
                  label: '${Qty.format(line.quantity)} ${product.unitLabel}',
                  onDecrement: canDecrement
                      ? () {
                          AppHaptics.tap();
                          controller.updateQuantity(
                            product.id,
                            line.quantity - _step,
                          );
                        }
                      : null,
                  onIncrement: canIncrement
                      ? () {
                          AppHaptics.tap();
                          controller.updateQuantity(
                            product.id,
                            line.quantity + _step,
                          );
                        }
                      : null,
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: isCheckingOut ? null : () => _remove(ref),
                  style: TextButton.styleFrom(
                    foregroundColor: colors.negative,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Remove'),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    return Dismissible(
      key: ValueKey('dismiss-${product.id}'),
      direction: isCheckingOut
          ? DismissDirection.none
          : DismissDirection.endToStart,
      onDismissed: (_) => _remove(ref),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: colors.negative,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      child: card,
    );
  }
}

/// Rounded square holding a product's initial — a lightweight stand-in for a
/// product image (images are optional and often absent for staged items).
class _InitialTile extends StatelessWidget {
  const _InitialTile({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.muted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w800,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// Compact −/value/+ pill. Buttons disable (null callback) at the stock ceiling
/// and the one-step floor, matching the add-to-cart sheet's rules.
class _QtyStepper extends StatelessWidget {
  const _QtyStepper({
    required this.label,
    required this.onDecrement,
    required this.onIncrement,
  });

  final String label;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepButton(icon: Icons.remove, onTap: onDecrement),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 60),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _StepButton(icon: Icons.add, onTap: onIncrement),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    return InkResponse(
      onTap: onTap,
      radius: 22,
      child: Padding(
        padding: const EdgeInsets.all(9),
        child: Icon(
          icon,
          size: 18,
          color: enabled ? scheme.primary : scheme.onSurfaceVariant.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}

/// Bounded-height checkout bar. Uses `MainAxisSize.min` so it hugs its content
/// instead of expanding to fill the loose height Scaffold grants a
/// bottomNavigationBar (the bug that previously collapsed the item list).
class _CheckoutBar extends StatelessWidget {
  const _CheckoutBar({
    required this.total,
    required this.itemCount,
    required this.currency,
    required this.isLoading,
    required this.onCheckout,
  });

  final double total;
  final int itemCount;
  final String currency;
  final bool isLoading;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      'Total · $itemCount ${itemCount == 1 ? 'item' : 'items'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    Money.format(total, currencyCode: currency),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: isLoading ? null : onCheckout,
                  icon: isLoading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.point_of_sale, size: 20),
                  label: Text(isLoading ? 'Selling…' : 'Checkout'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown when the cart has no staged items.
class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.shopping_cart_outlined,
              size: 56,
              color: scheme.outline,
            ),
            const SizedBox(height: 14),
            Text(
              'Your cart is empty',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Add products from Items or Scan to build a sale, then check out here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
