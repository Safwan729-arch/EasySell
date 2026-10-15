import 'package:ai_shopkeeper/core/error/failure.dart';
import 'package:ai_shopkeeper/core/error/result.dart';
import 'package:ai_shopkeeper/features/auth/data/auth_repository.dart';
import 'package:ai_shopkeeper/features/auth/domain/shop.dart';
import 'package:ai_shopkeeper/features/expiry/data/batch_repository.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/today_provider.dart';
import 'package:ai_shopkeeper/features/inventory/data/product_repository.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/inventory/presentation/inventory_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ProductRepo implements ProductRepository {
  @override
  Future<Result<Product>> addProduct(Product product) async =>
      Result.success(product.copyWith(id: 'new-id'));

  @override
  Future<Result<Product>> updateProduct(Product product) async =>
      Result.success(product);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BatchRepo implements BatchRepository {
  _BatchRepo({this.fail = false});
  final bool fail;
  final added = <Map<String, Object>>[];

  @override
  Future<Result<void>> addBatch({
    required String shopId,
    required String productId,
    required double quantity,
    required double buyingPrice,
    required DateTime receivedOn,
    required DateTime expiryDate,
  }) async {
    added.add({
      'productId': productId,
      'quantity': quantity,
      'buyingPrice': buyingPrice,
      'receivedOn': receivedOn,
      'expiryDate': expiryDate,
    });
    if (fail) return const Result.failure(NetworkFailure('offline'));
    return const Result.success(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<ProviderContainer> _container(_BatchRepo batches) async {
  final c = ProviderContainer(
    overrides: [
      myShopProvider.overrideWith(
        (ref) async =>
            const Shop(id: 's1', ownerId: 'o1', name: 'Shop', currency: 'BDT'),
      ),
      productRepositoryProvider.overrideWithValue(_ProductRepo()),
      batchRepositoryProvider.overrideWithValue(batches),
      nowProvider.overrideWithValue(() => DateTime(2026, 10, 14, 9)),
    ],
  );
  addTearDown(c.dispose);
  await c.read(myShopProvider.future);
  return c;
}

const _bread = Product(
  id: '',
  shopId: '',
  name: 'Bread',
  quantity: 10,
  buyingPrice: 40,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'a new product with an expiry date records its first delivery',
    () async {
      final batches = _BatchRepo();
      final c = await _container(batches);
      final outcome = await c
          .read(inventoryControllerProvider.notifier)
          .save(_bread, isNew: true, expiryDate: DateTime(2026, 10, 18));

      expect(outcome, ProductSaveOutcome.saved);
      expect(batches.added.single, {
        'productId': 'new-id',
        'quantity': 10.0,
        'buyingPrice': 40.0,
        'receivedOn': DateTime(2026, 10, 14),
        'expiryDate': DateTime(2026, 10, 18),
      });
    },
  );

  test('a failed delivery insert keeps the product and says so', () async {
    final c = await _container(_BatchRepo(fail: true));
    final outcome = await c
        .read(inventoryControllerProvider.notifier)
        .save(_bread, isNew: true, expiryDate: DateTime(2026, 10, 18));
    expect(outcome, ProductSaveOutcome.savedWithoutExpiry);
  });

  test('no delivery for zero stock or for an edit', () async {
    final batches = _BatchRepo();
    final c = await _container(batches);
    final n = c.read(inventoryControllerProvider.notifier);
    await n.save(
      _bread.copyWith(quantity: 0),
      isNew: true,
      expiryDate: DateTime(2026, 10, 18),
    );
    await n.save(
      _bread.copyWith(id: 'p1'),
      isNew: false,
      expiryDate: DateTime(2026, 10, 18),
    );
    expect(batches.added, isEmpty);
  });
}
