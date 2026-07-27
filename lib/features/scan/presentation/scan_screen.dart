import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/failure.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../cart/presentation/add_to_cart_sheet.dart';
import '../../inventory/domain/product.dart';
import '../../inventory/presentation/inventory_controller.dart';
import '../domain/scan_decision.dart';
import 'product_picker_sheet.dart';
import 'scan_controller.dart';

/// Drives the scan flow: opens the camera immediately, recognizes, then routes
/// to a confirmation sheet / chooser / manual pick. Every resolved product --
/// even a high-confidence auto match -- pauses on [showAddToCartSheet] so the
/// shopkeeper can see what was recognized and set a quantity before it lands
/// in the cart; AI output is never auto-committed. Confirming (or cancelling)
/// reopens the camera so items can be scanned back-to-back; the AppBar back
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
    final l10n = context.l10n;
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
          () => _error =
              e is Failure ? l10n.common_couldNotRecognize : l10n.scan_failed,
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
        return _confirmAndAdd(outcome.products.first);
      case ScanAction.chooseFromMatches:
        final picked = await showProductPickerSheet(
          context,
          products: outcome.products,
          title: context.l10n.scan_didYouMean,
        );
        if (picked == null) {
          if (mounted) context.pop();
          return false;
        }
        return _confirmAndAdd(picked);
      case ScanAction.noMatch:
        return _noMatch();
    }
  }

  /// Opens the add-to-cart confirmation sheet for [product] so the shopkeeper
  /// sets the quantity before it enters the cart, then returns true to keep
  /// scanning (the AppBar back arrow, not a successful add, is how a shopkeeper
  /// exits to review the cart). The sheet owns stock handling, the add, and the
  /// success haptic; a Cancel/dismiss simply adds nothing and returns to the
  /// camera.
  Future<bool> _confirmAndAdd(Product product) async {
    final added = await showAddToCartSheet(context, product: product);
    if (!mounted) return false;
    if (added == true) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(context.l10n.scan_addedToCart(product.name))),
        );
    }
    return true;
  }

  Future<bool> _noMatch() async {
    // Manual fallback pulls the full catalog from the inventory stream.
    final all = ref.read(_allProductsForPicker);
    final picked = await showProductPickerSheet(
      context,
      products: all,
      title: context.l10n.scan_noMatchPick,
    );
    if (picked == null) {
      if (mounted) context.pop();
      return false;
    }
    return _confirmAndAdd(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.inventory_scanProduct)),
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
                  FilledButton(onPressed: _run, child: Text(context.l10n.common_retry)),
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
