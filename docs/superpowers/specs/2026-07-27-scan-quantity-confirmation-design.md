# Scan Quantity Confirmation Sheet

**Date:** 2026-07-27
**Feature owner:** Member A (Full Stack)
**Scope:** Flutter scan flow + the shared add-to-cart sheet (`lib/features/scan/`,
`lib/features/cart/`). No backend/Edge Function changes.
**Branch:** `feat/scan-quantity-sheet` (off `main`; independent of the Gemini scan migration).

---

## 1. Goal

After a scan recognizes a product, show a **quantity-confirmation sheet** where the
shopkeeper sets the amount **before** it is added to the cart. Today the scan flow
**auto-adds one unit-step** and immediately reopens the camera; quantity can only be
corrected later on the Cart screen. This feature inserts a deliberate "set the
amount, then Add" gate — matching the project rule "never auto-commit AI output;
confirm first" — while preserving fast back-to-back scanning (adding reopens the
camera).

**Approach (revised after codebase exploration):** the app already has
`showAddToCartSheet` (`lib/features/cart/presentation/add_to_cart_sheet.dart`),
used by the Product Detail screen. It already renders product identity, an
"available to add" stock hint, a unit-aware −/＋ quantity stepper clamped to stock,
a live subtotal in the shop's currency, and Cancel / Add buttons — exactly the sheet
this feature needs. So we **reuse it** in the scan flow rather than build a twin, and
**enhance it once** with a directly-typeable quantity field (per the user decision
"reuse it + add typing"), which benefits every caller.

## 2. Current behavior (what changes)

In `lib/features/scan/presentation/scan_screen.dart`, `_route()` handles three
recognition outcomes (`autoSell`, `chooseFromMatches` → after the "Did you mean?"
picker, `noMatch` → after the manual picker) and each ends by calling
`_addToCart(product)`, which **immediately** does
`cart.addOrIncrement(product, stepForUnit(product.unit))`, shows an "Added …"
snackbar, and returns `true` (keep scanning).

`showAddToCartSheet` already: computes `remainingStockFor`, shows an out-of-stock
state, steps by `stepForUnit`, clamps `+`/quantity to remaining stock, shows the live
subtotal, calls `cart.addOrIncrement(product, qty)` itself on Add + fires
`AppHaptics.success()`, and pops `true` (added) / `false` (cancel) / `null`
(dismiss). It currently shows the quantity as **read-only text** — no typing.

## 3. Enhancement to the shared sheet: typeable quantity

In `_AddToCartSheet` (`add_to_cart_sheet.dart`), replace the read-only quantity
`Text` (`'${Qty.format(_qty)} ${product.unitLabel}'`) with an editable
**`TextField`** sitting between the −/＋ buttons, with the unit label beside it:

- Backed by a `TextEditingController` kept in sync with `_qty`: tapping −/＋ updates
  both `_qty` and the field text; typing parses the field and updates `_qty`.
- `keyboardType`: decimal when `product.unitType.allowsDecimal` (weight/volume),
  whole-number otherwise (pieces). Pieces reject a typed decimal (floored to whole).
- On every change, the typed value is run through a pure helper
  `clampCartQuantity(value, remaining, allowsDecimal)` (see §5) → clamped to
  `[0, remaining]`, floored to whole for pieces. The subtotal updates live from the
  clamped `_qty`.
- Empty / unparseable / `0` field → `_qty = 0` → **Add disabled** (existing
  `(_qty <= 0)` guard already covers this).
- The existing −/＋ disable rules are kept (− disabled at ≤ one step; ＋ disabled when
  the next step would exceed remaining). Typing is the escape hatch for large amounts.

Everything else in the sheet (identity, stock hint, subtotal row, Cancel/Add
buttons, out-of-stock handling) is unchanged. Its `Future<bool?>` contract is
unchanged, so the Product Detail caller keeps working with no edit.

## 4. Scan flow wiring (`scan_screen.dart`)

Replace `_addToCart(Product)` with `_confirmAndAdd(Product) → Future<bool>`:

```dart
Future<bool> _confirmAndAdd(Product product) async {
  final added = await showAddToCartSheet(context, product: product);
  if (!mounted) return false;
  if (added == true) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Added ${product.name} to cart')));
  }
  return true; // keep scanning whether added, cancelled, or dismissed
}
```

Update the three `_route` call sites (`autoSell` → `_confirmAndAdd(products.first)`;
the two picker paths → `_confirmAndAdd(picked)`). The old inline out-of-stock /
"already fully staged" snackbar and the direct `addOrIncrement` are removed — the
sheet now owns stock handling and the add. `AppHaptics.success()` is fired by the
sheet, so it is not duplicated here.

**Behavior decisions preserved from Option C:** adding reopens the camera (the
`_run` loop), so Add behaves as "add & scan next"; Cancel/dismiss adds nothing and
also returns to the camera; the AppBar back arrow remains the single explicit exit to
the cart. The product-**picker** dismissal on the ambiguous/no-match paths keeps its
current pop-to-exit behavior; only the quantity sheet's dismissal returns to scanning.

## 5. Files

- **Modify:** `lib/features/cart/presentation/add_to_cart_sheet.dart` — add the
  typeable `TextField` + `TextEditingController` wiring described in §3.
- **Modify:** `lib/features/cart/domain/cart_math.dart` — add pure helper
  `double clampCartQuantity({required double value, required double remaining,
  required bool allowsDecimal})` (clamp to `[0, remaining]`; floor to whole when
  `!allowsDecimal`). Extracted so the typing/clamp math is unit-testable without a
  widget, and reusable by the sheet.
- **Modify:** `lib/features/scan/presentation/scan_screen.dart` — replace
  `_addToCart` with `_confirmAndAdd`; update the three `_route` call sites; drop the
  now-unused out-of-stock snackbar branch and the direct cart import usage if it
  becomes unused.

No changes to `cart_controller.dart`, the Edge Functions, or the Gemini migration.

## 6. Testing

- **Unit** (`test/features/cart/cart_math_test.dart`, extend if present else create):
  `clampCartQuantity` — clamps above remaining down to remaining; negatives → 0;
  pieces floor `2.7 → 2`; weight keeps `2.5`; value within range passes through;
  `remaining` of `0` → `0`.
- **Widget** (`test/features/cart/add_to_cart_sheet_test.dart`): pump the sheet for a
  piece product with known stock — typing `20` when only `12` in stock clamps to
  `12` and updates the subtotal; typing a decimal for a piece floors it; typing `0`
  or clearing disables Add; −/＋ still work and stay in sync with the field; Add pops
  `true` and stages the typed quantity; Cancel pops `false`.
- **Scan-flow** (`test/features/scan/scan_confirm_test.dart`, new): a recognized
  single match opens the add-to-cart sheet rather than adding immediately, and only
  the confirmed quantity lands in the cart. (Uses the existing scan test doubles /
  controller-override pattern if one exists; otherwise a focused widget test around
  `_confirmAndAdd`.)

## 7. Out of scope

- No change to recognition, the Edge Function, or the Gemini migration.
- No change to the Cart screen's own line stepper or checkout.
- No multi-quantity-per-scan or barcode features.
- Product Detail keeps its current behavior; it simply inherits the typeable field
  for free.

## 8. Rollback

Feature is additive and branch-isolated. Reverting the branch's commits restores the
auto-add-one scan behavior and the read-only stepper; no data or schema implications.
