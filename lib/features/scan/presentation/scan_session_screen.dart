import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/haptics.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../l10n/app_localizations.dart';
import '../../inventory/domain/product.dart';
import '../../inventory/presentation/inventory_controller.dart';
import '../data/scan_camera.dart';
import '../domain/scan_item.dart';
import 'product_picker_sheet.dart';
import 'scan_session_controller.dart';
import 'scan_tray.dart';
import 'top_sellers_strip.dart';

/// The scan session. The viewfinder never closes and recognition happens behind
/// it, so a basket is shot in one continuous run instead of one modal per item.
/// Nothing reaches the cart until "Add" -- the tray, not a per-item sheet, is
/// where AI output gets confirmed.
class ScanSessionScreen extends ConsumerStatefulWidget {
  const ScanSessionScreen({super.key});

  @override
  ConsumerState<ScanSessionScreen> createState() => _ScanSessionScreenState();
}

class _ScanSessionScreenState extends ConsumerState<ScanSessionScreen>
    with WidgetsBindingObserver {
  bool _ready = false;
  bool _denied = false;

  /// The device reports no camera hardware at all (most often an emulator).
  /// Kept distinct from [_denied]: "open Settings" is the right recovery for a
  /// refused permission but wrong advice here -- there is no permission to
  /// grant, so that button is simply not shown for this state.
  bool _unavailable = false;

  /// Captured once in [initState] rather than read from `ref` again in
  /// [dispose]/[didChangeAppLifecycleState]: those can run while this
  /// element's own `ref` is no longer safe to read (e.g. the whole tree
  /// unmounting at once, as widget-test teardown does), and `ref.read` there
  /// throws "using ref when a widget is about to or has been unmounted".
  late final ScanCamera _camera;

  @override
  void initState() {
    super.initState();
    _camera = ref.read(scanCameraProvider);
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  Future<void> _start() async {
    try {
      await _camera.initialize();
      if (mounted) {
        setState(() {
          _ready = true;
          _denied = false;
          _unavailable = false;
        });
      }
    } on CameraPermissionDenied {
      if (mounted) setState(() => _denied = true);
    } on CameraUnavailable {
      if (mounted) setState(() => _unavailable = true);
    }
  }

  /// Android reclaims the camera when the app leaves the foreground. Without
  /// this the user returns to a frozen preview and a leaked handle -- the
  /// best-known trap in the `camera` package. The tray is untouched by it.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _camera.dispose();
      if (mounted) setState(() => _ready = false);
    } else if (state == AppLifecycleState.resumed &&
        !_denied &&
        !_unavailable) {
      _start();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera.dispose();
    super.dispose();
  }

  Future<void> _shutter() async {
    AppHaptics.tap();
    await ref.read(scanSessionProvider.notifier).capture();
  }

  Future<void> _pick(ScanItem item) async {
    final all = item.choices.isNotEmpty
        ? item.choices
        : (ref.read(productsStreamProvider).value ?? const <Product>[]);
    final picked = await showProductPickerSheet(
      context,
      products: all,
      title: context.l10n.scan_didYouMean,
      readLabel: item.readLabel,
    );
    if (picked != null) {
      ref.read(scanSessionProvider.notifier).choose(item.id, picked);
    }
  }

  Future<void> _addAll() async {
    final items = ref.read(scanSessionProvider);
    final unresolved = items.where((i) => !i.isAddable).length;
    if (unresolved > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.l10n.scan_discardTitle),
          content: Text(ctx.l10n.scan_discardBody(unresolved)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(ctx.l10n.common_cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(ctx.l10n.common_add),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    ref.read(scanSessionProvider.notifier).addAllToCart();
    AppHaptics.success();
    if (mounted) context.pop();
  }

  Future<bool> _confirmLeave() async {
    final staged = ref.read(scanSessionProvider).length;
    if (staged == 0) return true;
    final choice = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.scan_leaveTitle),
        content: Text(ctx.l10n.scan_leaveBody(staged)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.l10n.common_discard),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.l10n.common_add),
          ),
        ],
      ),
    );
    if (choice == true) {
      ref.read(scanSessionProvider.notifier).addAllToCart();
    } else {
      ref.read(scanSessionProvider.notifier).clear();
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final items = ref.watch(scanSessionProvider);
    final pending = items.where((i) => i.isPending).length;
    final addable = items.where((i) => i.isAddable).length;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) context.pop();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.inventory_scanProduct)),
        body: Column(
          children: [
            Expanded(child: _viewfinder(l10n)),
            const TopSellersStrip(),
            const Divider(height: 1),
            ScanTray(onPick: _pick),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: FilledButton(
                  key: const Key('scan-add-all'),
                  onPressed: (pending > 0 || addable == 0) ? null : _addAll,
                  child: Text(
                    pending > 0
                        ? l10n.scan_recognizing(pending)
                        : l10n.scan_addItems(addable),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _viewfinder(AppLocalizations l10n) {
    if (_denied) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined, size: 48),
              const SizedBox(height: 12),
              Text(l10n.scan_cameraDenied, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _start,
                child: Text(l10n.scan_openSettings),
              ),
            ],
          ),
        ),
      );
    }
    if (_unavailable) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off_outlined, size: 48),
              const SizedBox(height: 12),
              Text(l10n.scan_cameraUnavailable, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }
    if (!_ready) return const Center(child: CircularProgressIndicator());
    return Stack(
      fit: StackFit.expand,
      children: [
        _camera.buildPreview(context),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: FloatingActionButton.large(
              key: const Key('scan-shutter'),
              onPressed: _shutter,
              child: const Icon(Icons.camera_alt),
            ),
          ),
        ),
      ],
    );
  }
}
