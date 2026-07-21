# Sale Detail Screen — Design Spec

**Date:** 2026-07-21
**Feature owner:** Member A (Flutter + Supabase)
**Branch base:** current working branch (`feat/customer-credit`)

## 1. Problem

In the History tab, each sale row shows a compact table (`Time · Item · Qty · Amount`).
The **Item** column truncates long product names (e.g. `Soyabean …`), and a single-sale
row is not tappable — there is no way to see the full detail of a past sale. Shopkeepers
want to tap a sold item and see the full story of that one sale.

## 2. Goal

Add a **Sale Detail** screen that opens when a shopkeeper taps a sold item in History.
It answers "what exactly happened in this one sale?" using the values already recorded on
the transaction row.

Explicitly **out of scope** (YAGNI):
- No payment method / Cash-vs-Credit / customer (khata) info. *(User decision.)*
- No whole-receipt summary screen. Each product line opens its own detail. *(User decision.)*
- No edit/delete of a sale. History is a record, not editable.
- No product-level stats (current stock, lifetime sold). This screen is about the sale,
  not the product. *(User decision: "this sale's story".)*

## 3. Navigation & Entry Points

The History list has two row shapes (see `history_screen.dart`):

| Row shape | Today's tap behavior | New tap behavior |
|---|---|---|
| **Single sale** (`row.isSingle`) | nothing (`onTap: null`) | opens Sale Detail for that transaction |
| **Multi-item receipt** (cart checkout) | toggles expand | unchanged — still toggles expand; each **expanded line** becomes tappable and opens Sale Detail for that line's transaction |

So every individual sale — standalone or a line within a receipt — is reachable, and the
receipt's expand/collapse affordance is preserved.

### Route

- Path: `/history/sale/:id` on the **root navigator** (`parentNavigatorKey: _rootKey`),
  full-screen with the standard `_transitionPage` slide-in, consistent with
  `/inventory/:id`, `/settings`, `/customers`, etc.
- The tapped `Transaction` object is passed via go_router's `extra`. The list already holds
  it in memory, so **no new database query** is needed to open the screen.
- `:id` is the transaction id — present for a stable/loggable URL and as the lookup key for
  the fallback path below.

### Data resolution on the screen

- **Transaction:** read from `state.extra as Transaction?`.
- **Product name + unit label:** resolved live from `productsStreamProvider` by
  `transaction.productId` (exactly how the History list resolves names today). This keeps
  the name current and gives the unit (`litre`, `kg`, `pcs`) for the quantity line.
- **Deleted product:** if no product matches `productId`, show the localized `Sale` fallback
  name and render the quantity as a plain number with no unit.
- **Missing `extra` (safety fallback):** in-app navigation always sets `extra`, but if the
  screen is ever reached without it (e.g. a hypothetical deep link / hot-restart on the
  route), show a simple "Sale not found" state with a back affordance rather than crashing.
  We deliberately do **not** add a repository fetch-by-id for MVP.

## 4. Screen Content ("this sale's story")

All monetary/profit figures come from the **frozen snapshot** on the transaction row
(`buyingPrice`, `sellingPrice` captured at sale time) — never recomputed from current
product prices (CLAUDE.md §4 rule).

```
┌─────────────────────────────┐
│  ←   Sale details           │   AppBar
│                             │
│   🅢  Soyabean Oil           │   avatar (initial) + full name, no truncation
│                             │
│   Sold on                   │
│   Mon, 21 Jul 2026 · 8:44 PM│   full localized date + time
│  ─────────────────────────  │
│   Quantity        0.5 litre │   qty + unit label (plain number if product gone)
│   Price each          ৳850  │   sellingPrice
│   Total               ৳425  │   revenue = sellingPrice × qty  (emphasized)
│   Cost                ৳350  │   cost = buyingPrice × qty
│   Profit              ৳75   │   profit = revenue − cost (positive/negative color)
│   Entered by        Manual  │   source: Manual / Voice / Photo scan (— if null)
│  ─────────────────────────  │
│   ⓘ Prices are locked in    │   footnote explaining frozen snapshot
│     from the moment of sale │
└─────────────────────────────┘
```

Field mapping (all already on `Transaction` / its getters):

| Row | Source |
|---|---|
| Quantity | `transaction.quantity` + resolved `ProductUnit.label` |
| Price each | `transaction.sellingPrice` |
| Total | `transaction.revenue` |
| Cost | `transaction.cost` |
| Profit | `transaction.profit` (green if ≥ 0, red if < 0) |
| Entered by | `transaction.source` → localized label; `—` when null |

Currency: `myShopProvider.value?.currency ?? 'USD'`, formatted via `Money.format`.
Profit color: reuse `AppColors.positive` / `negative` theme extension.

## 5. Localization

New keys added to **both** `lib/l10n/app_en.arb` and `lib/l10n/app_bn.arb` (identical key
sets — enforced by `l10n_parity_test`). Proposed keys:

- `saleDetail_title` — "Sale details"
- `saleDetail_soldOn` — "Sold on"
- `saleDetail_quantity` — "Quantity"
- `saleDetail_priceEach` — "Price each"
- `saleDetail_total` — "Total"
- `saleDetail_cost` — "Cost"
- `saleDetail_profit` — "Profit"
- `saleDetail_enteredBy` — "Entered by"
- `saleDetail_frozenNote` — "Prices are locked in from the moment of sale."
- `saleDetail_notFound` — "Sale not found."
- Source labels: `saleDetail_sourceManual` / `saleDetail_sourceVoice` /
  `saleDetail_sourcePhoto` (check for an existing source-label helper first and reuse if
  one exists rather than duplicating).

Reuse existing `history_saleFallback` ("Sale") for the deleted-product name.

## 6. Files

- **New:** `lib/features/transactions/presentation/sale_detail_screen.dart` — the screen
  (`ConsumerWidget`); pure presentation, reads providers, no business logic.
- **Edit:** `lib/core/router/app_router.dart` — add `AppRoutes.saleDetail` constant + the
  `/history/sale/:id` root-navigator route.
- **Edit:** `lib/features/transactions/presentation/history_screen.dart` — make single-sale
  rows and expanded receipt lines tap to `context.push` the detail route with the
  `Transaction` as `extra`.
- **Edit:** `lib/l10n/app_en.arb`, `lib/l10n/app_bn.arb` — new keys.
- **Maybe new:** a small source-label helper (or extend an existing l10n helper) if none
  exists.

## 7. Testing

- Widget test: tapping a single-sale row pushes the detail route and the screen renders the
  correct product name, quantity, total, and profit for a known transaction.
- Widget test: profit sign drives color (positive vs negative) — or at least that a negative
  profit renders without error.
- `l10n_parity_test` continues to pass (equal key sets en/bn).
- `flutter analyze` clean; full `flutter test` green.

## 8. Non-goals / Future

- A whole-receipt summary screen (grand total of a cart checkout) — deferred; user chose
  per-item detail.
- Product-level analytics from a sale — deferred.
- Editing/voiding a sale — out of scope.
