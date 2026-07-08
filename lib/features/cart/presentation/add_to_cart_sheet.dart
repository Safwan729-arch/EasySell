import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/haptics.dart';
import '../../../shared/extensions/format.dart';
import '../../auth/data/auth_repository.dart';
import '../../inventory/domain/product.dart';
import '../domain/cart_math.dart';
import 'cart_controller.dart';

/// Bottom sheet for staging [product] into the cart. Mirrors the sale
/// confirmation sheet's quantity stepper, but "Add to cart" only stages the
/// line locally -- nothing commits until checkout on the Cart screen.
Future<bool?> showAddToCartSheet(
  BuildContext context, {
  required Product product,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (_) => _AddToCartSheet(product: product),
  );
}

class _AddToCartSheet extends ConsumerStatefulWidget {
  const _AddToCartSheet({required this.product});

  final Product product;

  @override
  ConsumerState<_AddToCartSheet> createState() => _AddToCartSheetState();
}

class _AddToCartSheetState extends ConsumerState<_AddToCartSheet> {
  late double _qty;

  double get _step => stepForUnit(widget.product.unit);

  @override
  void initState() {
    super.initState();
    final remaining = ref
        .read(cartControllerProvider.notifier)
        .remainingStockFor(widget.product);
    _qty = remaining <= 0 ? 0 : _step.clamp(0, remaining).toDouble();
  }

  String _fmtQty(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  void _add() {
    ref.read(cartControllerProvider.notifier).addOrIncrement(widget.product, _qty);
    AppHaptics.success();
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final product = widget.product;
    final currency = ref.watch(myShopProvider).value?.currency ?? 'USD';
    final maxQty = ref.read(cartControllerProvider.notifier).remainingStockFor(product);
    final outOfStock = maxQty <= 0;
    final total = product.sellingPrice * _qty;

    final subtitle = [
      if (product.brand?.isNotEmpty ?? false) product.brand!,
      if (product.variant?.isNotEmpty ?? false) product.variant!,
    ].join(' · ');

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add to cart', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(product.name, style: theme.textTheme.titleMedium),
          if (subtitle.isNotEmpty)
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            outOfStock
                ? 'No more available to add.'
                : '${Product.trimNum(maxQty)} ${product.unitLabel} available to add',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Quantity', style: theme.textTheme.titleSmall),
              Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: _qty <= _step
                        ? null
                        : () {
                            AppHaptics.tap();
                            setState(() => _qty -= _step);
                          },
                    icon: const Icon(Icons.remove),
                  ),
                  SizedBox(
                    width: 88,
                    child: Text(
                      '${_fmtQty(_qty)} ${product.unitLabel}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: (_qty + _step > maxQty + 1e-9)
                        ? null
                        : () {
                            AppHaptics.tap();
                            setState(() => _qty += _step);
                          },
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Subtotal', style: theme.textTheme.titleMedium),
              Text(
                Money.format(total, currencyCode: currency),
                style: theme.textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: (outOfStock || _qty <= 0) ? null : _add,
                  child: const Text('Add to cart'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
