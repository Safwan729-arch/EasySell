import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/refresh_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../data/transaction_repository.dart';
import '../domain/transaction.dart';

/// Lower bound for every in-app date picker: the shop's first-ever sale date
/// (local calendar day), or null when the shop has no sales yet — in which case
/// pickers fall back to their legacy floor. Refreshes with [dataRefreshProvider]
/// so the first sale of a brand-new shop opens the calendar immediately.
final earliestSaleDateProvider = FutureProvider.autoDispose<DateTime?>((
  ref,
) async {
  ref.watch(dataRefreshProvider);
  final shopId = ref.watch(myShopProvider).value?.id;
  if (shopId == null) return null;
  final result = await ref
      .read(transactionRepositoryProvider)
      .earliestSaleDate(shopId: shopId);
  return result.when(success: (d) => d, failure: (_) => null);
});

/// How far back [recentUnitsSoldProvider] looks. Long enough to include slow
/// movers a shop still stocks, short enough that a product they stopped selling
/// months ago stops influencing matching.
const recentSalesWindow = Duration(days: 30);

/// Units sold per product id over [recentSalesWindow], newest sales first.
///
/// Feeds the voice/scan candidate payload so a model can break a tie the speech
/// itself never settled: told only that a shop stocks both Pepsi 500ml and
/// Pepsi 1L, "two Pepsi" is a coin flip, but told the 1L sells twenty times a
/// day and the 500ml twice a month, the guess is obvious.
///
/// Deliberately NOT autoDispose and NOT awaited on the hot path: the voice
/// controller kicks this off when recording starts and reads whatever has
/// arrived by the time it uploads, so an unresolved (or failed) fetch costs
/// nothing but a slightly less-informed match. Watches [dataRefreshProvider] so
/// recording a sale refreshes the counts.
final recentUnitsSoldProvider = FutureProvider<Map<String, double>>((
  ref,
) async {
  ref.watch(dataRefreshProvider);
  final shopId = ref.watch(myShopProvider).value?.id;
  if (shopId == null) return const <String, double>{};
  final result = await ref
      .read(transactionRepositoryProvider)
      .recentSales(
        shopId: shopId,
        limit: 300,
        since: DateTime.now().subtract(recentSalesWindow),
      );
  return result.when(
    success: (sales) {
      final units = <String, double>{};
      for (final s in sales) {
        units[s.productId] = (units[s.productId] ?? 0) + s.quantity;
      }
      return units;
    },
    // A failed lookup must never block a sale -- matching just loses a hint.
    failure: (_) => const <String, double>{},
  );
});

/// All SALE transactions on a specific local calendar [day], newest first and
/// uncapped, so drilling into a past day in History is always complete.
final salesForDayProvider = FutureProvider.autoDispose
    .family<List<Transaction>, DateTime>((ref, day) async {
      ref.watch(dataRefreshProvider);
      final shopId = ref.watch(myShopProvider).value?.id;
      if (shopId == null) return const <Transaction>[];
      final result = await ref
          .read(transactionRepositoryProvider)
          .salesForDay(shopId: shopId, day: day);
      return result.when(success: (l) => l, failure: (f) => throw f);
    });
