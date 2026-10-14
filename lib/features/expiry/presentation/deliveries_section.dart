import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/theme.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../shared/extensions/format.dart';
import '../../inventory/domain/product.dart';
import '../domain/expiry_estimate.dart';
import '../domain/product_batch.dart';
import 'batch_actions_controller.dart';
import 'batch_action_feedback.dart';
import 'batch_form_sheet.dart';
import 'expiry_date_field.dart';
import 'expiry_providers.dart';

/// The product page's Deliveries list (spec §5): each open delivery with its
/// dates, estimated amount left and status, plus a short closed history.
class DeliveriesSection extends ConsumerWidget {
  const DeliveriesSection({super.key, required this.product});

  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final expiry = ref.watch(productExpiryProvider)[product.id];
    final closed =
        ref.watch(closedBatchesProvider(product.id)).value ??
        const <ProductBatch>[];
    final open = expiry?.batches ?? const <BatchEstimate>[];

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.expiry_deliveries, style: theme.textTheme.titleMedium),
          for (final e in open) _DeliveryRow(product: product, estimate: e),
          if (product.quantity > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => showBatchFormSheet(context, product: product),
                icon: const Icon(Icons.event_available_outlined, size: 18),
                label: Text(l10n.expiry_addDate),
              ),
            ),
          if (closed.isNotEmpty)
            Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  l10n.expiry_closedHistory,
                  style: theme.textTheme.bodyMedium,
                ),
                children: [
                  for (final b in closed)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(_closedLabel(context, b.closedReason)),
                      subtitle: Text(
                        l10n.expiry_rowDates(
                          formatExpiryDate(context, b.receivedOn),
                          formatExpiryDate(context, b.expiryDate),
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

  String _closedLabel(BuildContext context, String? reason) {
    final l10n = context.l10n;
    return switch (reason) {
      BatchCloseReason.removed => l10n.expiry_closedRemoved,
      BatchCloseReason.noneLeft => l10n.expiry_closedNoneLeft,
      BatchCloseReason.notExpired => l10n.expiry_closedNotExpired,
      _ => l10n.expiry_closedSoldOut,
    };
  }
}

class _DeliveryRow extends ConsumerWidget {
  const _DeliveryRow({required this.product, required this.estimate});

  final Product product;
  final BatchEstimate estimate;

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
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
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.common_cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.expiry_removeFromStock),
          ),
        ],
      ),
    );
    if (yes != true) return;
    final ok = await ref
        .read(batchActionsControllerProvider.notifier)
        .removeExpired([estimate.batch.id]);
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
                  final messenger = ScaffoldMessenger.of(context);
                  final ok = await ref
                      .read(batchActionsControllerProvider.notifier)
                      .markNoneLeft(b.id);
                  if (!ok) showBatchActionFailure(messenger, l10n, ref);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit', child: Text(l10n.common_edit)),
                  PopupMenuItem(
                    value: 'none',
                    child: Text(l10n.expiry_noneLeft),
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
