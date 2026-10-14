import 'package:ai_shopkeeper/core/error/failure.dart';
import 'package:ai_shopkeeper/core/error/result.dart';
import 'package:ai_shopkeeper/features/auth/data/auth_repository.dart';
import 'package:ai_shopkeeper/features/auth/domain/shop.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/expiry_reconciler.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/today_provider.dart';
import 'package:ai_shopkeeper/features/transactions/data/transaction_repository.dart';
import 'package:ai_shopkeeper/features/transactions/domain/transaction.dart';
import 'package:ai_shopkeeper/features/transactions/presentation/transaction_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/expiry_fakes.dart';

class _FlakyRestockRepo implements TransactionRepository {
  bool fail = true;
  final ids = <String>[];
  final expiries = <DateTime?>[];
  final receivedOns = <DateTime?>[];

  @override
  Future<Result<Transaction>> recordRestock({
    required String shopId,
    required String productId,
    required double quantity,
    required String restockId,
    String source = 'manual',
    DateTime? expiryDate,
    DateTime? receivedOn,
  }) async {
    ids.add(restockId);
    expiries.add(expiryDate);
    receivedOns.add(receivedOn);
    if (fail) return const Result.failure(NetworkFailure('timed out'));
    return const Result.success(
      Transaction(
        id: 't',
        shopId: 's1',
        productId: 'p1',
        type: 'restock',
        quantity: 1,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<ProviderContainer> _container(
  TransactionRepository repo, {
  DateTime Function()? now,
}) async {
  final c = ProviderContainer(
    overrides: [
      myShopProvider.overrideWith(
        (ref) async =>
            const Shop(id: 's1', ownerId: 'o1', name: 'Shop', currency: 'BDT'),
      ),
      transactionRepositoryProvider.overrideWithValue(repo),
      expiryReconcilerProvider.overrideWithValue(NoopReconciler()),
      nowProvider.overrideWithValue(now ?? () => DateTime(2026, 10, 14, 1, 30)),
    ],
  );
  addTearDown(c.dispose);
  await c.read(myShopProvider.future);
  return c;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('an identical restock on a later day is a new restock', () async {
    // Monday's restock commits but the reply is lost and the sheet is
    // closed; Tuesday's genuine, identical restock must not be swallowed as
    // a replay of Monday's (expiry review #6).
    final repo = _FlakyRestockRepo();
    var now = DateTime(2026, 10, 13, 18);
    final c = await _container(repo, now: () => now);
    final n = c.read(transactionControllerProvider.notifier);

    await n.recordRestock(productId: 'p1', quantity: 24);
    now = DateTime(2026, 10, 14, 9);
    await n.recordRestock(productId: 'p1', quantity: 24);

    expect(repo.ids[1], isNot(repo.ids[0]));
  });

  test('a retry of the same restock reuses the restock id', () async {
    final repo = _FlakyRestockRepo();
    final c = await _container(repo);
    final n = c.read(transactionControllerProvider.notifier);

    expect(await n.recordRestock(productId: 'p1', quantity: 2), isFalse);
    repo.fail = false;
    expect(await n.recordRestock(productId: 'p1', quantity: 2), isTrue);

    expect(repo.ids, hasLength(2));
    expect(repo.ids[1], repo.ids[0]);
  });

  test('a changed restock gets a new id', () async {
    final repo = _FlakyRestockRepo();
    final c = await _container(repo);
    final n = c.read(transactionControllerProvider.notifier);

    await n.recordRestock(productId: 'p1', quantity: 2);
    await n.recordRestock(productId: 'p1', quantity: 3);
    await n.recordRestock(
      productId: 'p1',
      quantity: 3,
      expiryDate: DateTime(2026, 11, 1),
    );

    expect(repo.ids.toSet(), hasLength(3));
  });

  test('the next restock after a success gets a new id', () async {
    final repo = _FlakyRestockRepo()..fail = false;
    final c = await _container(repo);
    final n = c.read(transactionControllerProvider.notifier);

    await n.recordRestock(productId: 'p1', quantity: 2);
    await n.recordRestock(productId: 'p1', quantity: 2);

    expect(repo.ids[1], isNot(repo.ids[0]));
  });

  test('the expiry date and the phone-local date added are sent', () async {
    final repo = _FlakyRestockRepo()..fail = false;
    final c = await _container(repo);
    await c
        .read(transactionControllerProvider.notifier)
        .recordRestock(
          productId: 'p1',
          quantity: 2,
          expiryDate: DateTime(2026, 11, 1),
        );

    expect(repo.expiries.single, DateTime(2026, 11, 1));
    // 01:30 local on 14 Oct is still 13 Oct in UTC -- the phone's date wins.
    expect(repo.receivedOns.single, DateTime(2026, 10, 14));
  });
}
