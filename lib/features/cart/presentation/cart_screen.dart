import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/haptics.dart';
import '../../../core/config/theme.dart';
import '../../../core/error/failure.dart';
import '../../../core/l10n/failure_text.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../core/widgets/brand_fill.dart';
import '../../../core/widgets/rounded_icon_tile.dart';
import '../../../core/widgets/two_option_segment.dart';
import '../../../shared/extensions/format.dart';
import '../../auth/data/auth_repository.dart';
import '../../customers/presentation/customer_picker_sheet.dart';
import '../../expiry/domain/batch_pick.dart';
import '../../expiry/domain/cart_expiry.dart';
import '../../expiry/domain/expiry_estimate.dart';
import '../../expiry/presentation/batch_action_feedback.dart';
import '../../expiry/presentation/batch_actions_controller.dart';
import '../../expiry/presentation/expiry_date_field.dart';
import '../../expiry/presentation/expiry_providers.dart';
import '../../inventory/domain/product.dart';
import '../domain/cart_line.dart';
import '../domain/cart_math.dart';
import 'cart_checkout_controller.dart';
import 'cart_controller.dart';
import 'cart_discount_controller.dart';
import 'discount_sheet.dart';
import 'payment_method_controller.dart';

/// Full-screen cart review + checkout. This IS the review-before-commit step
/// for a multi-item sale -- there is no second confirmation modal, the same
/// principle as the single-item sheet just scaled to N lines.
class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  Future<void> _checkout(BuildContext context, WidgetRef ref) async {
    final lines = ref.read(cartControllerProvider);
    final itemCount = lines.length;
    // NET, and read BEFORE checkout() runs -- a successful checkout clears the
    // discount, so reading it afterwards silently reports the gross bill. This
    // number is not decoration: on credit the snackbar names the debt that was
    // just written to customer_ledger, so a gross figure here misstates what
    // the customer owes at the exact moment the debt is created.
    final total = cartTotal(lines) - ref.read(cartDiscountControllerProvider);
    final currency = ref.read(myShopProvider).value?.currency ?? 'USD';
    final selection = ref.read(paymentMethodControllerProvider);

    final ok = await ref
        .read(cartCheckoutControllerProvider.notifier)
        .checkout(customerId: selection.customer?.id);
    if (!context.mounted || !ok) return;

    AppHaptics.success();
    final l10n = context.l10n;
    ref.read(paymentMethodControllerProvider.notifier).reset();
    context.pop();
    final formattedTotal = Money.format(total, currencyCode: currency);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            selection.customer != null
                ? l10n.cart_addedToKhata(
                    selection.customer!.name,
                    formattedTotal,
                  )
                : l10n.cart_itemsSold(itemCount, formattedTotal),
          ),
        ),
      );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final cleared = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(ctx.l10n.cart_clearTitle),
          content: Text(ctx.l10n.cart_clearBody),
          // Natural-width actions: the theme forces FilledButton to a
          // full-width minimumSize, which makes a dialog's confirm button
          // dwarf the text "Keep". Reset it so both size to their content.
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(ctx.l10n.cart_keep),
            ),
            FilledButton(
              style: destructiveButtonStyle(ctx),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(ctx.l10n.common_clear),
            ),
          ],
        );
      },
    );
    if (cleared == true) {
      AppHaptics.warning();
      ref.read(cartControllerProvider.notifier).clear();
      ref.read(paymentMethodControllerProvider.notifier).reset();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final lines = ref.watch(cartControllerProvider);
    final currency = ref.watch(myShopProvider).value?.currency ?? 'USD';
    final checkoutState = ref.watch(cartCheckoutControllerProvider);
    // A line that would sell expired units, or more than is left, blocks
    // checkout until it is fixed (expiry spec §5 Cart).
    // Except a retry of a sale that was sent and never answered: it may
    // already be saved, the server replays it, and editing the cart instead
    // would record it twice.
    final blocked =
        ref.watch(cartLineNoticesProvider).isNotEmpty &&
        !ref
            .read(cartCheckoutControllerProvider.notifier)
            .hasUnacknowledgedSale(lines);

    ref.listen<AsyncValue<void>>(cartCheckoutControllerProvider, (_, next) {
      if (next is AsyncError) {
        AppHaptics.warning();
        // Translated from the failure's CODE, not its message: the RPC raises
        // English sentences ("Insufficient stock for Pepsi: have 3, need 5")
        // and this app is Bengali-first, so forwarding them verbatim showed
        // the wrong language at the moment a sale failed. See failure_text.dart.
        final message = switch (next.error) {
          Failure f => failureText(context.l10n, f),
          _ => context.l10n.cart_checkoutFailed,
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
        title: Text(context.l10n.cart_title),
        actions: [
          if (lines.isNotEmpty)
            TextButton(
              onPressed: checkoutState.isLoading
                  ? null
                  : () => _confirmClear(context, ref),
              child: Text(context.l10n.common_clear),
            ),
        ],
      ),
      body: lines.isEmpty
          ? const _EmptyCart()
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              itemCount: lines.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 14),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      context.l10n.cart_itemsInCart(lines.length),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontSize: 16,
                        color: theme.colorScheme.onSurfaceVariant,
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
              subtotal: cartTotal(lines),
              itemCount: lines.length,
              currency: currency,
              isLoading: checkoutState.isLoading,
              blocked: blocked,
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
    // the product's own GOOD stock -- expired units are never offered -- or,
    // once a batch is chosen, what that batch has left.
    final expiry = ref.watch(productExpiryProvider)[product.id];
    final options = sellOptions(expiry);
    // Shown whenever there is a dated batch to name: a choice to make (several
    // places to sell from), one made, or the only batch there is.
    final showBatch =
        needsBatchChoice(options) ||
        line.batchId != null ||
        onlyOption(options)?.batchId != null;
    final double maxQty =
        chosenLeft(line, expiry) ?? ref.watch(goodStockProvider(product));
    final notice = ref.watch(cartLineNoticesProvider)[product.id];
    final canDecrement = !isCheckingOut && line.quantity > _step;
    final canIncrement =
        !isCheckingOut && line.quantity + _step <= maxQty + 1e-9;

    // Still a [Card]: cart tests count Cards to count lines.
    final card = Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The same solid letter tile as Items (design decision 2).
                RoundedTextTile(
                  text: product.name.isNotEmpty
                      ? product.name.characters.first.toUpperCase()
                      : '?',
                  color: tileColorFor(
                    product.name,
                    dark: theme.brightness == Brightness.dark,
                  ),
                  size: 52,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      const SizedBox(height: 2),
                      Text(
                        context.l10n.cart_pricePerUnit(
                          Money.format(
                            product.sellingPrice,
                            currencyCode: currency,
                          ),
                          product.unitLabel,
                        ),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  Money.format(line.subtotal, currencyCode: currency),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
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
                const SizedBox(width: 8),
                // Takes what the stepper leaves and shrinks to fit it: the
                // 52 dp stepper plus "Remove" can outgrow a 360 dp card.
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: TextButton.icon(
                        onPressed: isCheckingOut ? null : () => _remove(ref),
                        style: TextButton.styleFrom(
                          foregroundColor: colors.negative,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          minimumSize: const Size(0, 44),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: theme.textTheme.titleSmall?.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        icon: const Icon(Icons.delete_outline, size: 22),
                        label: Text(context.l10n.common_remove),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (showBatch) ...[
              const SizedBox(height: 4),
              _BatchRow(line: line, options: options, enabled: !isCheckingOut),
            ],
            if (notice != null) ...[
              const SizedBox(height: 10),
              _LineNotice(
                notice: notice,
                product: product,
                isCheckingOut: isCheckingOut,
              ),
            ],
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
          borderRadius: BorderRadius.circular(22),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      child: card,
    );
  }
}

/// Why this line cannot be checked out, with the way out (expiry spec §5).
class _LineNotice extends ConsumerWidget {
  const _LineNotice({
    required this.notice,
    required this.product,
    required this.isCheckingOut,
  });

  final CartLineNotice notice;
  final Product product;
  final bool isCheckingOut;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.error,
      fontWeight: FontWeight.w600,
    );
    switch (notice) {
      case BatchUnchosenNotice():
        return Text(l10n.cart_batchChooseNotice, style: style);
      case BatchShortNotice(:final left):
        return Text(
          left > 0
              ? l10n.cart_batchShort(Qty.format(left), product.unitLabel)
              : l10n.cart_batchGone,
          style: style,
        );
      case OverStockNotice(:final stock):
        return Text(
          l10n.expiry_cartOnlyLeft(Qty.format(stock), product.unitLabel),
          style: style,
        );
      case ExpiredStockNotice(
        :final good,
        :final expired,
        :final expiredBatchIds,
      ):
        final busy =
            isCheckingOut ||
            ref.watch(batchActionsControllerProvider).isLoading;
        final actions = ref.read(batchActionsControllerProvider.notifier);
        // A failed tap must say why, not silently do nothing.
        Future<void> act(Future<bool> Function() action) async {
          final messenger = ScaffoldMessenger.of(context);
          if (!await action()) showBatchActionFailure(messenger, l10n, ref);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              good > 0
                  ? l10n.expiry_cartOnlyGood(
                      Qty.format(good),
                      product.name,
                      Qty.format(expired),
                    )
                  : l10n.expiry_cartOnlyExpired(
                      product.name,
                      Qty.format(expired),
                    ),
              style: style,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 36),
                  ),
                  onPressed: busy
                      ? null
                      : () => act(() => actions.removeExpired(expiredBatchIds)),
                  child: Text(l10n.expiry_cartRemoveExpired),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () =>
                            act(() => actions.markNotExpired(expiredBatchIds)),
                  child: Text(l10n.expiry_cartNotExpired),
                ),
              ],
            ),
          ],
        );
    }
  }
}

/// Which batch (delivery) the line sells from. With several batches the
/// seller must choose (checkout waits); with one, it is shown and needs no
/// tap; a product without dates shows nothing.
class _BatchRow extends ConsumerWidget {
  const _BatchRow({
    required this.line,
    required this.options,
    required this.enabled,
  });

  final CartLine line;
  final List<SellOption> options;
  final bool enabled;

  String _choiceText(BuildContext context, String? choice) {
    final l10n = context.l10n;
    if (choice == null) return l10n.cart_batchChoose;
    if (choice == mixBatches) return l10n.cart_batchMix;
    if (choice == noDateBatch) return l10n.cart_batchNoDate;
    for (final o in options) {
      if (o.batchId == choice) {
        return l10n.cart_batchExpires(formatExpiryDate(context, o.expiryDate!));
      }
    }
    return '—';
  }

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => _BatchSheet(line: line, options: options),
    );
    if (choice == null) return;
    AppHaptics.tap();
    ref.read(cartControllerProvider.notifier).setBatch(line.product.id, choice);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // One place to sell from: say which, nothing to choose.
    if (!needsBatchChoice(options) && line.batchId == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Text(
          context.l10n.cart_batchLabel(
            _choiceText(context, onlyOption(options)!.batchId),
          ),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    final unchosen = line.batchId == null;
    return TextButton(
      onPressed: enabled ? () => _pick(context, ref) : null,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: unchosen ? theme.colorScheme.error : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              context.l10n.cart_batchLabel(_choiceText(context, line.batchId)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.arrow_drop_down, size: 20),
        ],
      ),
    );
  }
}

class _BatchSheet extends StatelessWidget {
  const _BatchSheet({required this.line, required this.options});

  final CartLine line;
  final List<SellOption> options;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final unit = line.product.unitLabel;

    Widget tile({
      required String value,
      required String title,
      String? subtitle,
      Widget? trailing,
    }) {
      final selected = line.batchId == value;
      return ListTile(
        key: ValueKey('batch-option-$value'),
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          color: selected ? theme.colorScheme.primary : null,
        ),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: trailing,
        onTap: () => Navigator.of(context).pop(value),
      );
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              l10n.cart_batchPickTitle,
              style: theme.textTheme.titleMedium,
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final o in options)
                  tile(
                    value: o.batchId ?? noDateBatch,
                    title: o.batchId == null
                        ? l10n.cart_batchNoDate
                        : l10n.cart_batchExpires(
                            formatExpiryDate(context, o.expiryDate!),
                          ),
                    subtitle: l10n.cart_batchOptionLeft(
                      Qty.format(o.left),
                      unit,
                    ),
                    trailing: o.status == BatchStatus.expiringSoon
                        ? Text(
                            l10n.expiry_statusSoon,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colors.warning,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        : null,
                  ),
                // Only when no one batch holds the line: the seller still
                // chooses it, but it may take from several.
                if (offersMix(options, line.quantity) ||
                    line.batchId == mixBatches)
                  tile(value: mixBatches, title: l10n.cart_batchMix),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// The pill stepper (− value +) under a cart line. Buttons disable (null
/// callback) at the stock ceiling and the one-step floor, matching the
/// add-to-cart sheet's rules.
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
    final colors = theme.extension<AppColors>()!;
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      height: 52,
      decoration: ShapeDecoration(
        color: isDark ? colors.field : colors.muted,
        shape: StadiumBorder(side: BorderSide(color: colors.glowBorder)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepButton(icon: Icons.remove, onTap: onDecrement),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 64),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _StepButton(icon: Icons.add, onTap: onIncrement, accent: true),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.onTap,
    this.accent = false,
  });

  final IconData icon;
  final VoidCallback? onTap;

  /// "+" is blue, "−" muted, as in the mockup.
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = Theme.of(context).extension<AppColors>()!;
    final enabled = onTap != null;
    return InkResponse(
      onTap: onTap,
      radius: 24,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Icon(
          icon,
          size: 24,
          color: !enabled
              ? colors.textDim.withValues(alpha: 0.6)
              : (accent ? colors.link : scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// Bounded-height checkout bar. Uses `MainAxisSize.min` so it hugs its content
/// instead of expanding to fill the loose height Scaffold grants a
/// bottomNavigationBar (the bug that previously collapsed the item list).
/// A `ConsumerWidget` (rather than plain values) so it can own the Cash/Credit
/// toggle and the chosen-customer row, which live in
/// [paymentMethodControllerProvider].
class _CheckoutBar extends ConsumerWidget {
  const _CheckoutBar({
    required this.subtotal,
    required this.itemCount,
    required this.currency,
    required this.isLoading,
    required this.blocked,
    required this.onCheckout,
  });

  /// The GROSS bill, before any discount. The bar watches the discount itself
  /// and derives the net exactly once, below. It previously took the NET and
  /// reconstructed the gross as `total + discount` -- the same figure in two
  /// shapes, which is precisely the ambiguity that let the success snackbar
  /// ship the gross total while the database recorded the net one.
  final double subtotal;
  final int itemCount;
  final String currency;
  final bool isLoading;

  /// A cart line needs fixing first (expired units, or more than is left).
  final bool blocked;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    final selection = ref.watch(paymentMethodControllerProvider);
    final discount = ref.watch(cartDiscountControllerProvider);
    final total = subtotal - discount;
    final notifier = ref.read(paymentMethodControllerProvider.notifier);
    final isCredit = selection.method == PaymentMethod.credit;
    final customer = selection.customer;

    final colors = theme.extension<AppColors>()!;
    final isDark = theme.brightness == Brightness.dark;
    // The bottom panel: a sheet-like surface with rounded top corners, lifted
    // by a soft upward shadow (light) or a glowing top edge (dark).
    return Container(
      decoration: BoxDecoration(
        color: isDark ? colors.sheet : scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: isDark
            ? Border(top: BorderSide(color: colors.glowBorder))
            : null,
        boxShadow: isDark
            ? const [BoxShadow(color: Color(0x2E3C6EFF), blurRadius: 18)]
            : const [
                BoxShadow(
                  color: Color(0x144056BE),
                  blurRadius: 30,
                  offset: Offset(0, -8),
                ),
              ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: TwoOptionSegment<PaymentMethod>(
                    values: PaymentMethod.values,
                    selected: selection.method,
                    enabled: !isLoading,
                    labelOf: (m) => m == PaymentMethod.cash
                        ? l10n.cart_paymentCash
                        : l10n.cart_paymentCredit,
                    onChanged: (m) => m == PaymentMethod.cash
                        ? notifier.setCash()
                        : notifier.setCredit(),
                  ),
                ),
              ),
              if (isCredit) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: customer == null
                      ? OutlinedButton.icon(
                          onPressed: isLoading
                              ? null
                              : () async {
                                  final chosen = await showCustomerPickerSheet(
                                    context,
                                  );
                                  if (chosen != null) {
                                    notifier.chooseCustomer(chosen);
                                  }
                                },
                          icon: const Icon(Icons.person_add_alt, size: 18),
                          label: Text(l10n.cart_selectCustomer),
                        )
                      : Text(
                          customer.name,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ],
              const SizedBox(height: 14),
              if (discount > 0) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.common_subtotal,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Text(
                      Money.format(subtotal, currencyCode: currency),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.cart_discount,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    // The amount reopens the sheet, seeded with the current
                    // value. Without this the sheet is only reachable from the
                    // "Add discount" button below, which exists only while the
                    // discount is zero -- so an applied discount could never be
                    // edited, and a customer haggling 60 down to 80 meant
                    // clearing and retyping. Deliberately a SEPARATE target
                    // from the ✕: one edits, the other destroys, and merging
                    // them would make a mis-tap cost the whole discount.
                    Tooltip(
                      message: l10n.cart_discountEdit,
                      child: InkWell(
                        onTap: isLoading
                            ? null
                            : () => showDiscountSheet(context),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Text(
                            '−${Money.format(discount, currencyCode: currency)}',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: isLoading
                          ? null
                          : () => ref
                                .read(cartDiscountControllerProvider.notifier)
                                .clear(),
                      icon: const Icon(Icons.close_rounded, size: 16),
                      visualDensity: VisualDensity.compact,
                      tooltip: l10n.cart_discountRemove,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
              ] else ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: isLoading
                        ? null
                        : () => showDiscountSheet(context),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(l10n.cart_addDiscount),
                  ),
                ),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      l10n.cart_totalItems(itemCount),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontSize: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Big, but it yields before it overflows on a 360 dp phone.
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        Money.format(total, currencyCode: currency),
                        maxLines: 1,
                        style: theme.textTheme.headlineLarge?.copyWith(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: (isLoading || blocked || !selection.isReady)
                      ? null
                      : onCheckout,
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
                  label: Text(
                    isLoading
                        ? l10n.cart_selling
                        : (isCredit && customer != null)
                        ? l10n.cart_addToKhata(customer.name)
                        : l10n.cart_checkout,
                  ),
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
            Icon(Icons.shopping_cart_outlined, size: 56, color: scheme.outline),
            const SizedBox(height: 14),
            Text(
              context.l10n.cart_empty,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.cart_emptyHint,
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
