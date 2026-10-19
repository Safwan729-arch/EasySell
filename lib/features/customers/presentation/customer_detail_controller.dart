import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
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

  /// Null on success, else why it failed. The failure goes back to the
  /// payment sheet, which is still open: setting it as this controller's
  /// state replaced the whole ledger with an error, and its snackbar showed
  /// behind the sheet where nobody saw it.
  ///
  /// [paymentId] must be re-sent unchanged when the same payment is retried
  /// (see [CustomerRepository.recordPayment]).
  Future<Failure?> recordPayment({
    required double amount,
    required String paymentId,
    String? note,
  }) async {
    final shopId = ref.read(myShopProvider).value?.id;
    if (shopId == null) {
      return const AuthFailure('No shop found for this account.');
    }
    final result = await ref
        .read(customerRepositoryProvider)
        .recordPayment(
          shopId: shopId,
          customerId: customerId,
          amount: amount,
          paymentId: paymentId,
          note: note,
        );
    return result.when(
      success: (_) {
        ref.invalidateSelf();
        ref.invalidate(customersControllerProvider);
        ref.invalidate(receivablesControllerProvider);
        ref.read(dataRefreshProvider.notifier).bump();
        return null;
      },
      failure: (f) => f,
    );
  }
}

final customerDetailControllerProvider =
    AsyncNotifierProvider.family<
      CustomerDetailController,
      List<LedgerEntry>,
      String
    >(CustomerDetailController.new);
