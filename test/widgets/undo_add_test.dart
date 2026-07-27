import 'package:ai_shopkeeper/features/auth/data/auth_repository.dart';
import 'package:ai_shopkeeper/features/auth/domain/shop.dart';
import 'package:ai_shopkeeper/features/cart/presentation/cart_controller.dart';
import 'package:ai_shopkeeper/features/cart/presentation/undo_add.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Product _p(String id) => Product(id: id, shopId: 's', name: 'Item $id', quantity: 100);

ProviderContainer _container() => ProviderContainer(
  overrides: [
    myShopProvider.overrideWith(
      (ref) => const Shop(id: 's', ownerId: 'o', name: 'Shop', currency: 'USD'),
    ),
  ],
);

void main() {
  testWidgets('tapping Undo restores the cart to the snapshot', (tester) async {
    final container = _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  final notifier = container.read(cartControllerProvider.notifier);
                  final snapshot = container.read(cartControllerProvider); // empty
                  notifier.addOrIncrement(_p('a'), 3); // cart now has 1 line
                  showUndoableAddSnackBar(
                    ScaffoldMessenger.of(context),
                    message: 'Added',
                    undoLabel: 'Undo',
                    onUndo: () => notifier.restore(snapshot),
                  );
                },
                child: const Text('add'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('add'));
    await tester.pump();
    // Settle the SnackBar entrance transition (~250ms) before tapping Undo --
    // not pumpAndSettle(), which would fight the SnackBar's ~4s auto-dismiss
    // timer (pumpAndSettle keeps pumping until no frames are scheduled, and
    // that timer keeps one scheduled the whole time).
    await tester.pump(const Duration(milliseconds: 750));
    expect(container.read(cartControllerProvider).length, 1);

    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(container.read(cartControllerProvider), isEmpty);
  });

  // Regression test for the CRITICAL bug: the voice flow calls
  // `Navigator.of(context).pop()` (unmounting the review sheet) and pushes
  // `/cart` BEFORE the user gets a chance to tap Undo. If the SnackBarAction's
  // onPressed closure depended on a `WidgetRef`/`BuildContext` owned by that
  // now-unmounted widget, tapping Undo would throw (Riverpod 3.x's
  // `WidgetRef.read` asserts the widget is still mounted) and the cart would
  // never be restored. This test reproduces exactly that shape: the widget
  // that triggers the snackbar is popped off the Navigator (fully unmounted,
  // not just covered) before Undo is tapped, using a `CartController` notifier
  // read from a `ProviderContainer` that outlives the popped widget -- the
  // same pattern the fixed `_addToCart`/`_confirmAndAdd` call sites use.
  testWidgets(
    'Undo still restores the cart after the triggering widget is unmounted',
    (tester) async {
      final container = _container();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (childContext) => Scaffold(
                        body: ElevatedButton(
                          onPressed: () {
                            // Capture the notifier + snapshot from the
                            // PROVIDER CONTAINER (which outlives this page),
                            // never from this widget's own BuildContext/ref --
                            // that's the fix.
                            final notifier = container.read(
                              cartControllerProvider.notifier,
                            );
                            final snapshot = container.read(
                              cartControllerProvider,
                            ); // empty
                            final messenger = ScaffoldMessenger.of(
                              childContext,
                            );
                            notifier.addOrIncrement(_p('a'), 3);
                            // Unmount THIS page before the user can tap Undo --
                            // mirrors the voice flow popping the review sheet
                            // and pushing /cart before Undo is tapped.
                            Navigator.of(childContext).pop();
                            showUndoableAddSnackBar(
                              messenger,
                              message: 'Added',
                              undoLabel: 'Undo',
                              onUndo: () => notifier.restore(snapshot),
                            );
                          },
                          child: const Text('add on child page'),
                        ),
                      ),
                    ),
                  ),
                  child: const Text('open child page'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open child page'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('add on child page'));
      // Let the pop's route transition finish -- the child page (and its
      // context/element) is now fully unmounted.
      await tester.pumpAndSettle();
      expect(find.text('add on child page'), findsNothing);

      // Settle the SnackBar entrance transition (not pumpAndSettle(), which
      // would fight the SnackBar's own ~4s auto-dismiss timer).
      await tester.pump(const Duration(milliseconds: 750));
      expect(container.read(cartControllerProvider).length, 1);

      // The critical assertion: tapping Undo after the triggering widget is
      // gone must NOT throw, and must actually restore the cart.
      await tester.tap(find.text('Undo'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(container.read(cartControllerProvider), isEmpty);
    },
  );
}
