import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/theme.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../core/widgets/rounded_icon_tile.dart';
import '../../../shared/extensions/format.dart';
import '../../cart/domain/cart_math.dart';
import '../../cart/presentation/cart_controller.dart';
import '../../inventory/domain/product.dart';
import '../../inventory/presentation/inventory_controller.dart';
import '../../scan/presentation/product_picker_sheet.dart';
import '../domain/voice_decision.dart';
import '../domain/voice_line.dart';
import 'voice_controller.dart';

/// Presents [VoiceReviewSheet] as a modal bottom sheet -- mirrors the other
/// `show*Sheet` entry points (`showAddToCartSheet`, `showProductPickerSheet`).
Future<void> showVoiceReviewSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (_) => const VoiceReviewSheet(),
  );
}

/// The last stop before a spoken sale touches the cart: one row per line the
/// AI parsed, letting the shopkeeper fix a mishear, settle an ambiguous
/// match, or drop something entirely before anything is committed. Every
/// edit flows through [voiceControllerProvider] -- this widget stays dumb.
class VoiceReviewSheet extends ConsumerWidget {
  const VoiceReviewSheet({super.key});

  Future<void> _addToCart(BuildContext context, WidgetRef ref) async {
    final state = ref.read(voiceControllerProvider);
    final products =
        ref.read(productsStreamProvider).value ?? const <Product>[];
    final byId = {for (final p in products) p.id: p};
    final cart = ref.read(cartControllerProvider.notifier);

    for (final line in state.lines) {
      final product = byId[line.chosenProductId];
      if (product == null) continue; // settled but vanished meanwhile -- skip
      cart.addOrIncrement(product, line.quantity);
    }

    ref.read(voiceControllerProvider.notifier).reset();
    if (!context.mounted) return;
    Navigator.of(context).pop();
    // No AppRoutes constant for cart exists yet -- app_router.dart itself
    // registers this route by the raw literal.
    context.push('/cart');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final state = ref.watch(voiceControllerProvider);
    final products =
        ref.watch(productsStreamProvider).value ?? const <Product>[];
    final byId = {for (final p in products) p.id: p};

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
          Text(l10n.voice_title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            '${l10n.voice_heard} "${state.liveTranscript}"',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: state.lines.length,
              separatorBuilder: (_, _) => const Divider(height: 24),
              itemBuilder: (context, i) =>
                  _buildLine(ref, i, state.lines[i], byId),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: state.canAdd ? () => _addToCart(context, ref) : null,
              child: Text(l10n.voice_addToCart),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLine(
    WidgetRef ref,
    int index,
    VoiceLine line,
    Map<String, Product> byId,
  ) => switch (line.status) {
    VoiceLineStatus.resolved => _ResolvedRow(
      index: index,
      line: line,
      product: byId[line.chosenProductId],
    ),
    VoiceLineStatus.ambiguous => _AmbiguousRow(
      index: index,
      line: line,
      byId: byId,
    ),
    VoiceLineStatus.notFound => _NotFoundRow(index: index, line: line),
  };
}

/// A caption warning that the chosen product's stock can't cover the line's
/// quantity. Advisory only -- `record_sale_cart` remains the real authority,
/// so this never disables anything.
class _LowStockCaption extends StatelessWidget {
  const _LowStockCaption({required this.product, required this.quantity});

  final Product? product;
  final double quantity;

  @override
  Widget build(BuildContext context) {
    final product = this.product;
    if (product == null || product.quantity >= quantity) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        context.l10n.voice_lowStock(product.quantity.round()),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
        ),
      ),
    );
  }
}

/// A settled line: product name, quantity stepper, and the assumed-quantity
/// caption when the count was never actually spoken.
class _ResolvedRow extends ConsumerWidget {
  const _ResolvedRow({
    required this.index,
    required this.line,
    required this.product,
  });

  final int index;
  final VoiceLine line;
  final Product? product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final step = stepForUnit(product?.unit ?? ProductUnit.pcs);
    final name = product?.name ?? line.heard;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RoundedIconTile(
          icon: Icons.check_circle,
          color: theme.extension<AppColors>()!.positive,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: theme.textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (line.quantityAssumed)
                Text(
                  l10n.voice_assumedQty,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              _LowStockCaption(product: product, quantity: line.quantity),
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          onPressed: line.quantity <= step
              ? null
              : () => ref
                    .read(voiceControllerProvider.notifier)
                    .setQuantity(index, line.quantity - step),
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 44,
          child: Text(
            Qty.format(line.quantity),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
        ),
        IconButton.filledTonal(
          onPressed: () => ref
              .read(voiceControllerProvider.notifier)
              .setQuantity(index, line.quantity + step),
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}

/// A line the AI couldn't confidently settle: the raw heard text plus a chip
/// per candidate. Tapping a chip calls straight through to `choose`.
class _AmbiguousRow extends ConsumerWidget {
  const _AmbiguousRow({
    required this.index,
    required this.line,
    required this.byId,
  });

  final int index;
  final VoiceLine line;
  final Map<String, Product> byId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final chosenProduct = byId[line.chosenProductId];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RoundedIconTile(
              icon: Icons.error_outline,
              color: theme.extension<AppColors>()!.warning,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '"${line.heard}" × ${Qty.format(line.quantity)}',
                style: theme.textTheme.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 56),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.voice_whichOne, style: theme.textTheme.labelMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final choice in line.choices)
                    ChoiceChip(
                      label: Text(
                        byId[choice.productId]?.name ?? choice.productId,
                      ),
                      selected: line.chosenProductId == choice.productId,
                      onSelected: (_) => ref
                          .read(voiceControllerProvider.notifier)
                          .choose(index, choice.productId),
                    ),
                ],
              ),
              _LowStockCaption(product: chosenProduct, quantity: line.quantity),
            ],
          ),
        ),
      ],
    );
  }
}

/// A line nothing in the shop's inventory plausibly matched: the shopkeeper
/// either picks a real product manually or drops the line.
class _NotFoundRow extends ConsumerWidget {
  const _NotFoundRow({required this.index, required this.line});

  final int index;
  final VoiceLine line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    Future<void> pick() async {
      final products =
          ref.read(productsStreamProvider).value ?? const <Product>[];
      final picked = await showProductPickerSheet(
        context,
        products: products,
        title: l10n.voice_pick,
      );
      if (picked != null) {
        ref.read(voiceControllerProvider.notifier).choose(index, picked.id);
      }
    }

    return Row(
      children: [
        RoundedIconTile(
          icon: Icons.error_outline,
          color: theme.extension<AppColors>()!.warning,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            '"${line.heard}"',
            style: theme.textTheme.titleMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        TextButton(onPressed: pick, child: Text(l10n.voice_pick)),
        IconButton(
          onPressed: () =>
              ref.read(voiceControllerProvider.notifier).removeLine(index),
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }
}
