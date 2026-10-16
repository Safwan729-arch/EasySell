---
tags: [design, cart, history]
---

# Cash / Digital / Credit at checkout — design

**Date:** 2026-10-15 · **Status:** built (migration `0018`, must be applied before the app ships)
**Path:** bounded, so there is no separate plan. The design was agreed in chat.

## 1. What the user asked for

At checkout, pick **Cash** or **Digital** (bKash, Nagad, card…) for how the
customer paid. Show it **only at checkout and in History**: no Dashboard,
Analytics or Restock changes.

## 2. Decisions

| Decision | Why |
|---|---|
| **One row: Cash · Digital · Credit** | The cart already had a Cash/Credit toggle. The user picked one three-way row over "Paid now / Credit, then Cash / Digital" (two taps for every digital sale) and over dropping Credit (that would remove the khata). |
| **Stored per transaction row** (`transactions.payment_method`), not on a receipt table | A receipt is just rows sharing `sale_group_id`. There is no receipt table, and adding one for a single column is the same grain-mismatch trap `sale_discounts` was rejected for (cart-discount design). Every line of one checkout gets the same value. History reads the first line. |
| **Credit is derived on the server, never sent** | A sale with `p_customer_id` *is* a credit sale. Deriving it means the method and the khata entry can't disagree. |
| **The app sends `p_payment_method` only for digital** | Cash is the server default. So cash and credit checkouts keep working if the app reaches a database without 0018, and only a digital checkout fails. The other way round, every checkout would break. |
| **No backfill. Old sales show no label** | A pre-0018 sale with no customer was *not* necessarily cash: the shopkeeper had no way to record bKash. "Cash" would be a guess, and showing nothing is honest. |
| **Changing cash ↔ digital after a failed checkout mints a new sale id** | Same rule as a changed customer or discount (0010). Reusing the id would make the server replay the first attempt with its old method and silently drop the change. |
| **Toggle goes full width** (was capped at 260 dp) | Three labels in 260 dp would scale the text down, and Bangla even more. |

## 3. Gotchas

- **New parameter = new signature.** 0018 drops the 0012 `record_sale_cart`
  overload first. Otherwise PostgREST sees two candidates and refuses the call.
- `record_sale_cart`'s body in 0018 is 0012's, **unchanged** apart from the
  method block and one insert column. Every comment about discount flooring,
  typmods and replay still applies. Edit the newest copy only.
- `TransactionRepository.recordSaleCart` has five hand-written test fakes
  (`cart_harness.dart` and four checkout tests). A new named parameter has to be
  added to all of them, or they stop compiling.

## 4. Out of scope (deliberately)

Cash vs digital totals on the Dashboard or Analytics, a History filter by
method, and which digital provider was used. The user limited this to checkout
and History. Since the column exists now, any of these can be added later
without another migration.
