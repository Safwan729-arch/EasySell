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
import '../domain/voice_line.dart';
import '../domain/voice_parse_result.dart';
import 'voice_controller.dart';

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

    // Defensive re-check at commit time. The footer button is already gated
    // on every line being effectively settled, but a product can vanish in
    // the gap between the button lighting up and this handler running --
    // never write a partial cart: if anything fails to resolve here, abort
    // the WHOLE add and leave the sheet open so the (now-unsettled) row is
    // visible again for the user to fix.
    final resolved = <Product>[];
    for (final line in state.lines) {
      final product = byId[line.chosenProductId];
      if (product == null) return;
      resolved.add(product);
    }

    final cart = ref.read(cartControllerProvider.notifier);
    for (var i = 0; i < state.lines.length; i++) {
      cart.addOrIncrement(resolved[i], state.lines[i].quantity);
    }

    ref.read(voiceControllerProvider.notifier).reset();
    if (!context.mounted) return;
    Navigator.of(context).pop();
    // No AppRoutes constant for cart exists yet -- app_router.dart itself
    // registers this route by the raw literal.
    context.push('/cart');
  }

  /// Opens a small editor prefilled with [current] transcript. On submit,
  /// re-runs the AI on the corrected text via the controller. Empty submits
  /// are ignored by the controller.
  Future<void> _editTranscript(BuildContext context, WidgetRef ref, String current) async {
    final controller = TextEditingController(text: current);
    try {
      final edited = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(dialogContext.l10n.voice_heard),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            onSubmitted: (v) => Navigator.of(dialogContext).pop(v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(dialogContext.l10n.common_cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: Text(dialogContext.l10n.voice_recheck),
            ),
          ],
        ),
      );
      if (edited != null) {
        await ref.read(voiceControllerProvider.notifier).reparseFromText(edited);
      }
    } finally {
      // Deferred a frame: the AlertDialog's exit-transition route is still
      // mounted (mid pop-animation) the instant `showDialog` resolves, so
      // disposing synchronously here can race the TextField's own teardown.
      // A post-frame callback runs after that route has actually been
      // removed from the tree.
      WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final state = ref.watch(voiceControllerProvider);
    final products =
        ref.watch(productsStreamProvider).value ?? const <Product>[];
    final byId = {for (final p in products) p.id: p};

    // "Effectively settled" -- a chosen product only counts if it still
    // exists in the products stream. Used consistently for both row
    // rendering and the button gate, so a product that vanishes mid-review
    // (e.g. deleted from another device) can never silently drop a line
    // from the cart: the line re-opens for review AND the button disables.
    bool settled(VoiceLine line) =>
        line.isSettled && byId.containsKey(line.chosenProductId);
    final canAdd = state.lines.isNotEmpty && state.lines.every(settled);

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
          InkWell(
            onTap: () => _editTranscript(context, ref, state.heardText ?? ''),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    '${l10n.voice_heard} "${state.heardText ?? ''}"',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.edit, size: 14, color: theme.colorScheme.onSurfaceVariant),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: state.lines.length,
              separatorBuilder: (_, _) => const Divider(height: 24),
              itemBuilder: (context, i) => _buildLine(
                i,
                state.lines[i],
                byId,
                settled: settled(state.lines[i]),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: canAdd ? () => _addToCart(context, ref) : null,
              child: Text(l10n.voice_addToCart),
            ),
          ),
        ],
      ),
    );
  }

  /// Renders by effective settledness, not by the line's original `status`:
  /// a chip pick that resolves a formerly-ambiguous line must render exactly
  /// like a pre-filled resolved one (stepper + all), and a resolved line
  /// whose product vanished must fall back exactly like a not-found one.
  Widget _buildLine(
    int index,
    VoiceLine line,
    Map<String, Product> byId, {
    required bool settled,
  }) {
    // Only offer choices that still resolve to a real product -- a vanished
    // candidate can't be usefully re-selected or labelled.
    final validChoices = line.choices
        .where((c) => byId.containsKey(c.productId))
        .toList();

    if (settled) {
      return _SettledRow(
        index: index,
        line: line,
        product: byId[line.chosenProductId]!,
        choices: validChoices,
        byId: byId,
      );
    }
    if (validChoices.isNotEmpty) {
      return _ChooseRow(
        index: index,
        line: line,
        choices: validChoices,
        byId: byId,
      );
    }
    return _NotFoundRow(index: index, line: line);
  }
}

/// A chip label that can't blow up the `Wrap` -- long (e.g. Bengali) product
/// names get clipped instead of forcing the row to overflow horizontally.
class _ChipLabel extends StatelessWidget {
  const _ChipLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 160),
    child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
  );
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

/// An effectively-settled line: product name, quantity stepper, and the
/// assumed-quantity caption when the count was never actually spoken.
/// Settling can come from a pre-filled resolved match OR the user picking a
/// chip on a formerly-ambiguous line -- both render identically here. When
/// more than one valid candidate exists, the choice chips stay visible below
/// the stepper (with the chosen one selected) so the user can still switch.
class _SettledRow extends ConsumerWidget {
  const _SettledRow({
    required this.index,
    required this.line,
    required this.product,
    required this.choices,
    required this.byId,
  });

  final int index;
  final VoiceLine line;
  final Product product;
  final List<VoiceMatch> choices;
  final Map<String, Product> byId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final step = stepForUnit(product.unit);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
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
                    product.name,
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
        ),
        if (choices.length > 1)
          Padding(
            padding: const EdgeInsets.only(left: 56, top: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final choice in choices)
                  ChoiceChip(
                    label: _ChipLabel(
                      byId[choice.productId]?.name ?? choice.productId,
                    ),
                    selected: line.chosenProductId == choice.productId,
                    onSelected: (_) => ref
                        .read(voiceControllerProvider.notifier)
                        .choose(index, choice.productId),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A line not yet effectively settled but with at least one candidate still
/// resolvable to a real product: the raw heard text plus a chip per
/// candidate. Tapping a chip calls straight through to `choose`.
class _ChooseRow extends ConsumerWidget {
  const _ChooseRow({
    required this.index,
    required this.line,
    required this.choices,
    required this.byId,
  });

  final int index;
  final VoiceLine line;
  final List<VoiceMatch> choices;
  final Map<String, Product> byId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

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
                  for (final choice in choices)
                    ChoiceChip(
                      label: _ChipLabel(
                        byId[choice.productId]?.name ?? choice.productId,
                      ),
                      selected: line.chosenProductId == choice.productId,
                      onSelected: (_) => ref
                          .read(voiceControllerProvider.notifier)
                          .choose(index, choice.productId),
                    ),
                ],
              ),
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
