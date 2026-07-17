import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/refresh_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../data/customer_repository.dart';
import '../domain/ledger_entry.dart';
import 'customers_controller.dart';
import 'receivables_controller.dart';

/// One customer's ledger (newest first) + the record-payment action.
///
/// riverpod 3's `AsyncNotifierProvider.family` has no `FamilyAsyncNotifier`
/// base (that's a riverpod 2.x type) — the family factory is
/// `NotifierT Function(ArgT arg)`, so the arg is captured via a constructor
/// instead of a `build(arg)` parameter or an inherited `arg` getter.
class CustomerDetailController extends AsyncNotifier<List<LedgerEntry>> {
  CustomerDetailController(this.customerId);

  final String customerId;

  @override
  Future<List<LedgerEntry>> build() async {
    ref.watch(dataRefreshProvider);
    final result = await ref
        .read(customerRepositoryProvider)
        .ledgerFor(customerId);
    return result.when(success: (v) => v, failure: (f) => throw f);
  }

  Future<bool> recordPayment({required double amount, String? note}) async {
    final shopId = ref.read(myShopProvider).value?.id;
    if (shopId == null) return false;
    final result = await ref
        .read(customerRepositoryProvider)
        .recordPayment(
          shopId: shopId,
          customerId: customerId,
          amount: amount,
          note: note,
        );
    return result.when(
      success: (_) {
        ref.invalidateSelf();
        ref.invalidate(customersControllerProvider);
        ref.invalidate(receivablesControllerProvider);
        ref.read(dataRefreshProvider.notifier).bump();
        return true;
      },
      failure: (f) {
        state = AsyncError(f, StackTrace.current);
        return false;
      },
    );
  }
}

final customerDetailControllerProvider = AsyncNotifierProvider.family<
  CustomerDetailController,
  List<LedgerEntry>,
  String
>(CustomerDetailController.new);
