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
  }) async {
    log.add('update $batchId clearLock=$clearLock');
    return _r;
  }

  @override
  Future<Result<void>> closeBatch(String batchId, String reason) async {
    log.add('close $batchId $reason');
    return _r;
  }

  @override
  Future<Result<void>> removeExpiredStock({
    required String shopId,
    required String batchId,
  }) async {
    log.add('remove $shopId $batchId');
    return _r;
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

Future<ProviderContainer> _container(_Repo repo) async {
  final c = ProviderContainer(
    overrides: [
      myShopProvider.overrideWith(
        (ref) async =>
            const Shop(id: 's1', ownerId: 'o1', name: 'Shop', currency: 'BDT'),
      ),
      batchRepositoryProvider.overrideWithValue(repo),
      expiryReconcilerProvider.overrideWithValue(NoopReconciler()),
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

  test('a failure is reported and surfaced as an error state', () async {
    final c = await _container(_Repo(fail: true));
    final ok = await c
        .read(batchActionsControllerProvider.notifier)
        .markNoneLeft('b1');
    expect(ok, isFalse);
    expect(c.read(batchActionsControllerProvider).error, isA<NetworkFailure>());
  });
}
