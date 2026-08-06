import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../shared/extensions/format.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/cart_math.dart';
import '../domain/discount_math.dart';
import 'cart_controller.dart';
import 'cart_discount_controller.dart';

/// Enters a flat amount off the whole cart. Mirrors `showAddToCartSheet`'s
/// wrapper so the discount step feels like the rest of the cart flow.
Future<void> showDiscountSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (_) => const _DiscountSheet(),
  );
}

class _DiscountSheet extends ConsumerStatefulWidget {
  const _DiscountSheet();

  @override
  ConsumerState<_DiscountSheet> createState() => _DiscountSheetState();
}

class _DiscountSheetState extends ConsumerState<_DiscountSheet> {
  late final TextEditingController _field;

  @override
  void initState() {
    super.initState();
    final current = ref.read(cartDiscountControllerProvider);
    _field = TextEditingController(text: current > 0 ? '$current' : '');
    _field.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  double get _typed => double.tryParse(_field.text.trim()) ?? 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    final currency = ref.watch(myShopProvider).value?.currency ?? 'USD';
    final lines = ref.watch(cartControllerProvider);
    final subtotal = cartTotal(lines);

    // Live as the field is typed: buying prices are already on the staged
    // products, so this costs no network call.
    final loss = lossFromDiscount(
      subtotal: subtotal,
      cost: cartCost(lines),
      discount: clampDiscount(entered: _typed, subtotal: subtotal),
    );

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.cart_discountTitle,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: Text(l10n.common_subtotal)),
              Text(
                Money.format(subtotal, currencyCode: currency),
                style: theme.textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _field,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: InputDecoration(
              labelText: l10n.cart_discountAmount,
              border: const OutlineInputBorder(),
            ),
          ),
          if (loss > 0) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: scheme.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.cart_discountBelowCost(
                      Money.format(loss, currencyCode: currency),
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.common_cancel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  // Never disabled by the warning above: selling below cost to
                  // clear stock is a deliberate act, not a mistake.
                  onPressed: () {
                    ref
                        .read(cartDiscountControllerProvider.notifier)
                        .setAmount(_typed);
                    Navigator.of(context).pop();
                  },
                  child: Text(l10n.cart_apply),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
