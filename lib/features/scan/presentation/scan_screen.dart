import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/haptics.dart';
import '../../../core/error/failure.dart';
import '../../cart/domain/cart_math.dart';
import '../../cart/presentation/cart_controller.dart';
import '../../inventory/domain/product.dart';
import '../../inventory/presentation/inventory_controller.dart';
import '../domain/scan_decision.dart';
import 'product_picker_sheet.dart';
import 'scan_controller.dart';

/// Drives the scan flow: opens the camera immediately, recognizes, then routes
/// to add-to-cart / chooser / manual pick. A successful add reopens the camera
/// so a shopkeeper can scan a customer's items back-to-back; the AppBar back
/// arrow exits to Inventory, where the global cart bar reflects everything
/// scanned so far. Cart items still only commit via the Cart screen's
/// checkout -- scanning never auto-commits a sale.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    while (true) {
      setState(() {
        _busy = true;
        _error = null;
      });
      try {
        final outcome = await ref
            .read(scanControllerProvider)
            .captureAndRecognize();
        if (!mounted) return;
        if (outcome == null) {
          context.pop(); // user cancelled the camera
          return;
        }
        final again = await _route(outcome);
        if (!mounted) return;
        if (!again) return;
      } catch (e) {
        if (!mounted) return;
        setState(
          () => _error = e is Failure ? e.message : 'Scan failed. Try again.',
        );
        return;
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  /// Routes a recognition outcome. Returns true to keep scanning (the loop in
  /// [_run] reopens the camera for another shot), false to exit the screen.
  Future<bool> _route(ScanOutcome outcome) async {
    switch (outcome.action) {
      case ScanAction.autoSell:
        if (outcome.products.isEmpty) return _noMatch();
        return _addToCart(outcome.products.first);
      case ScanAction.chooseFromMatches:
        final picked = await showProductPickerSheet(
          context,
          products: outcome.products,
          title: 'Did you mean?',
        );
        if (picked == null) {
          if (mounted) context.pop();
          return false;
        }
        return _addToCart(picked);
      case ScanAction.noMatch:
        return _noMatch();
    }
  }

  /// Adds a unit-aware increment of [product] to the cart. Always returns
  /// true (keep scanning) -- the AppBar back arrow, not a successful add, is
  /// how a shopkeeper exits to review the cart.
  Future<bool> _addToCart(Product product) async {
    final cart = ref.read(cartControllerProvider.notifier);
    if (cart.remainingStockFor(product) <= 0) {
      if (mounted) {
        final message = product.quantity <= 0
            ? '${product.name} is out of stock.'
            : '${product.name} is already fully staged in your cart.';
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      }
      return true;
    }
    cart.addOrIncrement(product, stepForUnit(product.unit));
    AppHaptics.success();
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Added ${product.name} to cart')));
    }
    return true;
  }

  Future<bool> _noMatch() async {
    // Manual fallback pulls the full catalog from the inventory stream.
    final all = ref.read(_allProductsForPicker);
    final picked = await showProductPickerSheet(
      context,
      products: all,
      title: 'No match — pick the product',
    );
    if (picked == null) {
      if (mounted) context.pop();
      return false;
    }
    return _addToCart(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan product')),
      body: Center(
        child: _error != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _run, child: const Text('Retry')),
                ],
              )
            : _busy
            ? const CircularProgressIndicator()
            : const SizedBox.shrink(),
      ),
    );
  }
}

final _allProductsForPicker = Provider<List<Product>>(
  (ref) => ref.watch(productsStreamProvider).value ?? const <Product>[],
);
