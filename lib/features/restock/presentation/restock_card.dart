import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/theme.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/extensions/format.dart';
import 'restock_providers.dart';
import 'restock_text.dart';

/// Home's "Restock soon" card (restock spec §4.1). Hidden unless something
/// needs buying -- and on error or while loading, so a shop that has not run
/// 0017 sees no change.
class RestockSoonCard extends ConsumerWidget {
  const RestockSoonCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final buyNow = ref.watch(restockPlanProvider).value?.buyNow ?? const [];
    if (buyNow.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: InkWell(
          onTap: () => context.push(AppRoutes.restock),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.shopping_basket_outlined,
                      size: 18,
                      color: colors.warning,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      l10n.restockPlan_cardTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => context.push(AppRoutes.restock),
                      child: Text(l10n.dashboard_viewAll),
                    ),
                  ],
                ),
                Text(
                  l10n.restockPlan_cardSummary(Qty.format(buyNow.length)),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                for (final i in buyNow.take(2))
                  Text(
                    l10n.restockPlan_cardItem(
                      i.product.name,
                      daysLeftShort(l10n, i),
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: i.daysLeft <= 2
                          ? colors.negative
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
