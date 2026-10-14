import 'package:ai_shopkeeper/core/error/failure.dart';
import 'package:ai_shopkeeper/core/error/result.dart';
import 'package:ai_shopkeeper/features/auth/data/auth_repository.dart';
import 'package:ai_shopkeeper/features/auth/domain/shop.dart';
import 'package:ai_shopkeeper/features/expiry/data/batch_repository.dart';
import 'package:ai_shopkeeper/features/expiry/domain/expiry_estimate.dart';
import 'package:ai_shopkeeper/features/expiry/domain/product_batch.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/expiry_reconciler.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/today_provider.dart';
import 'package:ai_shopkeeper/features/inventory/data/product_repository.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBatchRepo implements BatchRepository {
  _FakeBatchRepo(this.calls, {this.batches = const [], this.failRead = false});
  final List<String> calls;
  final List<ProductBatch> batches;
  final bool failRead;
  List<ReconcileWrite>? applied;

  @override
  Future<Result<List<ProductBatch>>> fetchOpenBatches(String shopId) async {
    calls.add('batches');
    if (failRead) return const Result.failure(NetworkFailure('offline'));
    return Result.success(batches);
  }

  @override
  Future<Result<void>> applyReconcile(List<ReconcileWrite> writes) async {
    calls.add('apply');
    applied = writes;
    return const Result.success(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProductRepo implements ProductRepository {
  _FakeProductRepo(this.calls, this.products);
  final List<String> calls;
  final List<Product> products;

  @override
  Future<Result<List<Product>>> fetchActiveProducts(String shopId) async {
    calls.add('products');
    return Result.success(products);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _pepsi = Product(id: 'pepsi', shopId: 's1', name: 'Pepsi', quantity: 15);
final _old = ProductBatch(
  id: 'old',
  shopId: 's1',
  productId: 'pepsi',
  quantity: 5,
  receivedOn: DateTime(2026, 10, 1),
  expiryDate: DateTime(2026, 10, 20),
);
final _new = ProductBatch(
  id: 'new',
  shopId: 's1',
  productId: 'pepsi',
  quantity: 10,
  receivedOn: DateTime(2026, 10, 10),
  expiryDate: DateTime(2026, 12, 15),
);

Future<ProviderContainer> _container(
  BatchRepository b,
  ProductRepository p,
) async {
  final c = ProviderContainer(
    overrides: [
      myShopProvider.overrideWith(
        (ref) async =>
            const Shop(id: 's1', ownerId: 'o1', name: 'Shop', currency: 'BDT'),
      ),
      batchRepositoryProvider.overrideWithValue(b),
      productRepositoryProvider.overrideWithValue(p),
      nowProvider.overrideWithValue(() => DateTime(2026, 10, 21, 10)),
    ],
  );
  addTearDown(c.dispose);
  await c.read(myShopProvider.future);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reconcile reads deliveries before products, then writes', () async {
    final calls = <String>[];
    final batches = _FakeBatchRepo(calls, batches: [_old, _new]);
    final c = await _container(batches, _FakeProductRepo(calls, [_pepsi]));

    final outcome = await c.read(expiryReconcilerProvider).run();

    expect(calls, ['batches', 'products', 'apply']);
    expect(batches.applied, [const LockExpired('old', 5)]);
    expect(outcome.ok, isTrue);
    // The outcome reflects the lock already applied.
    expect(outcome.byProduct['pepsi']!.expired, 5);
    expect(outcome.byProduct['pepsi']!.good, 10);
    expect(outcome.byProduct['pepsi']!.writes, isEmpty);
  });

  test('a shop with no deliveries reads nothing else', () async {
    final calls = <String>[];
    final c = await _container(
      _FakeBatchRepo(calls),
      _FakeProductRepo(calls, [_pepsi]),
    );
    final outcome = await c.read(expiryReconcilerProvider).run();
    expect(calls, ['batches']);
    expect(outcome.ok, isTrue);
    expect(outcome.byProduct, isEmpty);
  });

  test('a failed read is reported, not thrown', () async {
    final calls = <String>[];
    final c = await _container(
      _FakeBatchRepo(calls, failRead: true),
      _FakeProductRepo(calls, [_pepsi]),
    );
    final outcome = await c.read(expiryReconcilerProvider).run();
    expect(outcome.ok, isFalse);
    expect(outcome.failure, isA<NetworkFailure>());
  });

  test('overlapping runs do not interleave', () async {
    final calls = <String>[];
    final c = await _container(
      _FakeBatchRepo(calls, batches: [_old, _new]),
      _FakeProductRepo(calls, [_pepsi]),
    );
    final r = c.read(expiryReconcilerProvider);
    await Future.wait([r.run(), r.run()]);
    expect(calls, [
      'batches',
      'products',
      'apply',
      'batches',
      'products',
      'apply',
    ]);
  });
}
