# Sale cart — design spec

**Date:** 2026-07-07
**Status:** Approved, pending implementation plan

## Problem

Today every sale is recorded one product at a time: tap a product in Inventory →
product detail → "Record sale" → confirm sheet → commits immediately via the
`record_sale` RPC. When a customer buys several items, the shopkeeper must repeat
this full round-trip per item, which doesn't scale well for busy shops. This
design introduces a cart: items are staged locally, then committed together in
one checkout.

## Goals

- Let a shopkeeper add multiple products to a running cart, then commit them all
  in a single checkout action.
- Never allow a partial checkout — a cart either fully commits or fully fails.
- Keep every other existing flow (restock, dashboard/report aggregates, single
  historical sales) working exactly as it does today.
- No feature flag: this replaces the one sale-entry path used today, so a
  runtime toggle would mean maintaining two parallel sale flows. Safety instead
  comes from an additive-only migration and a git rollback checkpoint.

## UX flow, screen by screen

- **Product detail** (`lib/features/inventory/presentation/product_detail_screen.dart`):
  the **"Record sale"** button becomes **"Add to cart."** Tapping it opens the
  existing quantity-stepper sheet (relabeled), capped at *stock minus whatever is
  already staged in the cart for that product*. Confirming adds the line to the
  cart and pops back to the Inventory list, ready to search the next item.
  **Restock is unchanged** — same button, same instant commit via
  `record_restock`.
- **Camera scan** (`lib/features/scan/presentation/scan_screen.dart`): a
  recognized product is added to the cart directly (qty 1, adjustable later)
  with a quick snackbar, instead of opening the commit-now confirmation sheet.
  After a successful add, the screen **reopens the camera for the next shot**
  (loops back into capture) instead of closing, so a shopkeeper can scan a
  customer's items back-to-back. Tapping the AppBar back arrow at any point
  exits to Inventory, where the global cart bar reflects everything scanned so
  far. Cancelling out of the "Did you mean?" chooser or the no-match picker
  still exits to Inventory, same as today — only a successful add loops.
- **Global cart bar**: a slim bar (e.g. "3 items · $12.50 ▸") appears just above
  the bottom nav in `MainShell`, visible on all four tabs (Home / Items /
  Reports / History) whenever the cart is non-empty. Tapping it opens a
  full-screen **Cart** page at `/cart`.
- **Cart page**: one row per product — qty stepper, line subtotal, remove —
  plus a grand total and a **Checkout** button. This page *is* the
  review-before-commit step; there is no second confirmation modal (same
  principle as today's single-item sheet, just scaled to N lines).
- **History** (`lib/features/transactions/presentation/history_screen.dart`):
  sale rows from one checkout are grouped into a single expandable "receipt"
  row (e.g. "3 items · $12.50"), tap to see the individual lines. A single
  manual/voice/scanned sale (no cart involved) still renders as its own
  one-line receipt — visually identical to today, including all pre-existing
  historical rows.
- **Dashboard & Reports**: **no changes.** Both read from aggregate RPCs
  (`get_dashboard_summary`, category split, best sellers) that already sum every
  `transactions` row regardless of grouping. One layout note: Dashboard's
  floating "Sell" button and the new global cart bar both anchor to the bottom
  of the screen; Flutter's `Scaffold` already positions a FAB above
  `bottomNavigationBar` automatically, so they are not expected to collide, but
  this should be verified visually once built.

## Data model

Additive migration `supabase/migrations/0007_sale_cart.sql`:

```sql
-- New nullable column: existing rows stay null and keep rendering as
-- single-line receipts in History.
alter table transactions add column if not exists sale_group_id uuid;
create index if not exists idx_transactions_sale_group on transactions (shop_id, sale_group_id);

-- record_sale_cart -------------------------------------------------------------
-- Atomic multi-item checkout, sibling to record_sale. All lines commit or none
-- do: the whole loop runs inside one plpgsql function call, so any
-- raise exception rolls back every row lock, stock decrement, and insert made
-- earlier in the same checkout.
create or replace function record_sale_cart(
  p_shop_id uuid,
  p_items jsonb,              -- [{"product_id": "...", "quantity": 2}, ...]
  p_source text default 'manual'
) returns setof transactions
language plpgsql
as $$
declare
  v_group uuid := gen_random_uuid();
  v_item record;
  v_product products;
begin
  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'Cart is empty';
  end if;

  for v_item in
    select * from jsonb_to_recordset(p_items) as x(product_id uuid, quantity numeric)
  loop
    if v_item.quantity is null or v_item.quantity <= 0 then
      raise exception 'Quantity must be greater than zero';
    end if;

    select * into v_product from products
      where id = v_item.product_id and shop_id = p_shop_id
      for update;

    if v_product is null then
      raise exception 'Product not found';
    end if;

    if v_product.quantity < v_item.quantity then
      raise exception 'Insufficient stock for %: have %, need %',
        v_product.name, v_product.quantity, v_item.quantity;
    end if;

    update products set quantity = quantity - v_item.quantity, updated_at = now()
      where id = v_item.product_id;

    insert into transactions(shop_id, product_id, type, quantity, buying_price,
                              selling_price, source, sale_group_id)
    values (p_shop_id, v_item.product_id, 'sale', v_item.quantity,
            v_product.buying_price, v_product.selling_price, p_source, v_group);
  end loop;

  return query select * from transactions where sale_group_id = v_group;
end;
$$;
```

`now()` is transaction-scoped in Postgres, so every line inserted in one
checkout shares the exact same `created_at` — this is what makes History's
grouping reliable without any extra bookkeeping. RLS already covers
`transactions`/`products` via the existing shop-scoped policies from
`0001_init.sql`; no new policy is needed.

## Flutter architecture

New feature module `lib/features/cart/` (feature-first, per project convention):

- `domain/cart_line.dart` — `CartLine(Product product, double quantity)`
  (freezed; `quantity` is a `double` to support kg/L fractions, mirroring
  `Transaction.quantity`).
- `presentation/cart_controller.dart` — `CartController extends
  Notifier<List<CartLine>>` with `addOrIncrement`, `updateQuantity`, `remove`,
  `clear`, plus derived `totalLines` / `grandTotal` getters. **In-memory only**
  — no persistence table, no disk cache. It's pre-commit staging, same category
  of state as today's confirmation sheet; losing it on app kill is a UX
  inconvenience, not a data-integrity issue, since nothing is committed until
  checkout. Cleared on successful checkout, on explicit "Clear cart," and on
  sign-out/shop switch.
- `presentation/cart_bar.dart` — the slim global bar, added into `MainShell`'s
  `bottomNavigationBar` (a `Column` above `AppBottomNav`, animated size-in when
  the cart is non-empty).
- `presentation/cart_screen.dart` — the full `/cart` page (line list, stepper
  per line, grand total, Checkout button), registered as a root-navigator route
  like `/inventory/new`.

**Reused, not duplicated:** checkout calls a new `recordSaleCart` method added
to the *existing* `TransactionRepository` — it's still fundamentally "record
transactions," same `Failure` mapping, same `Transaction.fromJson` deserializing
each returned row. No separate cart repository. `Transaction` gains one new
nullable field, `saleGroupId`.

**Product detail & scan changes:** `_recordSale` in `product_detail_screen.dart`
and `_sell` in `scan_screen.dart` call `cartControllerProvider.notifier
.addOrIncrement(...)` instead of `showSaleConfirmationSheet`.
`showSaleConfirmationSheet` is retired for the sale path (kept only for
restock). In `scan_screen.dart`, `_sell` no longer pops after adding — it calls
`_run()` again to reopen the camera, so all three routing outcomes
(`autoSell`, `chooseFromMatches`, `noMatch`) loop back into another capture
after a successful add.

**History grouping:** with `Transaction.saleGroupId` added, `history_screen
.dart`'s `_visibleRows` groups by `saleGroupId ?? 'single-${id}'` before
sorting. A new `_ReceiptRow` (product-count "items," summed revenue, shared
timestamp) replaces `_DataRow` as the top-level row, expandable to the
underlying per-product lines. Search matches if *any* line in the receipt
matches; sort operates on the receipt's aggregate values.

## Error handling & edge cases

- **Checkout failure** (e.g. stock ran out on one item): the RPC's exception
  message (e.g. "Insufficient stock for Coca-Cola: have 2, need 3") surfaces
  inline on the Cart page, the same pattern as today's sheet. **The cart is
  left intact** — nothing is cleared on failure — so the shopkeeper edits that
  line's quantity and taps Checkout again. The cart only clears on confirmed
  success.
- **Client-side over-add guard:** the quantity stepper in "Add to cart" clamps
  to `stock − already-in-cart-for-this-product`, so adding the same item twice
  can't silently exceed stock in the common case. The RPC remains the
  authority; this is a UX nicety, not the safety mechanism.
- **Empty cart:** the Checkout button is disabled with zero lines; the RPC also
  guards an empty `p_items` as a defense-in-depth backstop, mirroring
  `record_sale`'s existing `quantity <= 0` guard style.
- **Sign-out / shop switch:** cart is cleared, same category as any other
  unsaved local UI state — no cross-shop leakage.

## Rollback / safety

No runtime feature flag (see Goals). Safety comes from: a `checkpoint-pre-cart`
git tag before starting, an isolated branch `feat/sale-cart`, and a migration
that is purely additive (new nullable column, new function) — safe to apply
even if the branch is later abandoned, since nothing existing is dropped or
altered. Rollback is `git checkout checkpoint-pre-cart`, the same pattern used
for the vision-scan feature.

## Testing plan

- **Unit tests:** `CartController` (add/increment/update/remove/clear, grand
  total & line-count math, stock-clamp on add), and the History grouping logic
  (mixed grouped/ungrouped rows sort and group correctly, including the "null
  `saleGroupId` = singleton receipt" case for existing/legacy data).
- **Manual/device pass:** add several products to cart from Inventory, scan one
  item into the same cart, verify the global bar updates on all four tabs,
  checkout, confirm stock decremented once per line (not double), confirm
  History shows one grouped receipt that expands correctly, confirm
  Dashboard/Reports totals match the checkout total. Then force a failure case
  (stage more of an item than is in stock, or restock it down from another
  device mid-cart) and confirm the whole checkout is rejected with the item
  named and the cart preserved.
- No changes needed to existing `record_sale`/`record_restock` tests — both are
  untouched.
