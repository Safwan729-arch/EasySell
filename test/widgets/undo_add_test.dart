import 'package:ai_shopkeeper/features/auth/data/auth_repository.dart';
import 'package:ai_shopkeeper/features/auth/domain/shop.dart';
import 'package:ai_shopkeeper/features/cart/presentation/cart_controller.dart';
import 'package:ai_shopkeeper/features/cart/presentation/undo_add.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Product _p(String id) => Product(id: id, shopId: 's', name: 'Item $id', quantity: 100);

void main() {
  testWidgets('tapping Undo restores the cart to the snapshot', (tester) async {
    late WidgetRef capturedRef;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myShopProvider.overrideWith(
            (ref) => const Shop(id: 's', ownerId: 'o', name: 'Shop', currency: 'USD'),
          ),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              capturedRef = ref;
              return Scaffold(
                body: Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () {
                      final notifier = ref.read(cartControllerProvider.notifier);
                      final snapshot = ref.read(cartControllerProvider); // empty
                      notifier.addOrIncrement(_p('a'), 3); // cart now has 1 line
                      showUndoableAddSnackBar(
                        ScaffoldMessenger.of(context),
                        ref,
                        message: 'Added',
                        undoLabel: 'Undo',
                        snapshot: snapshot,
                      );
                    },
                    child: const Text('add'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('add'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    expect(capturedRef.read(cartControllerProvider).length, 1);

    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(capturedRef.read(cartControllerProvider), isEmpty);
  });
}
