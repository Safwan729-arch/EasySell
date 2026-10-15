import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/theme.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../shared/extensions/format.dart';
import '../../auth/data/auth_repository.dart';
import '../../inventory/domain/product.dart';
import '../domain/expiry_estimate.dart';
import '../domain/removal_loss.dart';
import 'batch_actions_controller.dart';
import 'batch_action_feedback.dart';
import 'batch_form_sheet.dart';
import 'expiry_date_field.dart';
import 'expiry_providers.dart';

/// The product page's Deliveries list (spec §5): each open delivery with its
/// dates, estimated amount left and status, plus what removals have cost.
class DeliveriesSection extends ConsumerWidget {
  const DeliveriesSection({super.key, required this.product});

  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final expiry = ref.watch(productExpiryProvider)[product.id];
    final loss =
        ref.watch(removalLossProvider(product.id)).value ?? RemovalLoss.none;
    final currency = ref.watch(myShopProvider).value?.currency ?? 'USD';
    final open = expiry?.batches ?? const <BatchEstimate>[];

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.expiry_deliveries, style: theme.textTheme.titleMedium),
          for (final e in open) _DeliveryRow(product: product, estimate: e),
          // Stock in no delivery (all of a soap's). The product form has no
          // stock box, so this row is how such stock comes off the shelf.
          if (undatedStock(product.quantity, expiry) > 0)
            _UndatedRow(
              product: product,
              left: undatedStock(product.quantity, expiry),
            ),
          // Only while some stock has no date. Once every unit sits in a
          // delivery the link read as "you still have to add a date"; new
          // stock gets its date from Restock.
          if (undatedStock(product.quantity, expiry) > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => showBatchFormSheet(context, product: product),
                icon: const Icon(Icons.event_available_outlined, size: 18),
                label: Text(l10n.expiry_addDate),
              ),
            ),
          // One line of what removals cost, in place of a Closed list that
          // said "Removed (expired)" with no amount or money.
          if (!loss.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: theme.extension<AppColors>()!.negative,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.expiry_thrownAway(
                        Qty.format(loss.units),
                        product.unitLabel,
                        Money.format(loss.cost, currencyCode: currency),
                      ),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DeliveryRow extends ConsumerWidget {
  const _DeliveryRow({required this.product, required this.estimate});

  final Product product;
  final BatchEstimate estimate;

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final actions = ref.read(batchActionsControllerProvider.notifier);
    final bool ok;
    if (estimate.status == BatchStatus.expired) {
      // All of an expired delivery goes: the server removes the locked count.
      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            l10n.expiry_removeConfirmTitle(
              Qty.format(estimate.left),
              product.unitLabel,
              product.name,
            ),
          ),
          content: Text(l10n.expiry_removeConfirmBody),
          // Side by side, like the cart's Clear dialog: "Cancel" + "Remove
          // from stock" did not fit one row on a 360 dp phone and stacked.
          // The title already says what is removed, so the button says Remove.
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.common_cancel),
            ),
            _RemoveButton(onPressed: () => Navigator.of(ctx).pop(true)),
          ],
        ),
      );
      if (yes != true) return;
      ok = await actions.removeExpired([estimate.batch.id]);
    } else {
      // Thrown away or returned early: any amount up to what is left. Part
      // of it keeps the delivery open with the rest.
      final qty = await showDialog<double>(
        context: context,
        builder: (_) =>
            _RemoveAmountDialog(product: product, left: estimate.left),
      );
      if (qty == null) return;
      ok = await actions.removeBatch(
        estimate.batch.id,
        quantity: qty,
        left: estimate.left,
      );
    }
    if (ok) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.expiry_removed)));
    } else {
      showBatchActionFailure(messenger, l10n, ref);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final busy = ref.watch(batchActionsControllerProvider).isLoading;
    final b = estimate.batch;

    final (label, color) = switch (estimate.status) {
      BatchStatus.expired => (l10n.expiry_statusExpired, colors.negative),
      BatchStatus.expiringSoon => (l10n.expiry_statusSoon, colors.warning),
      _ => (l10n.expiry_statusGood, colors.positive),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.expiry_rowDates(
                        formatExpiryDate(context, b.receivedOn),
                        formatExpiryDate(context, b.expiryDate),
                      ),
                      style: theme.textTheme.bodyMedium,
                    ),
                    Text(
                      l10n.expiry_rowLeft(
                        Qty.format(estimate.left),
                        product.unitLabel,
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
              PopupMenuButton<String>(
                enabled: !busy,
                onSelected: (v) async {
                  if (v == 'edit') {
                    showBatchFormSheet(context, product: product, batch: b);
                    return;
                  }
                  await _confirmRemove(context, ref);
                },
                // No "None left": a sold-out delivery closes by itself. An
                // expired one has its own Remove button below.
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit', child: Text(l10n.common_edit)),
                  if (estimate.status != BatchStatus.expired)
                    PopupMenuItem(
                      value: 'remove',
                      child: Text(l10n.expiry_removeFromStock),
                    ),
                ],
              ),
            ],
          ),
          if (estimate.status == BatchStatus.expired)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36)),
              onPressed: busy ? null : () => _confirmRemove(context, ref),
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              label: Text(l10n.expiry_removeFromStock),
            ),
        ],
      ),
    );
  }
}

/// The red Remove button of the removal dialogs.
class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
    style: FilledButton.styleFrom(
      minimumSize: const Size(0, 44),
      backgroundColor: Theme.of(context).extension<AppColors>()!.negative,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20),
    ),
    onPressed: onPressed,
    child: Text(context.l10n.common_remove),
  );
}

/// "How many?" for removing part or all of a delivery that has not expired.
/// Pops the amount, or null on Cancel.
class _RemoveAmountDialog extends StatefulWidget {
  const _RemoveAmountDialog({required this.product, required this.left});

  final Product product;
  final double left;

  @override
  State<_RemoveAmountDialog> createState() => _RemoveAmountDialogState();
}

class _RemoveAmountDialogState extends State<_RemoveAmountDialog> {
  late final _amount = TextEditingController(text: plainQty(widget.left));

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  bool get _decimals => widget.product.unitType.allowsDecimal;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final unit = widget.product.unitLabel;
    final qty = double.tryParse(_amount.text.trim());
    final String? error;
    if (qty == null || qty <= 0 || (!_decimals && qty != qty.roundToDouble())) {
      error = l10n.expiry_amountInvalid;
    } else if (qty > widget.left + 1e-9) {
      error = l10n.cart_batchShort(Qty.format(widget.left), unit);
    } else {
      error = null;
    }

    return AlertDialog(
      title: Text(l10n.expiry_removeAmountTitle(widget.product.name)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.expiry_removeConfirmBody),
          const SizedBox(height: 16),
          TextField(
            controller: _amount,
            onChanged: (_) => setState(() {}),
            keyboardType: TextInputType.numberWithOptions(decimal: _decimals),
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                _decimals ? RegExp(r'[0-9.]') : RegExp(r'[0-9]'),
              ),
            ],
            decoration: InputDecoration(
              labelText: l10n.expiry_removeAmountLabel,
              suffixText: unit,
              helperText: error == null
                  ? l10n.cart_batchOptionLeft(Qty.format(widget.left), unit)
                  : null,
              errorText: error,
            ),
          ),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.common_cancel),
        ),
        _RemoveButton(
          onPressed: error == null
              ? () => Navigator.of(context).pop(qty)
              : null,
        ),
      ],
    );
  }
}

/// The stock that sits in no delivery, with the way to remove it.
class _UndatedRow extends ConsumerWidget {
  const _UndatedRow({required this.product, required this.left});

  final Product product;
  final double left;

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final qty = await showDialog<double>(
      context: context,
      builder: (_) => _RemoveAmountDialog(product: product, left: left),
    );
    if (qty == null) return;
    final ok = await ref
        .read(batchActionsControllerProvider.notifier)
        .removeUndated(product.id, quantity: qty);
    if (ok) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.expiry_removed)));
    } else {
      showBatchActionFailure(messenger, l10n, ref);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final busy = ref.watch(batchActionsControllerProvider).isLoading;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.cart_batchNoDate, style: theme.textTheme.bodyMedium),
                Text(
                  l10n.cart_batchOptionLeft(
                    Qty.format(left),
                    product.unitLabel,
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            key: const ValueKey('undated-menu'),
            enabled: !busy,
            onSelected: (_) => _remove(context, ref),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'remove',
                child: Text(l10n.expiry_removeFromStock),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
