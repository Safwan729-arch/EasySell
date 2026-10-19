import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/refresh_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../../expiry/presentation/today_provider.dart';
import '../data/finance_repository.dart';
import '../domain/finance_health.dart';

/// The money-health sums. Refetches after a sale, restock or khata payment
/// ([dataRefreshProvider]) and when the local date changes.
///
/// No automatic retry, for the same reason as `restockSpeedsProvider`: the
/// default retries for ~40 s and shows a spinner instead of the error.
final financeHealthProvider = FutureProvider.autoDispose<FinanceHealth>(
  retry: (_, _) => null,
  (ref) async {
    ref.watch(dataRefreshProvider);
    final today = ref.watch(todayProvider);
    final shopId = await ref.watch(myShopProvider.selectAsync((s) => s?.id));
    if (shopId == null) return FinanceHealth.empty;
    final offset = ref.read(nowProvider)().timeZoneOffset.inMinutes;
    final r = await ref
        .read(financeRepositoryProvider)
        .fetchHealth(shopId, today: today, utcOffsetMinutes: offset);
    return r.when(success: (h) => h, failure: (f) => throw f);
  },
);
