import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/refresh_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../data/customer_repository.dart';
import '../domain/receivables_summary.dart';

/// Total receivables + debtor count for the dashboard card. Recomputes whenever
/// a sale/payment bumps [dataRefreshProvider].
class ReceivablesController extends AsyncNotifier<ReceivablesSummary> {
  @override
  Future<ReceivablesSummary> build() async {
    ref.watch(dataRefreshProvider);
    final shopId = ref.watch(myShopProvider).value?.id;
    if (shopId == null) return ReceivablesSummary.empty;
    final result = await ref
        .read(customerRepositoryProvider)
        .receivablesSummary(shopId);
    return result.when(success: (v) => v, failure: (f) => throw f);
  }
}

final receivablesControllerProvider =
    AsyncNotifierProvider<ReceivablesController, ReceivablesSummary>(
      ReceivablesController.new,
    );
