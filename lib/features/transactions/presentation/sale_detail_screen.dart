import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/config/theme.dart';
import '../../../core/l10n/enum_labels.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../shared/extensions/format.dart';
import '../../auth/data/auth_repository.dart';
import '../../expiry/presentation/expiry_date_field.dart';
import '../../inventory/domain/product.dart';
import '../../inventory/presentation/inventory_controller.dart';
import '../domain/transaction.dart';

/// Full-screen "story" of a single past sale. Receives the tapped [Transaction]
/// via go_router `extra`; all money/profit figures are the FROZEN snapshot on
/// the row (never recomputed from current prices — CLAUDE.md §4). The product
/// name/unit is resolved live from [productsStreamProvider], falling back
/// gracefully when the product was later deleted.
class SaleDetailScreen extends ConsumerWidget {
  const SaleDetailScreen({super.key, required this.sale});

  final Transaction? sale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    if (sale == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.saleDetail_title)),
        body: Center(child: Text(l10n.saleDetail_notFound)),
      );
    }
    final t = sale!;

    final currency = ref.watch(myShopProvider).value?.currency ?? 'USD';
    final products =
        ref.watch(productsStreamProvider).value ?? const <Product>[];
    Product? product;
    for (final p in products) {
      if (p.id == t.productId) {
        product = p;
        break;
      }
    }
    final name = (product?.name.isNotEmpty ?? false)
        ? product!.name
        : l10n.history_saleFallback;
    final qtyLabel = product != null
        ? '${Qty.format(t.quantity)} ${product.unit.label}'
        : Qty.format(t.quantity);

    final dt = (t.createdAt ?? DateTime.now()).toLocal();
    // AM/PM stays Latin (universally read on Bangladeshi tills); DateFormat
    // localizes the digits via Intl.defaultLocale — matches history_screen.
    final soldOn =
        '${DateFormat('EEE, d MMM y').format(dt)} · '
        '${DateFormat('h:mm').format(dt)}${dt.hour < 12 ? 'AM' : 'PM'}';

    final colors = theme.extension<AppColors>()!;
    final profitColor = t.profit >= 0 ? colors.positive : colors.negative;

    String money(double v) => Money.format(v, currencyCode: currency);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.saleDetail_title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Row(
            children: [
              _Avatar(letter: name.isNotEmpty ? name[0].toUpperCase() : '?'),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            l10n.saleDetail_soldOn,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(soldOn, style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          const Divider(),
          _DetailRow(label: l10n.saleDetail_quantity, value: qtyLabel),
          // The delivery the units came from. Hidden for undated stock and
          // older sales, which never recorded a delivery.
          if (t.batchExpiry case final expiry?)
            _DetailRow(
              label: l10n.expiry_dateLabel,
              value: formatExpiryDate(context, expiry),
            ),
          _DetailRow(
            label: l10n.saleDetail_priceEach,
            value: money(t.sellingPrice),
          ),
          if (t.discountAmount > 0) ...[
            _DetailRow(
              label: l10n.common_subtotal,
              value: money(t.sellingPrice * t.quantity),
            ),
            _DetailRow(
              label: l10n.saleDetail_discount,
              value: '−${money(t.discountAmount)}',
            ),
          ],
          _DetailRow(
            label: l10n.saleDetail_total,
            value: money(t.revenue),
            emphasize: true,
          ),
          _DetailRow(label: l10n.saleDetail_cost, value: money(t.cost)),
          _DetailRow(
            label: l10n.saleDetail_profit,
            value: money(t.profit),
            valueColor: profitColor,
            emphasize: true,
          ),
          _DetailRow(
            label: l10n.saleDetail_enteredBy,
            value: saleSourceLabel(l10n, t.source),
          ),
          const Divider(),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.saleDetail_frozenNote,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.letter});
  final String letter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        letter,
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style:
                (emphasize
                        ? theme.textTheme.titleMedium
                        : theme.textTheme.bodyLarge)
                    ?.copyWith(
                      fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
                      color: valueColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
          ),
        ],
      ),
    );
  }
}
