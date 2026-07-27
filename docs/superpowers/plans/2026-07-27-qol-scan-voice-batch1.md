# QoL Batch 1 (Scan & Voice) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three quality-of-life improvements to the scan and voice sale flows: show what the AI read on a scan, let the shopkeeper edit a misheard voice transcript and re-run the AI, and undo the last cart add from either flow.

**Architecture:** Thread the already-parsed `read_*` vision fields up to the scan UI; add a transcript re-parse path to the voice repository/controller reusing the deployed `parse-sale` text endpoint; make cart-undo a snapshot/restore on `CartController` surfaced through a shared snackbar helper.

**Tech Stack:** Flutter, Riverpod (`Notifier`), freezed, `flutter_localizations` / gen-l10n, `flutter_test`. Backend unchanged (no Edge Function edits).

## Global Constraints

- State management: Riverpod only (`Notifier`/`AsyncNotifier`); no other state libs.
- Widgets stay dumb; logic lives in controllers/repositories.
- Never hardcode secrets; no backend/secret changes in this batch.
- Localized user-facing strings only — add keys to BOTH `lib/l10n/app_en.arb` and `lib/l10n/app_bn.arb`, then regenerate with `flutter gen-l10n`.
- Never run `dart format .` repo-wide — format only the specific files touched.
- After each task: `flutter analyze lib test` clean and `flutter test` green.
- Branch: `feat/qol-scan-voice` (already created off `main`).
- Commit trailer on every commit: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

---

### Task 1: Cart undo — `CartController.restore`

**Files:**
- Modify: `lib/features/cart/presentation/cart_controller.dart`
- Test: `test/cart_controller_restore_test.dart` (create)

**Interfaces:**
- Produces: `void CartController.restore(List<CartLine> snapshot)` — sets cart state back to `snapshot`. Used by Task 5's snackbar helper.

- [ ] **Step 1: Write the failing test**

```dart
// test/cart_controller_restore_test.dart
import 'package:ai_shopkeeper/features/auth/data/auth_repository.dart';
import 'package:ai_shopkeeper/features/auth/domain/shop.dart';
import 'package:ai_shopkeeper/features/cart/domain/cart_line.dart';
import 'package:ai_shopkeeper/features/cart/presentation/cart_controller.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
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
  test('restore returns the cart to a captured snapshot', () {
    final c = _container();
    final notifier = c.read(cartControllerProvider.notifier);

    notifier.addOrIncrement(_p('a'), 2);
    final snapshot = c.read(cartControllerProvider); // [a x2]

    notifier.addOrIncrement(_p('b'), 5); // cart now [a x2, b x5]
    expect(c.read(cartControllerProvider).length, 2);

    notifier.restore(snapshot);
    expect(c.read(cartControllerProvider), equals(snapshot));
    expect(c.read(cartControllerProvider).length, 1);
    expect(c.read(cartControllerProvider).first.quantity, 2);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/cart_controller_restore_test.dart`
Expected: FAIL — `restore` is not defined on `CartController`.

- [ ] **Step 3: Add the method**

In `lib/features/cart/presentation/cart_controller.dart`, add after `clear()`:

```dart
  /// Reverts the cart to a previously captured [snapshot]. Used by the
  /// "undo last add" affordance after a scan or voice add.
  void restore(List<CartLine> snapshot) => state = snapshot;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/cart_controller_restore_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/cart/presentation/cart_controller.dart test/cart_controller_restore_test.dart
git commit -m "feat(cart): add CartController.restore for undo-last-add

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Scan — thread `read_*` fields + `readLabel`

**Files:**
- Modify: `lib/features/scan/presentation/scan_controller.dart`
- Test: `test/scan_read_label_test.dart` (create)

**Interfaces:**
- Consumes: `RecognitionResult.readBrand/readName/readSize` (`String?`, already exist in `lib/features/scan/domain/recognition_result.dart`).
- Produces: `ScanOutcome` gains `final String? readBrand, readName, readSize;` and `String? get readLabel` (non-empty parts joined by `' · '`, or `null`). Used by Tasks 3–5.

- [ ] **Step 1: Write the failing test**

```dart
// test/scan_read_label_test.dart
import 'package:ai_shopkeeper/features/scan/domain/scan_decision.dart';
import 'package:ai_shopkeeper/features/scan/presentation/scan_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ScanOutcome outcome({String? b, String? n, String? s}) => ScanOutcome(
    action: ScanAction.noMatch,
    products: const [],
    readBrand: b,
    readName: n,
    readSize: s,
  );

  test('readLabel joins non-empty parts with a middot', () {
    expect(outcome(b: 'Pepsi', s: '1L').readLabel, 'Pepsi · 1L');
    expect(outcome(b: 'Pepsi', n: 'Cola', s: '500ml').readLabel, 'Pepsi · Cola · 500ml');
  });

  test('readLabel is null when nothing was read', () {
    expect(outcome().readLabel, isNull);
    expect(outcome(b: '   ', n: '').readLabel, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/scan_read_label_test.dart`
Expected: FAIL — `ScanOutcome` has no `readBrand`/`readLabel`.

- [ ] **Step 3: Add fields + getter, populate from recognition**

In `lib/features/scan/presentation/scan_controller.dart`, replace the `ScanOutcome` class:

```dart
class ScanOutcome {
  const ScanOutcome({
    required this.action,
    required this.products,
    this.readBrand,
    this.readName,
    this.readSize,
  });
  final ScanAction action;
  final List<Product> products;
  final String? readBrand;
  final String? readName;
  final String? readSize;

  /// What the model reported reading off the packaging, as one display line
  /// (e.g. "Pepsi · 1L"). Null when nothing legible was read.
  String? get readLabel {
    final parts = [readBrand, readName, readSize]
        .where((s) => s != null && s.trim().isNotEmpty)
        .map((s) => s!.trim())
        .toList();
    return parts.isEmpty ? null : parts.join(' · ');
  }
}
```

And in `captureAndRecognize`, populate the fields in the `success` branch:

```dart
        return ScanOutcome(
          action: decision.action,
          products: resolved,
          readBrand: recognition.readBrand,
          readName: recognition.readName,
          readSize: recognition.readSize,
        );
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/scan_read_label_test.dart`
Expected: PASS. Also run `flutter analyze lib test` — clean.

- [ ] **Step 5: Commit**

```bash
git add lib/features/scan/presentation/scan_controller.dart test/scan_read_label_test.dart
git commit -m "feat(scan): surface read_brand/name/size on ScanOutcome as readLabel

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Scan — `scan_read` string + "Read:" caption on add-to-cart sheet

**Files:**
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_bn.arb`
- Modify: `lib/features/cart/presentation/add_to_cart_sheet.dart`
- Test: `test/widgets/add_to_cart_sheet_test.dart` (extend)

**Interfaces:**
- Produces: `showAddToCartSheet(context, {required Product product, String? readLabel})` — optional `readLabel`; when non-null renders a caption `Read: <label>`. Manual callers pass nothing (unchanged).
- Consumes: `context.l10n.scan_read(String details)`.

- [ ] **Step 1: Write the failing test**

Add to `test/widgets/add_to_cart_sheet_test.dart` inside `main()`:

```dart
  testWidgets('shows the "Read:" caption when a readLabel is given', (tester) async {
    await tester.pumpWidget(_harness(_p(quantity: 12, price: 5)));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Pepsi · 1L'), findsOneWidget);
  });

  testWidgets('omits the caption when no readLabel is given', (tester) async {
    await tester.pumpWidget(_harnessNoLabel(_p(quantity: 12, price: 5)));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Read:'), findsNothing);
  });
```

Update the existing `_harness` builder to pass a label, and add a no-label variant. Replace the `showAddToCartSheet` call site in `_harness`:

```dart
          onPressed: () => showAddToCartSheet(context, product: product, readLabel: 'Pepsi · 1L'),
```

Add below `_harness`:

```dart
Widget _harnessNoLabel(Product product) => ProviderScope(
  overrides: [
    myShopProvider.overrideWith(
      (ref) =>
          const Shop(id: 's', ownerId: 'o', name: 'Test Shop', currency: 'USD'),
    ),
  ],
  child: MaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showAddToCartSheet(context, product: product),
          child: const Text('open'),
        ),
      ),
    ),
  ),
);
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/add_to_cart_sheet_test.dart`
Expected: FAIL — `showAddToCartSheet` has no `readLabel`; `scan_read` undefined.

- [ ] **Step 3: Add the l10n key, regenerate, add the caption**

In `lib/l10n/app_en.arb`, after the `"scan_addedToCart"` block add:

```json
  "scan_read": "Read: {details}",
  "@scan_read": { "placeholders": { "details": { "type": "String" } } },
```

In `lib/l10n/app_bn.arb`, add the matching key (keep placeholder name):

```json
  "scan_read": "পড়া হয়েছে: {details}",
```

Regenerate: `flutter gen-l10n`

In `lib/features/cart/presentation/add_to_cart_sheet.dart`:

Update the entry point:

```dart
Future<bool?> showAddToCartSheet(
  BuildContext context, {
  required Product product,
  String? readLabel,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (_) => _AddToCartSheet(product: product, readLabel: readLabel),
  );
}
```

Update the widget class + constructor:

```dart
class _AddToCartSheet extends ConsumerStatefulWidget {
  const _AddToCartSheet({required this.product, this.readLabel});

  final Product product;
  final String? readLabel;
```

In `build`, after the `subtitle` `Text(...)` block (the `if (subtitle.isNotEmpty) Text(...)`), and before `const SizedBox(height: 4)`, insert:

```dart
          if (widget.readLabel != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                l10n.scan_read(widget.readLabel!),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/add_to_cart_sheet_test.dart`
Expected: PASS (all cases, including the pre-existing ones).

- [ ] **Step 5: Commit**

```bash
git add lib/l10n/app_en.arb lib/l10n/app_bn.arb lib/l10n/app_localizations.dart lib/l10n/app_localizations_en.dart lib/l10n/app_localizations_bn.dart lib/features/cart/presentation/add_to_cart_sheet.dart test/widgets/add_to_cart_sheet_test.dart
git commit -m "feat(scan): show what the scanner read on the add-to-cart sheet

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Scan — read label on the picker + wire scan screen

**Files:**
- Modify: `lib/features/scan/presentation/product_picker_sheet.dart`
- Modify: `lib/features/scan/presentation/scan_screen.dart`
- Test: `test/widgets/product_picker_read_label_test.dart` (create)

**Interfaces:**
- Produces: `showProductPickerSheet(context, {required List<Product> products, required String title, String? readLabel})` — optional `readLabel` shown under the title.
- Consumes: `ScanOutcome.readLabel` (Task 2), `showAddToCartSheet(..., readLabel:)` (Task 3), `context.l10n.scan_read`.

- [ ] **Step 1: Write the failing test**

```dart
// test/widgets/product_picker_read_label_test.dart
import 'package:ai_shopkeeper/core/config/theme.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/scan/presentation/product_picker_sheet.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('picker shows the read label under the title', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showProductPickerSheet(
                context,
                products: const [Product(id: 'p1', shopId: 's', name: 'Pepsi 1L', quantity: 5)],
                title: 'Pick one',
                readLabel: 'Pepsi · 1L',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Pepsi · 1L'), findsWidgets);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/product_picker_read_label_test.dart`
Expected: FAIL — `showProductPickerSheet` has no `readLabel`.

- [ ] **Step 3: Add the optional label to the picker**

In `lib/features/scan/presentation/product_picker_sheet.dart`:

```dart
Future<Product?> showProductPickerSheet(
  BuildContext context, {
  required List<Product> products,
  required String title,
  String? readLabel,
}) {
  return showModalBottomSheet<Product>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (_) => _ProductPickerSheet(products: products, title: title, readLabel: readLabel),
  );
}
```

```dart
class _ProductPickerSheet extends StatefulWidget {
  const _ProductPickerSheet({required this.products, required this.title, this.readLabel});

  final List<Product> products;
  final String title;
  final String? readLabel;
```

In `build`, immediately after the title `Text(widget.title, ...)` widget, insert:

```dart
          if (widget.readLabel != null) ...[
            const SizedBox(height: 4),
            Text(
              context.l10n.scan_read(widget.readLabel!),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/product_picker_read_label_test.dart`
Expected: PASS.

- [ ] **Step 5: Wire the scan screen to pass labels through**

In `lib/features/scan/presentation/scan_screen.dart`:

Change `_confirmAndAdd` to accept and forward a label:

```dart
  Future<bool> _confirmAndAdd(Product product, {String? readLabel}) async {
    final added = await showAddToCartSheet(context, product: product, readLabel: readLabel);
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
```

In `_route`, pass the outcome's label:

```dart
      case ScanAction.autoSell:
        if (outcome.products.isEmpty) return _noMatch();
        return _confirmAndAdd(outcome.products.first, readLabel: outcome.readLabel);
      case ScanAction.chooseFromMatches:
        final picked = await showProductPickerSheet(
          context,
          products: outcome.products,
          title: context.l10n.scan_didYouMean,
          readLabel: outcome.readLabel,
        );
        if (picked == null) {
          if (mounted) context.pop();
          return false;
        }
        return _confirmAndAdd(picked, readLabel: outcome.readLabel);
```

Note: `_noMatch()` has no read label from a matched product path; leave it passing nothing (the picker there is a manual catalog pick). Keep `_noMatch`'s `_confirmAndAdd(picked)` call unchanged.

Run: `flutter analyze lib test` — clean. `flutter test` — green.

- [ ] **Step 6: Commit**

```bash
git add lib/features/scan/presentation/product_picker_sheet.dart lib/features/scan/presentation/scan_screen.dart test/widgets/product_picker_read_label_test.dart
git commit -m "feat(scan): show read label on the match picker and pass it through the scan flow

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Undo snackbar helper + wire scan add

**Files:**
- Create: `lib/features/cart/presentation/undo_add.dart`
- Modify: `lib/features/scan/presentation/scan_screen.dart`
- Test: `test/widgets/undo_add_test.dart` (create)

**Interfaces:**
- Consumes: `CartController.restore` (Task 1).
- Produces: `void showUndoableAddSnackBar(ScaffoldMessengerState messenger, WidgetRef ref, {required String message, required String undoLabel, required List<CartLine> snapshot})` — shows a snackbar whose Undo action restores `snapshot`. Used by scan (this task) and voice (Task 8).

- [ ] **Step 1: Write the failing test**

```dart
// test/widgets/undo_add_test.dart
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
    expect(capturedRef.read(cartControllerProvider).length, 1);

    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(capturedRef.read(cartControllerProvider), isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/undo_add_test.dart`
Expected: FAIL — `undo_add.dart` / `showUndoableAddSnackBar` do not exist.

- [ ] **Step 3: Create the helper**

```dart
// lib/features/cart/presentation/undo_add.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/cart_line.dart';
import 'cart_controller.dart';

/// Shows a confirmation snackbar with an Undo action that restores the cart to
/// [snapshot]. Shared by the scan and voice add flows so "undo last add"
/// behaves identically in both. Capture [snapshot] BEFORE mutating the cart.
void showUndoableAddSnackBar(
  ScaffoldMessengerState messenger,
  WidgetRef ref, {
  required String message,
  required String undoLabel,
  required List<CartLine> snapshot,
}) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: undoLabel,
          onPressed: () =>
              ref.read(cartControllerProvider.notifier).restore(snapshot),
        ),
      ),
    );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/undo_add_test.dart`
Expected: PASS.

- [ ] **Step 5: Wire the scan add to use it**

In `lib/features/scan/presentation/scan_screen.dart`:

Add imports:

```dart
import '../../cart/presentation/cart_controller.dart';
import '../../cart/presentation/undo_add.dart';
```

Replace `_confirmAndAdd` (from Task 4) with the snapshot + undo version:

```dart
  Future<bool> _confirmAndAdd(Product product, {String? readLabel}) async {
    final snapshot = ref.read(cartControllerProvider); // pre-add cart
    final added = await showAddToCartSheet(context, product: product, readLabel: readLabel);
    if (!mounted) return false;
    if (added == true) {
      showUndoableAddSnackBar(
        ScaffoldMessenger.of(context),
        ref,
        message: context.l10n.scan_addedToCart(product.name),
        undoLabel: context.l10n.common_undo,
        snapshot: snapshot,
      );
    }
    return true;
  }
```

Run: `flutter analyze lib test` — clean. `flutter test` — green.

- [ ] **Step 6: Commit**

```bash
git add lib/features/cart/presentation/undo_add.dart lib/features/scan/presentation/scan_screen.dart test/widgets/undo_add_test.dart
git commit -m "feat(scan): undo last add via snackbar (shared snapshot/restore helper)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: Voice repository — transcript re-parse path

**Files:**
- Modify: `lib/features/voice/data/voice_sale_repository.dart`
- Modify: `test/widgets/voice_review_sheet_test.dart` (fake), `test/voice_controller_test.dart` (fake)

**Interfaces:**
- Produces: `Future<Result<VoiceParseResult>> VoiceSaleRepository.parseTranscript({required String transcript, required List<Map<String, dynamic>> candidates})` — calls `parse-sale` with a `transcript` body (text path). Used by Task 7.
- Note: both existing fakes `implement VoiceSaleRepository`, so they MUST gain a `parseTranscript` stub or the suite won't compile.

- [ ] **Step 1: Add the repository method**

In `lib/features/voice/data/voice_sale_repository.dart`, add inside the class after `parse(...)`:

```dart
  /// Re-parses an edited transcript through the same `parse-sale` function,
  /// using its text path instead of audio. Lets the shopkeeper fix a mishear
  /// and get freshly matched line items without re-recording.
  Future<Result<VoiceParseResult>> parseTranscript({
    required String transcript,
    required List<Map<String, dynamic>> candidates,
  }) async {
    try {
      final res = await _client.functions
          .invoke(
            'parse-sale',
            body: {'transcript': transcript, 'candidates': candidates},
          )
          .timeout(const Duration(seconds: 30));
      final data = res.data;
      final map = data is String ? jsonDecode(data) : data;
      return Result.success(
        VoiceParseResult.fromJson(Map<String, dynamic>.from(map as Map)),
      );
    } catch (e) {
      return Result.failure(mapVoiceFailure(e));
    }
  }
```

- [ ] **Step 2: Update both fakes so the suite compiles**

In `test/widgets/voice_review_sheet_test.dart`, add a second result field and the method to `_FakeVoiceRepo`:

```dart
class _FakeVoiceRepo implements VoiceSaleRepository {
  _FakeVoiceRepo(this._result, {Result<VoiceParseResult>? transcriptResult})
      : _transcriptResult = transcriptResult ?? _result;
  final Result<VoiceParseResult> _result;
  final Result<VoiceParseResult> _transcriptResult;

  @override
  Future<Result<VoiceParseResult>> parse({
    required Uint8List audioBytes,
    required String audioMime,
    required List<Map<String, dynamic>> candidates,
  }) async => _result;

  @override
  Future<Result<VoiceParseResult>> parseTranscript({
    required String transcript,
    required List<Map<String, dynamic>> candidates,
  }) async => _transcriptResult;
}
```

In `test/voice_controller_test.dart`, find its `_FakeVoiceRepo` (or equivalently named repo fake) and add the same `parseTranscript` override. If that fake has no constructor param for a transcript result, add one mirroring the block above so Task 7's test can inject a distinct re-parse result. (Read the file first; match its existing field naming.)

- [ ] **Step 3: Run the full suite to verify it still compiles + passes**

Run: `flutter test`
Expected: PASS (no behavior change yet; this step only proves the interface addition didn't break the fakes).

- [ ] **Step 4: Commit**

```bash
git add lib/features/voice/data/voice_sale_repository.dart test/widgets/voice_review_sheet_test.dart test/voice_controller_test.dart
git commit -m "feat(voice): add parseTranscript text path to voice repository

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: Voice controller — `reparseFromText`

**Files:**
- Modify: `lib/features/voice/presentation/voice_controller.dart`
- Test: `test/voice_reparse_test.dart` (create)

**Interfaces:**
- Consumes: `VoiceSaleRepository.parseTranscript` (Task 6), `buildVoiceLines`, `buildCandidates`.
- Produces: `Future<void> VoiceController.reparseFromText(String transcript)` — trims input; no-op on empty; sets `thinking`, calls `parseTranscript`, rebuilds `heardText` + `lines`, lands on `reviewing` (or `error` with `noMatch` when empty). Used by Task 8.

- [ ] **Step 1: Write the failing test**

```dart
// test/voice_reparse_test.dart
import 'dart:typed_data';

import 'package:ai_shopkeeper/core/error/result.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/inventory/presentation/inventory_controller.dart';
import 'package:ai_shopkeeper/features/voice/data/audio_recorder.dart';
import 'package:ai_shopkeeper/features/voice/data/voice_sale_repository.dart';
import 'package:ai_shopkeeper/features/voice/domain/voice_parse_result.dart';
import 'package:ai_shopkeeper/features/voice/presentation/voice_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRecorder implements AudioRecorderPort {
  @override
  Future<bool> hasPermission() async => true;
  @override
  Future<void> start() async {}
  @override
  Future<({Uint8List bytes, String mime})?> stop() async =>
      (bytes: Uint8List.fromList(const [1]), mime: 'audio/m4a');
  @override
  Future<void> cancel() async {}
  @override
  Future<void> dispose() async {}
}

class _FakeRepo implements VoiceSaleRepository {
  _FakeRepo(this.audioResult, this.textResult);
  final Result<VoiceParseResult> audioResult;
  final Result<VoiceParseResult> textResult;
  @override
  Future<Result<VoiceParseResult>> parse({
    required Uint8List audioBytes,
    required String audioMime,
    required List<Map<String, dynamic>> candidates,
  }) async => audioResult;
  @override
  Future<Result<VoiceParseResult>> parseTranscript({
    required String transcript,
    required List<Map<String, dynamic>> candidates,
  }) async => textResult;
}

void main() {
  test('reparseFromText replaces lines and heardText from the edited text', () async {
    final audio = VoiceParseResult(
      heardText: 'pepci',
      items: [VoiceItem(heard: 'pepci', quantity: 1, quantityAssumed: true, matches: const [])],
    );
    final text = VoiceParseResult(
      heardText: '2 pepsi',
      items: [
        VoiceItem(
          heard: 'pepsi', quantity: 2, quantityAssumed: false,
          matches: const [VoiceMatch(productId: 'p1', confidence: 0.9)],
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        audioRecorderProvider.overrideWithValue(_FakeRecorder()),
        voiceSaleRepositoryProvider.overrideWithValue(_FakeRepo(Result.success(audio), Result.success(text))),
        productsStreamProvider.overrideWith(
          (ref) => Stream.value(const [Product(id: 'p1', shopId: 's', name: 'Pepsi 1L', quantity: 9)]),
        ),
      ],
    );
    final n = container.read(voiceControllerProvider.notifier);
    await n.startListening();
    await n.stopAndParse(); // now reviewing with the (mis-heard) audio result

    await n.reparseFromText('2 pepsi');

    final state = container.read(voiceControllerProvider);
    expect(state.phase, VoicePhase.reviewing);
    expect(state.heardText, '2 pepsi');
    expect(state.lines.length, 1);
    expect(state.lines.first.quantity, 2);
  });

  test('reparseFromText ignores empty input', () async {
    final container = ProviderContainer(
      overrides: [
        audioRecorderProvider.overrideWithValue(_FakeRecorder()),
        voiceSaleRepositoryProvider.overrideWithValue(
          _FakeRepo(Result.success(const VoiceParseResult(items: [])), Result.success(const VoiceParseResult(items: []))),
        ),
        productsStreamProvider.overrideWith((ref) => Stream.value(const <Product>[])),
      ],
    );
    final n = container.read(voiceControllerProvider.notifier);
    await n.reparseFromText('   ');
    expect(container.read(voiceControllerProvider).phase, VoicePhase.idle);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/voice_reparse_test.dart`
Expected: FAIL — `reparseFromText` not defined.

- [ ] **Step 3: Implement the method**

In `lib/features/voice/presentation/voice_controller.dart`, add after `stopAndParse`:

```dart
  /// Re-runs parsing on a shopkeeper-edited [transcript] (the text path of
  /// `parse-sale`), rebuilding the reviewable lines so a single misheard word
  /// can be fixed without re-recording. Empty input is a no-op.
  Future<void> reparseFromText(String transcript) async {
    final text = transcript.trim();
    if (text.isEmpty) return;
    final session = ++_session; // supersede any in-flight recording/parse
    state = state.copyWith(phase: VoicePhase.thinking);

    final products = ref.read(productsStreamProvider).value ?? const [];
    final result = await ref
        .read(voiceSaleRepositoryProvider)
        .parseTranscript(
          transcript: text,
          candidates: buildCandidates(products, includeUnit: true),
        );
    if (_session != session) return;

    result.when(
      success: (parsed) {
        final lines = buildVoiceLines(parsed);
        state = state.copyWith(
          phase: lines.isEmpty ? VoicePhase.error : VoicePhase.reviewing,
          heardText: parsed.heardText ?? text,
          lines: lines,
          errorMessage: lines.isEmpty ? 'noMatch' : null,
        );
      },
      failure: (f) => state = state.copyWith(
        phase: VoicePhase.error,
        errorMessage: f.message,
      ),
    );
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/voice_reparse_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/voice/presentation/voice_controller.dart test/voice_reparse_test.dart
git commit -m "feat(voice): reparseFromText re-runs the AI on an edited transcript

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 8: Voice review sheet — editable transcript + undo

**Files:**
- Modify: `lib/features/voice/presentation/voice_review_sheet.dart`
- Test: `test/widgets/voice_edit_transcript_test.dart` (create)

**Interfaces:**
- Consumes: `VoiceController.reparseFromText` (Task 7), `showUndoableAddSnackBar` (Task 5), `CartController` snapshot, `context.l10n.common_undo`, `context.l10n.voice_addToCart`.

- [ ] **Step 1: Write the failing test**

```dart
// test/widgets/voice_edit_transcript_test.dart
import 'dart:typed_data';

import 'package:ai_shopkeeper/core/config/theme.dart';
import 'package:ai_shopkeeper/core/error/result.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/inventory/presentation/inventory_controller.dart';
import 'package:ai_shopkeeper/features/voice/data/audio_recorder.dart';
import 'package:ai_shopkeeper/features/voice/data/voice_sale_repository.dart';
import 'package:ai_shopkeeper/features/voice/domain/voice_parse_result.dart';
import 'package:ai_shopkeeper/features/voice/presentation/voice_controller.dart';
import 'package:ai_shopkeeper/features/voice/presentation/voice_review_sheet.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:ai_shopkeeper/shared/providers/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

class _FakeRecorder implements AudioRecorderPort {
  @override
  Future<bool> hasPermission() async => true;
  @override
  Future<void> start() async {}
  @override
  Future<({Uint8List bytes, String mime})?> stop() async =>
      (bytes: Uint8List.fromList(const [1]), mime: 'audio/m4a');
  @override
  Future<void> cancel() async {}
  @override
  Future<void> dispose() async {}
}

class _FakeRepo implements VoiceSaleRepository {
  _FakeRepo(this.audio, this.text);
  final Result<VoiceParseResult> audio;
  final Result<VoiceParseResult> text;
  @override
  Future<Result<VoiceParseResult>> parse({
    required Uint8List audioBytes,
    required String audioMime,
    required List<Map<String, dynamic>> candidates,
  }) async => audio;
  @override
  Future<Result<VoiceParseResult>> parseTranscript({
    required String transcript,
    required List<Map<String, dynamic>> candidates,
  }) async => text;
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('editing the heard text re-parses and updates the lines', (tester) async {
    final audio = VoiceParseResult(
      heardText: 'pepci',
      items: [VoiceItem(heard: 'pepci', quantity: 1, quantityAssumed: true, matches: const [VoiceMatch(productId: 'p1', confidence: 0.4)])],
    );
    final text = VoiceParseResult(
      heardText: '2 pepsi',
      items: [VoiceItem(heard: 'pepsi', quantity: 2, quantityAssumed: false, matches: const [VoiceMatch(productId: 'p1', confidence: 0.95)])],
    );
    final container = ProviderContainer(
      overrides: [
        audioRecorderProvider.overrideWithValue(_FakeRecorder()),
        voiceSaleRepositoryProvider.overrideWithValue(_FakeRepo(Result.success(audio), Result.success(text))),
        productsStreamProvider.overrideWith(
          (ref) => Stream.value(const [Product(id: 'p1', shopId: 's', name: 'Pepsi 1L', quantity: 9)]),
        ),
      ],
    );
    final n = container.read(voiceControllerProvider.notifier);
    await n.startListening();
    await n.stopAndParse();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('en'),
          supportedLocales: supportedAppLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const Scaffold(body: VoiceReviewSheet()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap the heard line to open the editor.
    await tester.tap(find.textContaining('pepci'));
    await tester.pumpAndSettle();

    // Replace the text and confirm.
    await tester.enterText(find.byType(TextField).last, '2 pepsi');
    await tester.tap(find.text('Re-check'));
    await tester.pumpAndSettle();

    // Lines rebuilt from the re-parse.
    expect(find.textContaining('2 pepsi'), findsWidgets);
    expect(container.read(voiceControllerProvider).lines.first.quantity, 2);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/voice_edit_transcript_test.dart`
Expected: FAIL — the heard line isn't tappable / no "Re-check" editor.

- [ ] **Step 3: Make the heard line tappable + add the editor**

In `lib/features/voice/presentation/voice_review_sheet.dart`, add imports:

```dart
import '../../cart/presentation/undo_add.dart';
```

Replace the heard `Text(...)` block (the `Text('${l10n.voice_heard} "${state.heardText ?? ''}"', ...)`) with an `InkWell` that opens the editor:

```dart
          InkWell(
            onTap: () => _editTranscript(context, ref, state.heardText ?? ''),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    '${l10n.voice_heard} "${state.heardText ?? ''}"',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.edit, size: 14, color: theme.colorScheme.onSurfaceVariant),
              ],
            ),
          ),
```

Add this method to `VoiceReviewSheet` (it's a `ConsumerWidget`, so take `ref`):

```dart
  /// Opens a small editor prefilled with [current] transcript. On submit,
  /// re-runs the AI on the corrected text via the controller. Empty submits
  /// are ignored by the controller.
  Future<void> _editTranscript(BuildContext context, WidgetRef ref, String current) async {
    final controller = TextEditingController(text: current);
    final edited = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.voice_heard),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onSubmitted: (v) => Navigator.of(dialogContext).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(dialogContext.l10n.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Re-check'),
          ),
        ],
      ),
    );
    if (edited != null) {
      await ref.read(voiceControllerProvider.notifier).reparseFromText(edited);
    }
  }
```

> Note: "Re-check" is a UI action label. If you want it localized, add a `voice_recheck` key to both ARBs and use `context.l10n.voice_recheck`; the test's `find.text('Re-check')` must then match the English value. For this batch a literal is acceptable since it is an in-dialog control, but prefer the l10n key if touching the ARBs anyway.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/voice_edit_transcript_test.dart`
Expected: PASS.

- [ ] **Step 5: Add voice undo on add (snapshot before commit)**

Still in `voice_review_sheet.dart`, update `_addToCart` to snapshot the cart before mutating it and show the shared undo snackbar. Capture the messenger before the `await`/navigation:

```dart
  Future<void> _addToCart(BuildContext context, WidgetRef ref) async {
    final state = ref.read(voiceControllerProvider);
    final products =
        ref.read(productsStreamProvider).value ?? const <Product>[];
    final byId = {for (final p in products) p.id: p};

    final resolved = <Product>[];
    for (final line in state.lines) {
      final product = byId[line.chosenProductId];
      if (product == null) return;
      resolved.add(product);
    }

    final cart = ref.read(cartControllerProvider.notifier);
    final snapshot = ref.read(cartControllerProvider); // pre-add cart
    final messenger = ScaffoldMessenger.of(context);
    final undoLabel = context.l10n.common_undo;
    final addedMsg = context.l10n.voice_addToCart;
    for (var i = 0; i < state.lines.length; i++) {
      cart.addOrIncrement(resolved[i], state.lines[i].quantity);
    }

    ref.read(voiceControllerProvider.notifier).reset();
    if (!context.mounted) return;
    Navigator.of(context).pop();
    context.push('/cart');
    showUndoableAddSnackBar(
      messenger,
      ref,
      message: addedMsg,
      undoLabel: undoLabel,
      snapshot: snapshot,
    );
  }
```

Run: `flutter analyze lib test` — clean. `flutter test` — green (the existing voice tests don't trigger `_addToCart`, so navigation isn't exercised there; the undo helper is covered by Task 5).

- [ ] **Step 6: Commit**

```bash
git add lib/features/voice/presentation/voice_review_sheet.dart test/widgets/voice_edit_transcript_test.dart
git commit -m "feat(voice): edit misheard transcript to re-run AI; undo last voice add

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Final verification

- [ ] `flutter analyze lib test` — no issues.
- [ ] `flutter test` — full suite green.
- [ ] Manual/on-device (folds into the pending S22 verification):
  - Scan a product → "Read: …" shows on the sheet and picker; Undo snackbar reverses the add.
  - Voice a sale → tap "I heard …" → fix a word → Re-check rebuilds items; Undo reverses the voice add.

## Self-review notes

- **Spec coverage:** Feature 1 → Tasks 2,3,4. Feature 2 → Tasks 6,7,8. Feature 3 → Tasks 1,5,8. Localization keys: `scan_read` added (Task 3); `common_undo` already existed (used in Tasks 5,8).
- **Type consistency:** `restore(List<CartLine>)`, `readLabel` getter, `showUndoableAddSnackBar(ScaffoldMessengerState, WidgetRef, {message, undoLabel, snapshot})`, `parseTranscript({transcript, candidates})`, `reparseFromText(String)` — names used identically across producing and consuming tasks.
- **Fake breakage:** adding `parseTranscript` to `VoiceSaleRepository` forces the two `implements` fakes to add the method (handled explicitly in Task 6).
- **Untestable glue:** scan snackbar wiring and voice `_addToCart` navigation are covered by `analyze` + on-device; the reversible logic (`restore`, `showUndoableAddSnackBar`, `reparseFromText`, `readLabel`) is unit/widget tested.
