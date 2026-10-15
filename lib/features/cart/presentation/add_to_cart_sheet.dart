import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/haptics.dart';
import '../../../core/config/theme.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../core/widgets/sheet_header.dart';
import '../../../core/widgets/stepper_button.dart';
import '../../../shared/extensions/format.dart';
import '../../auth/data/auth_repository.dart';
import '../../expiry/presentation/expiry_providers.dart';
import '../../inventory/domain/product.dart';
import '../domain/cart_math.dart';
import 'cart_controller.dart';

/// Bottom sheet for staging [product] into the cart. Mirrors the sale
/// confirmation sheet's quantity stepper, but "Add to cart" only stages the
/// line locally -- nothing commits until checkout on the Cart screen.
Future<bool?> showAddToCartSheet(
  BuildContext context, {
  required Product product,
  String? readLabel,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _AddToCartSheet(product: product, readLabel: readLabel),
  );
}

class _AddToCartSheet extends ConsumerStatefulWidget {
  const _AddToCartSheet({required this.product, this.readLabel});

  final Product product;
  final String? readLabel;

  @override
  ConsumerState<_AddToCartSheet> createState() => _AddToCartSheetState();
}

class _AddToCartSheetState extends ConsumerState<_AddToCartSheet> {
  late double _qty;
  late final TextEditingController _qtyController;

  double get _step => stepForUnit(widget.product.unit);
  bool get _allowsDecimal => widget.product.unitType.allowsDecimal;

  /// The quantity as plain ASCII, for writing back into the text field.
  ///
  /// Deliberately NOT `Qty.format`, which localises digits through `intl`: in
  /// Bengali it returns `০.১২৩`, and `double.tryParse` cannot read that back.
  /// The field is re-parsed on every keystroke, so one snap-back used to leave
  /// text the next edit resolved to null -- silently zeroing the quantity in
  /// the app's primary locale. `discount_sheet.dart` documents the same trap.
  ///
  /// Trailing zeros are trimmed so a stepped 2.0 shows as "2", matching what
  /// `Qty.format` displayed before.
  String _fieldText(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v
        .toStringAsFixed(3)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  @override
  void initState() {
    super.initState();
    final remaining = ref
        .read(cartControllerProvider.notifier)
        .remainingStockFor(
          widget.product,
          stock: ref.read(goodStockProvider(widget.product)),
        );
    _qty = remaining <= 0 ? 0 : _step.clamp(0, remaining).toDouble();
    _qtyController = TextEditingController(text: _fieldText(_qty));
  }

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  /// Sets the quantity from a stepper button and syncs the text field to match.
  void _setQty(double v) {
    setState(() => _qty = v);
    final text = _fieldText(v);
    _qtyController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  /// Handles direct typing: parse, clamp to stock (and to whole for pieces).
  /// Only snaps the field text back when the typed value was out of range, so a
  /// mid-entry decimal like "2." is not clobbered.
  void _onFieldChanged(String raw, double remaining) {
    final parsed = double.tryParse(raw.trim());
    final clamped = clampCartQuantity(
      value: parsed ?? 0,
      remaining: remaining,
      allowsDecimal: _allowsDecimal,
    );
    setState(() => _qty = clamped);
    if (parsed != null && parsed != clamped) {
      final text = _fieldText(clamped);
      _qtyController.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  void _add() {
    ref
        .read(cartControllerProvider.notifier)
        .addOrIncrement(widget.product, _qty);
    AppHaptics.success();
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final product = widget.product;
    final currency = ref.watch(myShopProvider).value?.currency ?? 'USD';
    final goodStock = ref.watch(goodStockProvider(product));
    final expired = ref.watch(productExpiryProvider)[product.id]?.expired ?? 0;
    final maxQty = ref
        .read(cartControllerProvider.notifier)
        .remainingStockFor(product, stock: goodStock);
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
          SheetHeader(title: l10n.common_addToCart),
          const SizedBox(height: 14),
          Text(
            product.name,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (subtitle.isNotEmpty)
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (widget.readLabel != null) ...[
            const SizedBox(height: 4),
            Text(
              l10n.scan_read(widget.readLabel!),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            outOfStock
                ? l10n.addToCart_noMore
                : l10n.addToCart_available(
                    Product.trimNum(maxQty),
                    product.unitLabel,
                  ),
            style: theme.textTheme.bodyLarge?.copyWith(
              fontSize: 15,
              color: theme.extension<AppColors>()!.link,
            ),
          ),
          if (expired > 0)
            Text(
              l10n.expiry_addSheetExpiredNote(
                Qty.format(expired),
                product.unitLabel,
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.common_quantity, style: theme.textTheme.titleSmall),
              Row(
                children: [
                  StepperButton(
                    onPressed: _qty <= _step
                        ? null
                        : () {
                            AppHaptics.tap();
                            _setQty(_qty - _step);
                          },
                    icon: Icons.remove,
                  ),
                  SizedBox(
                    width: 96,
                    child: TextField(
                      controller: _qtyController,
                      enabled: !outOfStock,
                      onChanged: (v) => _onFieldChanged(v, maxQty),
                      keyboardType: TextInputType.numberWithOptions(
                        decimal: _allowsDecimal,
                      ),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge,
                      decoration: InputDecoration(
                        isDense: true,
                        suffixText: product.unitLabel,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
                  StepperButton(
                    onPressed: (_qty + _step > maxQty + 1e-9)
                        ? null
                        : () {
                            AppHaptics.tap();
                            _setQty(_qty + _step);
                          },
                    icon: Icons.add,
                  ),
                ],
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.common_subtotal, style: theme.textTheme.titleMedium),
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
                  child: Text(l10n.common_cancel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: (outOfStock || _qty <= 0) ? null : _add,
                  child: Text(l10n.common_addToCart),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
