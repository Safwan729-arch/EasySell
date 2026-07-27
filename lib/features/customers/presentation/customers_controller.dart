import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../../shared/providers/refresh_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../data/customer_repository.dart';
import '../domain/customer_balance.dart';
import 'receivables_controller.dart';

/// Loads the shop's customers with live balances (highest balance first) and
/// owns customer create/update/delete. Mutations refresh the receivables card
/// and any open detail view.
class CustomersController extends AsyncNotifier<List<CustomerBalance>> {
  @override
  Future<List<CustomerBalance>> build() async {
    ref.watch(dataRefreshProvider);
    final shopId = ref.watch(myShopProvider).value?.id;
    if (shopId == null) return const [];
    final result = await ref
        .read(customerRepositoryProvider)
        .customerBalances(shopId);
    return result.when(success: (v) => v, failure: (f) => throw f);
  }

  /// Re-fetches the customer list (e.g. for pull-to-refresh). Completes once
  /// the rebuilt value is available.
  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  Future<Failure?> createCustomer({
    required String name,
    required String phone,
    String? note,
  }) {
    return _run(
      (repo, shopId) => repo.createCustomer(
        shopId: shopId,
        name: name,
        phone: phone,
        note: note,
      ),
    );
  }

  Future<Failure?> updateCustomer({
    required String id,
    required String name,
    required String phone,
    String? note,
  }) {
    return _run(
      (repo, _) =>
          repo.updateCustomer(id: id, name: name, phone: phone, note: note),
    );
  }

  Future<Failure?> deleteCustomer(String id) {
    return _run((repo, shopId) => repo.deleteCustomer(shopId: shopId, id: id));
  }

  /// Runs a repository mutation, refreshing dependent views on success and
  /// reporting the failure to the caller on error (never clobbering the
  /// loaded list with `AsyncError` — a failed create/update/delete shouldn't
  /// blank out an otherwise-healthy customer list). Generic over the
  /// Result's payload so create/update/delete share one path.
  Future<Failure?> _run<T>(
    Future<Result<T>> Function(CustomerRepository repo, String shopId) action,
  ) async {
    final shopId = ref.read(myShopProvider).value?.id;
    if (shopId == null) {
      return const AuthFailure('No shop found for this account.');
    }
    final result = await action(ref.read(customerRepositoryProvider), shopId);
    return result.when(
      success: (_) {
        _refreshAll();
        return null;
      },
      failure: (f) => f,
    );
  }

  void _refreshAll() {
    ref.invalidateSelf();
    ref.invalidate(receivablesControllerProvider);
    ref.read(dataRefreshProvider.notifier).bump();
  }
}

final customersControllerProvider =
    AsyncNotifierProvider<CustomersController, List<CustomerBalance>>(
      CustomersController.new,
    );
