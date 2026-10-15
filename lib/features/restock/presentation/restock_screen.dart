import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/theme.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../shared/extensions/format.dart';
import '../../transactions/presentation/transaction_confirmation_sheet.dart';
import '../domain/restock_plan.dart';
import 'restock_providers.dart';
import 'restock_text.dart';

/// What to restock and how much (restock spec §4.2).
class RestockScreen extends ConsumerWidget {
  const RestockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final plan = ref.watch(restockPlanProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.restockPlan_title)),
      body: switch (plan) {
        AsyncData(:final value) when value.isEmpty => _Message(
          icon: Icons.inventory_2_outlined,
          text: l10n.restockPlan_empty,
        ),
        AsyncData(:final value) => ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            if (value.buyNow.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  l10n.restockPlan_buyNow,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              for (final i in value.buyNow) _RestockRow(item: i, buy: true),
            ],
            if (value.enough.isNotEmpty)
              Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    l10n.restockPlan_enough(Qty.format(value.enough.length)),
                    style: theme.textTheme.titleSmall,
                  ),
                  children: [
                    for (final i in value.enough)
                      _RestockRow(item: i, buy: false),
                  ],
                ),
              ),
          ],
        ),
        AsyncError() => _Message(
          icon: Icons.cloud_off_outlined,
          text: l10n.restockPlan_loadError,
          onRetry: () => ref.invalidate(restockSpeedsProvider),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _RestockRow extends StatelessWidget {
  const _RestockRow({required this.item, required this.buy});

  final RestockItem item;
  final bool buy;

  Future<void> _open(BuildContext context) async {
    if (!buy) {
      context.push('/inventory/${item.product.id}');
      return;
    }
    final recorded = await showRestockSheet(
      context,
      product: item.product,
      initialQuantity: item.suggestion,
    );
    if (recorded == true && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(context.l10n.common_stockAdded)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final p = item.product;
    final urgent = item.daysLeft <= 2;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => _open(context),
      title: Row(
        children: [
          Flexible(child: Text(p.name, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 6),
          switch (item.trend) {
            RestockTrend.up => Icon(
              Icons.trending_up,
              size: 18,
              color: colors.positive,
            ),
            RestockTrend.down => Icon(
              Icons.trending_down,
              size: 18,
              color: colors.negative,
            ),
            RestockTrend.flat => const SizedBox.shrink(),
          },
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            runsOutText(l10n, item),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: buy
                  ? (urgent ? colors.negative : colors.warning)
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: buy ? FontWeight.w600 : null,
            ),
          ),
          if (buy)
            Text(
              l10n.restockPlan_buyAbout(
                Qty.format(item.suggestion),
                p.unitLabel,
              ),
              style: theme.textTheme.bodyMedium,
            ),
          Text(
            l10n.restockPlan_inStock(Qty.format(item.goodStock), p.unitLabel),
            style: muted,
          ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.onRetry});

  final IconData icon;
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onRetry,
                child: Text(context.l10n.common_retry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
