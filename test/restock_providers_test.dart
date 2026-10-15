import 'package:ai_shopkeeper/core/error/failure.dart';
import 'package:ai_shopkeeper/core/error/result.dart';
import 'package:ai_shopkeeper/features/auth/data/auth_repository.dart';
import 'package:ai_shopkeeper/features/auth/domain/shop.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/expiry_providers.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/today_provider.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/inventory/presentation/inventory_controller.dart';
import 'package:ai_shopkeeper/features/restock/data/restock_repository.dart';
import 'package:ai_shopkeeper/features/restock/domain/restock_plan.dart';
import 'package:ai_shopkeeper/features/restock/presentation/restock_providers.dart';
import 'package:ai_shopkeeper/shared/providers/refresh_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Final review 2026-10-15: the widget tests override [restockPlanProvider]
/// with a ready-made value, so they never saw how the REAL providers behave
/// on a failure or a refresh.
class _Repo implements RestockRepository {
  _Repo(this.result);
  Result<List<RestockSpeed>> result;
  int calls = 0;

  @override
  Future<Result<List<RestockSpeed>>> fetchSpeeds(
    String shopId, {
    required DateTime today,
    required int utcOffsetMinutes,
  }) async {
    calls++;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _mojo = Product(id: 'mojo', shopId: 's1', name: 'Mojo', quantity: 10);

ProviderContainer _container(
  _Repo repo, {
  Stream<List<Product>> Function()? products,
  Future<Shop?> Function()? shop,
}) {
  final c = ProviderContainer(
    // myShopProvider keeps Riverpod's default retry in the app (loading while
    // it retries is true); here a failure is final at once.
    retry: (_, _) => null,
    overrides: [
      restockRepositoryProvider.overrideWithValue(repo),
      myShopProvider.overrideWith(
        (ref) =>
            shop?.call() ??
            Future.value(
              const Shop(
                id: 's1',
                ownerId: 'o1',
                name: 'Shop',
                currency: 'BDT',
              ),
            ),
      ),
      productsStreamProvider.overrideWith(
        (ref) => products?.call() ?? Stream.value([_mojo]),
      ),
      productExpiryProvider.overrideWithValue(const {}),
      nowProvider.overrideWithValue(() => DateTime(2026, 10, 15, 10)),
    ],
  );
  addTearDown(c.dispose);
  c.listen(restockPlanProvider, (_, _) {});
  return c;
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a failure shows as an error at once and is not retried', () async {
    // Riverpod retries a failing provider ~10 times over ~40 s by default,
    // showing a spinner the whole time (0017 not run, or offline).
    final repo = _Repo(
      const Result.failure(NetworkFailure('No internet connection.')),
    );
    final c = _container(repo);
    await _settle();
    expect(c.read(restockPlanProvider), isA<AsyncError<RestockPlan>>());

    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(repo.calls, 1, reason: 'no automatic retry');
  });

  test('a refresh keeps the last plan instead of a spinner', () async {
    // whenData turned the reload's AsyncLoading(previous) into a bare
    // AsyncLoading: after every restock the list and the Home card blanked.
    final repo = _Repo(
      const Result.success([RestockSpeed(productId: 'mojo', speed: 5)]),
    );
    final c = _container(repo);
    await _settle();
    expect(c.read(restockPlanProvider).value?.buyNow.single.suggestion, 35);

    c.read(dataRefreshProvider.notifier).bump();
    final during = c.read(restockPlanProvider);
    expect(during.value?.buyNow.single.suggestion, 35);

    await _settle();
    expect(repo.calls, 2);
    expect(c.read(restockPlanProvider).value?.buyNow, hasLength(1));
  });

  RestockSpeed mojoSpeed() => const RestockSpeed(productId: 'mojo', speed: 5);

  test('the shop record reloading with the same id does not refetch', () async {
    // An auth token refresh reloads myShopProvider; only the shop id matters.
    final repo = _Repo(Result.success([mojoSpeed()]));
    final c = _container(repo);
    await _settle();
    expect(repo.calls, 1);

    c.invalidate(myShopProvider);
    await _settle();
    expect(repo.calls, 1);
  });

  test('a failed shop lookup is an error, not "nothing to restock"', () async {
    final repo = _Repo(Result.success([mojoSpeed()]));
    final c = _container(
      repo,
      shop: () => Future.error(const NetworkFailure('offline')),
    );
    await _settle();
    expect(c.read(restockPlanProvider), isA<AsyncError<RestockPlan>>());
  });

  test('products still loading: loading, not "nothing to restock"', () async {
    final repo = _Repo(Result.success([mojoSpeed()]));
    final c = _container(repo, products: () => const Stream.empty());
    await _settle();
    expect(c.read(restockPlanProvider), isA<AsyncLoading<RestockPlan>>());
  });

  test('products failed: an error, not "nothing to restock"', () async {
    final repo = _Repo(Result.success([mojoSpeed()]));
    final c = _container(
      repo,
      products: () => Stream.error(const NetworkFailure('offline')),
    );
    await _settle();
    expect(c.read(restockPlanProvider), isA<AsyncError<RestockPlan>>());
  });

  test('Retry shows loading at once, then the result', () async {
    // invalidate keeps the error and only sets isLoading, so the screen kept
    // showing the error with no sign that Retry did anything.
    final repo = _Repo(const Result.failure(NetworkFailure('offline')));
    final c = _container(repo);
    await _settle();
    expect(c.read(restockPlanProvider), isA<AsyncError<RestockPlan>>());

    c.invalidate(restockSpeedsProvider);
    expect(c.read(restockPlanProvider), isA<AsyncLoading<RestockPlan>>());

    await _settle();
    expect(repo.calls, 2);
    expect(c.read(restockPlanProvider), isA<AsyncError<RestockPlan>>());
  });
}
