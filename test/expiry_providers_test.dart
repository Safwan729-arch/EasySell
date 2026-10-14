import 'package:ai_shopkeeper/features/expiry/domain/product_batch.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/expiry_providers.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/today_provider.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/inventory/presentation/inventory_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'with no deliveries the alerts are empty and "today" is never started',
    () async {
      // todayProvider arms a midnight timer; a shop that never records an
      // expiry date (and every widget test without a backend) must not pay for
      // it -- a pending timer fails widget tests.
      final c = ProviderContainer(
        overrides: [
          productsStreamProvider.overrideWith(
            (ref) => Stream.value(const [
              Product(id: 'p', shopId: 's', name: 'Soap'),
            ]),
          ),
          batchesStreamProvider.overrideWith(
            (ref) => Stream.value(const <ProductBatch>[]),
          ),
        ],
      );
      addTearDown(c.dispose);
      final sub = c.listen(expiryAlertsProvider, (_, _) {});
      addTearDown(sub.close);
      await c.read(productsStreamProvider.future);
      await c.read(batchesStreamProvider.future);

      expect(c.read(expiryAlertsProvider), isEmpty);
      expect(c.exists(todayProvider), isFalse);
    },
  );
}
