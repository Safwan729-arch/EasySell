import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/haptics.dart';
import '../../analytics/presentation/analytics_controller.dart';
import '../../inventory/domain/product.dart';
import '../../inventory/presentation/inventory_controller.dart';
import 'scan_session_controller.dart';

/// How many shortcuts fit before the row becomes a scroll nobody reads.
const _maxTopSellers = 12;

/// One-tap shortcuts for the products this shop actually sells all day.
///
/// Costs nothing new: `bestSellersProvider` already exists for the Reports tab,
/// derived from `TransactionRepository.recentSales()`. No migration, nothing to
/// deploy. Every tap here is a Gemini call that never happens, which is why
/// this is the cost feature as much as the speed one.
///
/// Hidden entirely when the shop has no sales history -- alphabetical filler
/// would just teach the shopkeeper to ignore the row.
class TopSellersStrip extends ConsumerWidget {
  const TopSellersStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products =
        ref.watch(productsStreamProvider).value ?? const <Product>[];
    final byId = {for (final p in products) p.id: p};
    final sellers =
        ref.watch(bestSellersProvider).value ?? const <BestSeller>[];

    final shortcuts = <Product>[
      for (final s in sellers)
        if (byId[s.productId] case final Product p)
          if (p.quantity > 0) p,
    ].take(_maxTopSellers).toList();

    if (shortcuts.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return SizedBox(
      height: 60,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        itemCount: shortcuts.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final p = shortcuts[i];
          return ActionChip(
            avatar: Icon(
              Icons.bolt,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            label: Text(p.name),
            onPressed: () {
              AppHaptics.tap();
              ref.read(scanSessionProvider.notifier).addShortcut(p);
            },
          );
        },
      ),
    );
  }
}
