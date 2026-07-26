# Scan Quantity Confirmation Sheet

**Date:** 2026-07-27
**Feature owner:** Member A (Full Stack)
**Scope:** Flutter scan flow (`lib/features/scan/`, `lib/features/cart/` reuse). No backend/Edge Function changes.
**Branch:** `feat/scan-quantity-sheet` (off `main`; independent of the Gemini scan migration).

---

## 1. Goal

After a scan recognizes a product, show a **quantity-confirmation sheet** where the
shopkeeper sets the amount **before** it is added to the cart. Today the scan flow
**auto-adds one unit-step** to the cart and immediately reopens the camera; quantity
can only be corrected later on the Cart screen. This feature inserts a deliberate
"set the amount, then Add" gate — matching the project rule "never auto-commit AI
output; confirm first" — while preserving fast back-to-back scanning ("Add & scan
next" reopens the camera).

This is **Option C** from brainstorming: confirm on every scan, but the sheet is the
default landing after recognition, with a prominent quantity stepper and an "Add &
scan next" primary action.

## 2. Current behavior (what changes)

In `lib/features/scan/presentation/scan_screen.dart`, `_route()` handles three
recognition outcomes and each ends by calling `_addToCart(product)`, which
**immediately** does `cart.addOrIncrement(product, stepForUnit(product.unit))`,
shows an "Added …" snackbar, and returns `true` (keep scanning).

The change: `_addToCart` is replaced by `_confirmAndAdd(product)`, which opens the
new quantity sheet first and only adds the **chosen** quantity. All three paths
(`autoSell`, `chooseFromMatches` → after the "Did you mean?" picker, `noMatch` →
after the manual picker) funnel through this single gate.

## 3. The quantity sheet

New modal bottom sheet: `showScanQuantitySheet(context, {product, remainingStock})`
→ `Future<double?>` returning the chosen quantity, or `null` if dismissed.

**Contents:**
- **Product identity:** `product.name` (bold title); subtitle = `brand · variant`
  joined (omit empties), same style as `product_picker_sheet.dart`.
- **Quantity control:** a row of `[−]  <number field>  [+]` with the unit label
  (`product.unit.label`) beside it.
  - `−`/`+` step by `stepForUnit(product.unit)` (1 pcs, 0.5 kg, 50 g, 0.5 litre,
    50 ml).
  - The number field is directly editable (numeric keyboard;
    `keyboardType: decimal` only when `product.unitType.allowsDecimal`, else
    whole-number). Pieces reject decimals; weight/volume accept them.
- **Stock hint:** `"{remainingStock} {unit} in stock"` (using the app's number
  formatting, trailing zeros trimmed). Quantity is **capped at `remainingStock`** —
  `+` and typed values never exceed it.
- **Live subtotal:** `product.sellingPrice * quantity`, formatted with the app's
  existing money formatter, updating as the quantity changes.
- **Actions:**
  - **"Add & scan next"** (primary, filled) → pops the sheet returning the chosen
    quantity. Disabled when quantity ≤ 0.
  - **"Cancel"** (text) / scrim dismiss → pops returning `null`.

**Initial quantity:** `min(stepForUnit(product.unit), remainingStock)` so a product
with less than one full step left still opens at a valid amount.

## 4. Flow / behavior in `scan_screen.dart`

`_confirmAndAdd(Product product) → Future<bool>` (returns whether to keep scanning):

1. Compute `remaining = cart.remainingStockFor(product)`.
2. If `remaining <= 0`: keep the **existing** out-of-stock / already-staged snackbar
   (out of stock vs fully-staged message), do **not** open the sheet, return `true`.
3. Else `final qty = await showScanQuantitySheet(context, product: product,
   remainingStock: remaining);`
   - If `qty == null` (dismissed): add nothing, return `true` (reopen camera — a
     cancel skips this item but keeps the scan session going; the AppBar back arrow
     still exits to the cart, unchanged).
   - Else: `cart.addOrIncrement(product, qty)`, fire `AppHaptics.success()`, show
     `"Added {qty} {unit} {name} to cart"` snackbar, return `true`.

`addOrIncrementLine` already clamps the merged quantity to stock, so a race where
stock changed between compute and add can never oversell.

**Decision — cancel keeps scanning:** consistent with Option C's speed goal; the
back arrow is the single, explicit "I'm done" exit. (The product-picker dismissal on
the `chooseFromMatches`/`noMatch` paths keeps its current pop-to-exit behavior; only
the *quantity* sheet's dismissal reopens the camera.)

## 5. Files

- **Create:** `lib/features/scan/presentation/scan_quantity_sheet.dart` — the sheet
  widget + `showScanQuantitySheet(...)` helper. Self-contained; depends on
  `Product`, `stepForUnit`, and the money/number formatters.
- **Create:** `lib/features/scan/domain/scan_quantity.dart` (small pure helper) —
  `clampScanQuantity({required double value, required double step,
  required double remaining, required bool allowsDecimal})` returning a validated
  quantity (≥ 0, ≤ remaining, snapped/whole for pieces). Extracted so the stepping
  and clamping math is unit-testable without pumping a widget.
- **Modify:** `lib/features/scan/presentation/scan_screen.dart` — replace
  `_addToCart` with `_confirmAndAdd`; update the three `_route` call sites.

No changes to `cart_math.dart`, `cart_controller.dart`, or any Edge Function.

## 6. Testing

- **Unit** (`test/features/scan/scan_quantity_test.dart`): `clampScanQuantity`
  covers — default at one step; `+` capping at remaining; `−` not going below 0;
  pieces rejecting decimals (2.4 pcs → 2); weight allowing 2.5 kg; remaining < step
  clamps the initial/step-up to remaining.
- **Widget** (`test/features/scan/scan_quantity_sheet_test.dart`): pumping the sheet —
  `+`/`−` update the displayed quantity and subtotal; typing a number updates the
  subtotal; "Add & scan next" is disabled at 0 and returns the chosen quantity on
  tap; Cancel returns null; a `remainingStock` of 3 blocks stepping to 4.
- **Scan-flow** (extend existing scan-screen test if present, else a focused new
  test): a recognized single match opens the quantity sheet (not an immediate add),
  and only the chosen quantity lands in the cart.

## 7. Out of scope

- No change to recognition, the Edge Function, or the Gemini migration.
- No change to the Cart screen's own line stepper or checkout.
- No multi-quantity-per-scan or barcode features.

## 8. Rollback

Feature is additive and branch-isolated. Reverting the branch's commits restores the
auto-add-one behavior; no data or schema implications.
