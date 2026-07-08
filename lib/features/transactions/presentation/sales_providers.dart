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
