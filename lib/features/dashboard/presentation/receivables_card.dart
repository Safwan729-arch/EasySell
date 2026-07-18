import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/extensions/format.dart';
import '../../auth/data/auth_repository.dart';
import '../../customers/presentation/receivables_controller.dart';

/// Dashboard card summarizing outstanding customer credit. Hidden entirely when
/// nobody owes anything, so cash-only shops see no extra clutter.
class ReceivablesCard extends ConsumerWidget {
  const ReceivablesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(receivablesControllerProvider).value;
    if (summary == null || summary.debtorCount == 0) {
      return const SizedBox.shrink();
    }
    final l10n = context.l10n;
    final currency = ref.watch(myShopProvider).value?.currency ?? 'USD';
    final theme = Theme.of(context);

    // The bottom margin lives here (inside the visible branch) rather than as
    // a SizedBox around this widget in dashboard_screen.dart, so the gap
    // truly collapses to zero when this card hides via the early return above
    // instead of doubling up with a neighbouring SizedBox.
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push(AppRoutes.customers),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.dashboard_receivablesTitle,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        l10n.customers_receivablesHeader(
                          Money.format(summary.totalOwed, currencyCode: currency),
                          summary.debtorCount,
                        ),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
