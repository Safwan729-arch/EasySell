import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/theme.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/section_bits.dart';
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
    void open() => context.push(AppRoutes.restock);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      // The mockups' peach "Low stock" card; Restock soon replaced it.
      child: AlertCard(
        tinted: true,
        icon: Icons.warning_amber_rounded,
        iconColor: colors.warning,
        title: l10n.restockPlan_cardTitle,
        onViewAll: open,
        onTap: open,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.restockPlan_cardSummary(buyNow.length),
              style: theme.textTheme.bodyLarge?.copyWith(fontSize: 15),
            ),
            const SizedBox(height: 4),
            for (final i in buyNow.take(2))
              Text(
                l10n.restockPlan_cardItem(
                  i.product.name,
                  daysLeftShort(l10n, i),
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: i.isUrgent
                      ? colors.negative
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
