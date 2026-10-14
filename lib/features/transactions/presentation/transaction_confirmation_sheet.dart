import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/haptics.dart';
import '../../../core/error/failure.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../shared/extensions/format.dart';
import '../../auth/data/auth_repository.dart';
import '../../cart/domain/cart_math.dart';
import '../../expiry/presentation/expiry_date_field.dart';
import '../../inventory/domain/product.dart';
import 'transaction_controller.dart';

/// Shows the confirmation sheet for a RESTOCK and returns true if recorded.
/// This is the only committing sheet left in the transactions feature --
/// sales now stage into the cart via `showAddToCartSheet` and commit together
/// at checkout (see the cart feature).
Future<bool?> showRestockSheet(
  BuildContext context, {
  required Product product,
  double initialQuantity = 1,
  String source = 'manual',
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (_) => _RestockConfirmationSheet(
      product: product,
      initialQuantity: initialQuantity,
      source: source,
    ),
  );
}

class _RestockConfirmationSheet extends ConsumerStatefulWidget {
  const _RestockConfirmationSheet({
    required this.product,
    required this.initialQuantity,
    required this.source,
  });

  final Product product;
  final double initialQuantity;
  final String source;

  @override
  ConsumerState<_RestockConfirmationSheet> createState() =>
      _RestockConfirmationSheetState();
}

class _RestockConfirmationSheetState
    extends ConsumerState<_RestockConfirmationSheet> {
  late double _qty;
  DateTime? _expiry;
  String? _error;

  Product get _product => widget.product;

  /// Step size matched to the unit so weight/volume can be restocked in
  /// fractions (0.5 kg / 50 g …) while pieces step in whole units. Shared
  /// with the add-to-cart sheet and cart screen via `stepForUnit`.
  double get _step => stepForUnit(_product.unit);

  @override
  void initState() {
    super.initState();
    _qty = widget.initialQuantity.clamp(_step, double.infinity).toDouble();
  }

  Future<void> _confirm() async {
    setState(() => _error = null);
    final controller = ref.read(transactionControllerProvider.notifier);
    final ok = await controller.recordRestock(
      productId: _product.id,
      quantity: _qty,
      source: widget.source,
      expiryDate: _expiry,
    );
    if (ok) {
      AppHaptics.success();
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final currency = ref.watch(myShopProvider).value?.currency ?? 'USD';
    final isLoading = ref.watch(transactionControllerProvider).isLoading;

    ref.listen<AsyncValue<void>>(transactionControllerProvider, (_, next) {
      if (next is AsyncError) {
        AppHaptics.warning();
        setState(() {
          _error = switch (next.error) {
            Failure(:final message) => message,
            _ => l10n.common_somethingWrong,
          };
        });
      }
    });

    final total = _product.buyingPrice * _qty;
    final canConfirm = !isLoading && _qty > 0;

    final subtitle = [
      if (_product.brand?.isNotEmpty ?? false) _product.brand!,
      if (_product.variant?.isNotEmpty ?? false) _product.variant!,
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
          Text(l10n.restock_confirmTitle, style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(_product.name, style: theme.textTheme.titleMedium),
          if (subtitle.isNotEmpty)
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            l10n.restock_inStock(_product.quantityLabel),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.common_quantity, style: theme.textTheme.titleSmall),
              Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: (isLoading || _qty <= _step)
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
                      '${Qty.format(_qty)} ${_product.unitLabel}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: isLoading
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
          const SizedBox(height: 12),
          ExpiryDateField(
            value: _expiry,
            enabled: !isLoading,
            onChanged: (d) => setState(() => _expiry = d),
          ),
          const Divider(height: 24),
          _row(
            theme,
            l10n.restock_unitCost,
            Money.format(_product.buyingPrice, currencyCode: currency),
          ),
          const SizedBox(height: 8),
          _row(
            theme,
            l10n.restock_totalCost,
            Money.format(total, currencyCode: currency),
            emphasize: true,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: isLoading
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: Text(l10n.common_cancel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: canConfirm ? _confirm : null,
                  child: isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.restock_confirmTitle),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(
    ThemeData theme,
    String label,
    String value, {
    bool emphasize = false,
  }) {
    final style = emphasize
        ? theme.textTheme.titleMedium
        : theme.textTheme.bodyMedium;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(value, style: style),
      ],
    );
  }
}
