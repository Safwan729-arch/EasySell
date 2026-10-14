import 'package:ai_shopkeeper/core/error/failure.dart';
import 'package:ai_shopkeeper/core/error/result.dart';
import 'package:ai_shopkeeper/features/auth/data/auth_repository.dart';
import 'package:ai_shopkeeper/features/auth/domain/shop.dart';
import 'package:ai_shopkeeper/features/expiry/data/batch_repository.dart';
import 'package:ai_shopkeeper/features/expiry/domain/product_batch.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/batch_actions_controller.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/expiry_reconciler.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/today_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/expiry_fakes.dart';

class _Repo implements BatchRepository {
  _Repo({this.fail = false});
  final bool fail;
  final log = <String>[];

  Result<void> get _r => fail
      ? const Result.failure(NetworkFailure('offline'))
      : const Result.success(null);

  @override
  Future<Result<void>> updateBatch({
    required String batchId,
    required double quantity,
    required DateTime expiryDate,
    required bool clearLock,
    double? lockedQty,
  }) async {
    log.add(
      'update $batchId clearLock=$clearLock'
      '${lockedQty == null ? '' : ' lock=$lockedQty'}',
    );
    return _r;
  }

  @override
  Future<Result<void>> closeBatch(String batchId, String reason) async {
    log.add('close $batchId $reason');
    return _r;
  }

  @override
  Future<Result<void>> removeStock({
    required String shopId,
    required String batchId,
    double? quantity,
    bool close = true,
    String? removalId,
  }) async {
    removalIds.add(removalId);
    log.add(
      'remove $shopId $batchId'
      '${quantity == null ? '' : ' qty=$quantity'}'
      '${close ? '' : ' keep-open'}',
    );
    return _r;
  }

  final removalIds = <String?>[];

  @override
  Future<Result<void>> removeUndatedStock({
    required String shopId,
    required String productId,
    required double quantity,
    required String removalId,
  }) async {
    removalIds.add(removalId);
    log.add('remove-undated $shopId $productId qty=$quantity');
    return _r;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LoggingReconciler implements ExpiryReconciler {
  _LoggingReconciler(this.log);
  final List<String> log;

  @override
  Future<ReconcileOutcome> run() async {
    log.add('reconcile');
    return const ReconcileOutcome.ok({});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _locked = ProductBatch(
  id: 'b1',
  shopId: 's1',
  productId: 'p1',
  quantity: 5,
  receivedOn: DateTime(2026, 10, 1),
  expiryDate: DateTime(2026, 10, 2),
  expiredQty: 5,
);

Future<ProviderContainer> _container(
  _Repo repo, {
  ExpiryReconciler? reconciler,
}) async {
  final c = ProviderContainer(
    overrides: [
      myShopProvider.overrideWith(
        (ref) async =>
            const Shop(id: 's1', ownerId: 'o1', name: 'Shop', currency: 'BDT'),
      ),
      batchRepositoryProvider.overrideWithValue(repo),
      expiryReconcilerProvider.overrideWithValue(
        reconciler ?? NoopReconciler(),
      ),
      nowProvider.overrideWithValue(() => DateTime(2026, 10, 14, 9)),
    ],
  );
  addTearDown(c.dispose);
  await c.read(myShopProvider.future);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('correcting a mistyped date into the future clears the lock', () async {
    final repo = _Repo();
    final c = await _container(repo);
    await c
        .read(batchActionsControllerProvider.notifier)
        .editBatch(_locked, quantity: 5, expiryDate: DateTime(2026, 10, 20));
    expect(repo.log, ['update b1 clearLock=true']);
  });

  test('a date still in the past keeps the lock', () async {
    final repo = _Repo();
    final c = await _container(repo);
    await c
        .read(batchActionsControllerProvider.notifier)
        .editBatch(_locked, quantity: 5, expiryDate: DateTime(2026, 10, 5));
    expect(repo.log, ['update b1 clearLock=false']);
  });

  test(
    'lowering the amount of a still-expired delivery lowers its lock',
    () async {
      // Typed 50 instead of 5 and locked at 50: correcting the amount must
      // correct the expired count, or "Remove from stock" removes 50 (45 of
      // them good) and calls them a loss.
      final repo = _Repo();
      final c = await _container(repo);
      await c
          .read(batchActionsControllerProvider.notifier)
          .editBatch(_locked, quantity: 3, expiryDate: DateTime(2026, 10, 5));
      expect(repo.log, ['update b1 clearLock=false lock=3.0']);
    },
  );

  test(
    'they-are-not-expired closes each expired delivery with that reason',
    () async {
      final repo = _Repo();
      final c = await _container(repo);
      await c.read(batchActionsControllerProvider.notifier).markNotExpired([
        'b1',
        'b2',
      ]);
      expect(repo.log, ['close b1 not_expired', 'close b2 not_expired']);
    },
  );

  test(
    'remove expired calls the server once per delivery with the shop',
    () async {
      final repo = _Repo();
      final c = await _container(repo);
      final ok = await c
          .read(batchActionsControllerProvider.notifier)
          .removeExpired(['b1']);
      expect(ok, isTrue);
      expect(repo.log, ['remove s1 b1']);
    },
  );

  test('remove expired stores pending expired counts first', () async {
    // A delivery shown as expired by its date may not be locked yet (just
    // added with a past date, just after midnight); the server refuses to
    // remove an unlocked one ("Delivery is not expired").
    final repo = _Repo();
    final c = await _container(repo, reconciler: _LoggingReconciler(repo.log));
    await c.read(batchActionsControllerProvider.notifier).removeExpired(['b1']);
    expect(repo.log.take(2), ['reconcile', 'remove s1 b1']);
  });

  test(
    'a delivery that has not expired is removed by the amount shown',
    () async {
      // Thrown away or returned early: the server cannot know how much of an
      // unexpired delivery is left (it is an estimate), so the app sends it.
      final repo = _Repo();
      final c = await _container(repo);
      final ok = await c
          .read(batchActionsControllerProvider.notifier)
          .removeBatch('b2', quantity: 7, left: 7);
      expect(ok, isTrue);
      expect(repo.log, ['remove s1 b2 qty=7.0']);
    },
  );

  test('removing part of a delivery keeps it open', () async {
    // One broken bottle out of 10: the other 9 are still on the shelf.
    final repo = _Repo();
    final c = await _container(repo);
    await c
        .read(batchActionsControllerProvider.notifier)
        .removeBatch('b2', quantity: 1, left: 10);
    expect(repo.log, ['remove s1 b2 qty=1.0 keep-open']);
  });

  test('a retry of an unanswered removal re-sends its id', () async {
    // A partial removal leaves the delivery open, so "already closed" cannot
    // catch a retry: without the same id a lost reply removes it twice.
    final repo = _Repo(fail: true);
    final c = await _container(repo);
    final actions = c.read(batchActionsControllerProvider.notifier);
    await actions.removeBatch('b2', quantity: 1, left: 10);
    await actions.removeBatch('b2', quantity: 1, left: 10);
    await actions.removeBatch('b2', quantity: 2, left: 10);
    expect(repo.removalIds[0], isNotNull);
    expect(repo.removalIds[1], repo.removalIds[0]);
    expect(repo.removalIds[2], isNot(repo.removalIds[0]));
  });

  test('stock with no date can be removed, retry-safe', () async {
    // Soap has no deliveries: without this, a broken bar could never come off
    // stock once the product form lost its stock box.
    final repo = _Repo(fail: true);
    final c = await _container(repo);
    final actions = c.read(batchActionsControllerProvider.notifier);
    await actions.removeUndated('soap', quantity: 2);
    await actions.removeUndated('soap', quantity: 2);
    expect(repo.log, [
      'remove-undated s1 soap qty=2.0',
      'remove-undated s1 soap qty=2.0',
    ]);
    expect(repo.removalIds[1], repo.removalIds[0]);
  });

  test('after a removal succeeds the same amount again is new', () async {
    final repo = _Repo();
    final c = await _container(repo);
    final actions = c.read(batchActionsControllerProvider.notifier);
    await actions.removeBatch('b2', quantity: 1, left: 10);
    await actions.removeBatch('b2', quantity: 1, left: 9);
    expect(repo.removalIds[1], isNot(repo.removalIds[0]));
  });

  test('a failure is reported and surfaced as an error state', () async {
    final c = await _container(_Repo(fail: true));
    final ok = await c
        .read(batchActionsControllerProvider.notifier)
        .removeBatch('b1', quantity: 1, left: 1);
    expect(ok, isFalse);
    expect(c.read(batchActionsControllerProvider).error, isA<NetworkFailure>());
  });
}
