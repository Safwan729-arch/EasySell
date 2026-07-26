# Scan Quantity Confirmation Sheet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After a scan recognizes a product, open the existing add-to-cart confirmation sheet (with a new typeable quantity field) so the shopkeeper sets the amount before it enters the cart — instead of the current auto-add-one behavior.

**Architecture:** Reuse `showAddToCartSheet` (already used by Product Detail) in the scan flow, and enhance that shared sheet once with a directly-typeable quantity `TextField` alongside its existing −/＋ stepper. A small pure `clampCartQuantity` helper carries the typing/clamp math so it's unit-testable. Frontend-only; no backend changes.

**Tech Stack:** Flutter, Riverpod, Material 3; `flutter_test` for unit + widget tests.

**Testing strategy (honest split):** the new *logic* is the clamp helper (Task 1) and the sheet's typing behavior (Task 2) — both get real tests. The scan-screen wiring (Task 3) is a low-risk call-site swap; a full end-to-end scan test would require faking the camera, go_router, and the rescan loop (brittle, high cost for a 3-line change), so Task 3 is verified by `flutter analyze` + the passing suite + the user's on-device scan.

---

## File Structure

- **Modify:** `lib/features/cart/domain/cart_math.dart` — add pure `clampCartQuantity(...)`.
- **Modify:** `lib/features/cart/presentation/add_to_cart_sheet.dart` — add the typeable quantity `TextField` + controller wiring; use `clampCartQuantity`.
- **Modify:** `lib/features/scan/presentation/scan_screen.dart` — replace `_addToCart` with `_confirmAndAdd` (calls `showAddToCartSheet`); update three call sites; drop now-unused imports.
- **Modify:** `test/cart_math_test.dart` — add a `clampCartQuantity` group.
- **Create:** `test/widgets/add_to_cart_sheet_test.dart` — widget tests for the typeable sheet.

The `showAddToCartSheet` `Future<bool?>` contract is unchanged, so the Product Detail caller needs no edit.

---

## Task 1: `clampCartQuantity` helper (TDD)

**Files:**
- Modify: `lib/features/cart/domain/cart_math.dart`
- Test: `test/cart_math_test.dart`

- [ ] **Step 1: Write the failing tests**

Append this group inside the existing `main()` in `test/cart_math_test.dart` (the file already imports `cart_math.dart`):

```dart
  group('clampCartQuantity', () {
    test('passes an in-range value through', () {
      expect(
        clampCartQuantity(value: 3, remaining: 10, allowsDecimal: false),
        3,
      );
    });
    test('clamps a value above remaining down to remaining', () {
      expect(
        clampCartQuantity(value: 20, remaining: 12, allowsDecimal: false),
        12,
      );
    });
    test('clamps negatives to zero', () {
      expect(
        clampCartQuantity(value: -1, remaining: 10, allowsDecimal: true),
        0,
      );
    });
    test('floors decimals for piece products', () {
      expect(
        clampCartQuantity(value: 2.7, remaining: 10, allowsDecimal: false),
        2,
      );
    });
    test('keeps decimals for weight/volume products', () {
      expect(
        clampCartQuantity(value: 2.5, remaining: 10, allowsDecimal: true),
        2.5,
      );
    });
    test('remaining of zero yields zero', () {
      expect(
        clampCartQuantity(value: 5, remaining: 0, allowsDecimal: false),
        0,
      );
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/cart_math_test.dart`
Expected: FAIL — `clampCartQuantity` is undefined.

- [ ] **Step 3: Implement the helper**

Append to `lib/features/cart/domain/cart_math.dart`:

```dart
/// Clamps a typed or stepped cart quantity to a valid range: never below 0,
/// never above [remaining] stock, and floored to a whole number when the
/// product is sold by the piece ([allowsDecimal] false). Used by the
/// add-to-cart sheet's quantity field and stepper.
double clampCartQuantity({
  required double value,
  required double remaining,
  required bool allowsDecimal,
}) {
  var v = allowsDecimal ? value : value.floorToDouble();
  if (v < 0) v = 0;
  if (v > remaining) v = remaining;
  return v;
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/cart_math_test.dart`
Expected: PASS (all existing tests + the new group).

- [ ] **Step 5: Commit**

```bash
git add lib/features/cart/domain/cart_math.dart test/cart_math_test.dart
git commit -m "feat(cart): add clampCartQuantity helper for quantity input"
```

---

## Task 2: Typeable quantity field in the shared sheet

**Files:**
- Modify: `lib/features/cart/presentation/add_to_cart_sheet.dart`
- Test: `test/widgets/add_to_cart_sheet_test.dart`

- [ ] **Step 1: Write the failing widget tests**

Create `test/widgets/add_to_cart_sheet_test.dart`:

```dart
import 'package:ai_shopkeeper/core/config/theme.dart';
import 'package:ai_shopkeeper/features/auth/data/auth_repository.dart';
import 'package:ai_shopkeeper/features/auth/domain/shop.dart';
import 'package:ai_shopkeeper/features/cart/presentation/add_to_cart_sheet.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

Product _p({
  double quantity = 12,
  double price = 5,
  UnitType unitType = UnitType.piece,
  ProductUnit unit = ProductUnit.pcs,
}) => Product(
  id: 'a',
  shopId: 's',
  name: 'Pepsi 1L',
  brand: 'Pepsi',
  variant: '1L',
  unitType: unitType,
  unit: unit,
  quantity: quantity,
  sellingPrice: price,
);

Widget _harness(Product product) => ProviderScope(
  overrides: [
    myShopProvider.overrideWith(
      (ref) =>
          const Shop(id: 's', ownerId: 'o', name: 'Test Shop', currency: 'USD'),
    ),
  ],
  child: MaterialApp(
    theme: AppTheme.light,
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

Future<void> _openSheet(WidgetTester tester, Product product) async {
  await tester.pumpWidget(_harness(product));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('typing above stock clamps the field and subtotal to remaining', (
    tester,
  ) async {
    await _openSheet(tester, _p(quantity: 12, price: 5));

    await tester.enterText(find.byType(TextField), '20');
    await tester.pumpAndSettle();

    // Field snaps to the 12-in-stock cap; subtotal reflects 12 * 5.
    expect(find.widgetWithText(TextField, '12'), findsOneWidget);
    expect(find.text('\$60.00'), findsOneWidget);
  });

  testWidgets('a typed decimal is floored for a piece product', (tester) async {
    await _openSheet(tester, _p(quantity: 12, price: 5));

    await tester.enterText(find.byType(TextField), '2.7');
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, '2'), findsOneWidget);
    expect(find.text('\$10.00'), findsOneWidget);
  });

  testWidgets('a weight product keeps a typed decimal', (tester) async {
    await _openSheet(
      tester,
      _p(quantity: 10, price: 40, unitType: UnitType.weight, unit: ProductUnit.kg),
    );

    await tester.enterText(find.byType(TextField), '2.5');
    await tester.pumpAndSettle();

    expect(find.text('\$100.00'), findsOneWidget);
  });

  testWidgets('clearing the quantity disables Add to cart', (tester) async {
    await _openSheet(tester, _p(quantity: 12, price: 5));

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();

    final addBtn = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Add to cart'),
    );
    expect(addBtn.onPressed, isNull);
  });

  testWidgets('the + stepper stays in sync with the field', (tester) async {
    await _openSheet(tester, _p(quantity: 12, price: 5));

    // Initial quantity is one step (1 pcs); tapping + makes it 2.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, '2'), findsOneWidget);
    expect(find.text('\$10.00'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/widgets/add_to_cart_sheet_test.dart`
Expected: FAIL — the sheet has no `TextField` yet (it renders quantity as read-only `Text`).

- [ ] **Step 3: Add the typeable field to `_AddToCartSheet`**

In `lib/features/cart/presentation/add_to_cart_sheet.dart`:

(a) Add the `clampCartQuantity` import path — it is already exported from `cart_math.dart`, which the file already imports (`import '../domain/cart_math.dart';`). No new import needed.

(b) Replace the state fields + `initState` + add `dispose`, `_setQty`, `_onFieldChanged`. Replace this block:

```dart
class _AddToCartSheetState extends ConsumerState<_AddToCartSheet> {
  late double _qty;

  double get _step => stepForUnit(widget.product.unit);

  @override
  void initState() {
    super.initState();
    final remaining = ref
        .read(cartControllerProvider.notifier)
        .remainingStockFor(widget.product);
    _qty = remaining <= 0 ? 0 : _step.clamp(0, remaining).toDouble();
  }

  void _add() {
```

with:

```dart
class _AddToCartSheetState extends ConsumerState<_AddToCartSheet> {
  late double _qty;
  late final TextEditingController _qtyController;

  double get _step => stepForUnit(widget.product.unit);
  bool get _allowsDecimal => widget.product.unitType.allowsDecimal;

  @override
  void initState() {
    super.initState();
    final remaining = ref
        .read(cartControllerProvider.notifier)
        .remainingStockFor(widget.product);
    _qty = remaining <= 0 ? 0 : _step.clamp(0, remaining).toDouble();
    _qtyController = TextEditingController(text: Qty.format(_qty));
  }

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  /// Sets the quantity from a stepper button and syncs the text field to match.
  void _setQty(double v) {
    setState(() => _qty = v);
    final text = Qty.format(v);
    _qtyController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  /// Handles direct typing: parse, clamp to stock (and to whole for pieces).
  /// Only snaps the field text back when the typed value was out of range, so a
  /// mid-entry decimal like "2." is not clobbered.
  void _onFieldChanged(String raw, double remaining) {
    final parsed = double.tryParse(raw.trim());
    final clamped = clampCartQuantity(
      value: parsed ?? 0,
      remaining: remaining,
      allowsDecimal: _allowsDecimal,
    );
    setState(() => _qty = clamped);
    if (parsed != null && parsed != clamped) {
      final text = Qty.format(clamped);
      _qtyController.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  void _add() {
```

(c) In `build`, replace the −/quantity/＋ inner `Row` (currently the `Row(children: [ IconButton.filledTonal(... remove ...), SizedBox(width: 88, child: Text(...)), IconButton.filledTonal(... add ...) ])`) with:

```dart
              Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: _qty <= _step
                        ? null
                        : () {
                            AppHaptics.tap();
                            _setQty(_qty - _step);
                          },
                    icon: const Icon(Icons.remove),
                  ),
                  SizedBox(
                    width: 96,
                    child: TextField(
                      controller: _qtyController,
                      enabled: !outOfStock,
                      onChanged: (v) => _onFieldChanged(v, maxQty),
                      keyboardType: TextInputType.numberWithOptions(
                        decimal: _allowsDecimal,
                      ),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge,
                      decoration: InputDecoration(
                        isDense: true,
                        suffixText: widget.product.unitLabel,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: (_qty + _step > maxQty + 1e-9)
                        ? null
                        : () {
                            AppHaptics.tap();
                            _setQty(_qty + _step);
                          },
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
```

Everything else in `build` (identity, stock hint, `maxQty`/`outOfStock`/`total` locals, subtotal row, Cancel/Add buttons) stays exactly as-is. `maxQty` is already defined earlier in `build` as `ref.read(cartControllerProvider.notifier).remainingStockFor(product)`.

- [ ] **Step 4: Run the widget tests to verify they pass**

Run: `flutter test test/widgets/add_to_cart_sheet_test.dart`
Expected: PASS (all five tests).

- [ ] **Step 5: Format the two touched files (never repo-wide)**

Run: `dart format lib/features/cart/presentation/add_to_cart_sheet.dart test/widgets/add_to_cart_sheet_test.dart`

- [ ] **Step 6: Commit**

```bash
git add lib/features/cart/presentation/add_to_cart_sheet.dart test/widgets/add_to_cart_sheet_test.dart
git commit -m "feat(cart): typeable quantity field in add-to-cart sheet"
```

---

## Task 3: Wire the scan flow to the confirmation sheet

**Files:**
- Modify: `lib/features/scan/presentation/scan_screen.dart`

- [ ] **Step 1: Swap the imports**

In `lib/features/scan/presentation/scan_screen.dart`, remove these three imports (they become unused once the direct add is gone):

```dart
import '../../../core/config/haptics.dart';
import '../../cart/domain/cart_math.dart';
import '../../cart/presentation/cart_controller.dart';
```

and add:

```dart
import '../../cart/presentation/add_to_cart_sheet.dart';
```

- [ ] **Step 2: Replace `_addToCart` with `_confirmAndAdd`**

Replace the entire `_addToCart` method:

```dart
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
```

with:

```dart
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
        ..showSnackBar(SnackBar(content: Text('Added ${product.name} to cart')));
    }
    return true;
  }
```

- [ ] **Step 3: Update the three `_route` call sites**

In `_route`, change the `autoSell` branch `return _addToCart(outcome.products.first);` to `return _confirmAndAdd(outcome.products.first);`, and the `chooseFromMatches` branch `return _addToCart(picked);` to `return _confirmAndAdd(picked);`. In `_noMatch`, change `return _addToCart(picked);` to `return _confirmAndAdd(picked);`.

- [ ] **Step 4: Analyze — no errors, no unused imports**

Run: `flutter analyze lib/features/scan/presentation/scan_screen.dart`
Expected: No issues (in particular, no "unused import" for the removed imports and no undefined `_addToCart`/`stepForUnit`/`cartControllerProvider`/`AppHaptics` references).

- [ ] **Step 5: Run the full suite**

Run: `flutter test`
Expected: PASS (the scan screen still compiles and all existing + new tests pass). Note: `history_sale_tap_test.dart` is a known pre-existing failure unrelated to this change — if it is the only red test and it was already failing on `main`, it does not block this task.

- [ ] **Step 6: Format the touched file and commit**

Run: `dart format lib/features/scan/presentation/scan_screen.dart`

```bash
git add lib/features/scan/presentation/scan_screen.dart
git commit -m "feat(scan): confirm quantity via add-to-cart sheet before staging"
```

---

## Self-Review

**Spec coverage:**
- §1/§2 goal — scan opens the confirmation sheet before adding → Task 3. ✅
- §3 typeable field on the shared sheet (controller sync, keyboard type, clamp, disable-on-zero) → Task 2 Step 3 + tests Step 1. ✅
- §4 `_confirmAndAdd` wiring + call sites + removed out-of-stock branch + no duplicated haptic → Task 3. ✅
- §5 files: `clampCartQuantity` in cart_math (Task 1), sheet edit (Task 2), scan_screen edit (Task 3). ✅
- §6 testing: clamp unit tests (Task 1), sheet widget tests (Task 2), scan wiring via analyze+suite+on-device per the stated strategy. ✅
- §7 out of scope — Product Detail inherits the field via the unchanged `Future<bool?>` contract; no checkout/edge/gemini changes. ✅

**Placeholder scan:** No TBD/TODO; all code steps show full code.

**Type consistency:** `clampCartQuantity({value, remaining, allowsDecimal}) → double` is defined in Task 1 and called with the same names in Task 2 `_onFieldChanged`. `_setQty(double)`, `_onFieldChanged(String, double)`, `_confirmAndAdd(Product) → Future<bool>` are consistent across their definition and call sites. `showAddToCartSheet(context, product:) → Future<bool?>` matches the existing signature and the `added == true` check. `maxQty` and `outOfStock` locals referenced in Task 2 Step 3(c) already exist in `build`.
