import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../cart/domain/cart_math.dart';
import '../../inventory/domain/product.dart';
import '../domain/scan_item.dart';
import 'scan_session_controller.dart';

/// The horizontal strip of what has been scanned so far. This IS the
/// confirmation step -- it replaces the per-item modal sheet, so every state a
/// chip can be in has to be legible at a glance.
class ScanTray extends ConsumerWidget {
  const ScanTray({super.key, required this.onPick});

  /// Opens the product picker for an ambiguous or unmatched chip.
  final void Function(ScanItem item) onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(scanSessionProvider);
    final l10n = context.l10n;
    if (items.isEmpty) {
      return SizedBox(
        height: 84,
        child: Center(
          child: Text(l10n.scan_nothingYet,
              style: Theme.of(context).textTheme.bodySmall),
        ),
      );
    }
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) => _Chip(item: items[i], onPick: onPick),
      ),
    );
  }
}

class _Chip extends ConsumerWidget {
  const _Chip({required this.item, required this.onPick});

  final ScanItem item;
  final void Function(ScanItem) onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final ctl = ref.read(scanSessionProvider.notifier);

    return switch (item.status) {
      ScanItemStatus.recognizing => _Shell(
        child: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      ScanItemStatus.failed => _Shell(
        onTap: () => ctl.retry(item.id),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.refresh, size: 18),
            const SizedBox(width: 6),
            Text(l10n.common_retry),
          ],
        ),
      ),
      ScanItemStatus.ambiguous || ScanItemStatus.unmatched => _Shell(
        onTap: () => onPick(item),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.readLabel ?? l10n.scan_notIdentified,
                style: theme.textTheme.labelLarge),
            Text(l10n.scan_tapToPick, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
      ScanItemStatus.resolved => _Resolved(item: item),
    };
  }
}

class _Resolved extends ConsumerWidget {
  const _Resolved({required this.item});

  final ScanItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final ctl = ref.read(scanSessionProvider.notifier);
    final product = item.product!;

    // A resolved chip can still land at zero quantity: the product is out of
    // stock (or the cart has already claimed every unit) so `_clamp` in the
    // controller floors it to 0. `setQuantity` removes a chip that reaches
    // zero via the stepper, but `_resolve` does not -- a fresh recognition of
    // an out-of-stock product settles here directly. Silently showing "0 pcs"
    // with working +/- steppers would look like a bug; flag it instead so the
    // shopkeeper understands why it cannot be added.
    if (item.quantity <= 0) {
      return _Shell(
        flagged: true,
        onTap: () => ctl.remove(item.id),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              product.name,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.error,
                decoration: TextDecoration.lineThrough,
              ),
            ),
            Text(
              l10n.scan_outOfStock,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ),
      );
    }

    final step = stepForUnit(product.unit);
    return _Shell(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(product.name, style: theme.textTheme.labelLarge),
              Text(
                '${Product.trimNum(item.quantity)} ${product.unitLabel}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(width: 4),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => ctl.setQuantity(item.id, item.quantity - step),
            icon: const Icon(Icons.remove, size: 18),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => ctl.setQuantity(item.id, item.quantity + step),
            icon: const Icon(Icons.add, size: 18),
          ),
        ],
      ),
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.child, this.onTap, this.flagged = false});

  final Widget child;
  final VoidCallback? onTap;

  /// True for a chip that needs to visibly read as blocked (e.g. out of
  /// stock) rather than just another resolved item.
  final bool flagged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: flagged
              ? theme.colorScheme.errorContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: flagged
              ? Border.all(color: theme.colorScheme.error, width: 1)
              : null,
        ),
        child: Center(child: child),
      ),
    );
  }
}
