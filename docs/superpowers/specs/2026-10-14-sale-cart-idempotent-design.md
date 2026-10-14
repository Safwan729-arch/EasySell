---
tags: [design, sale-cart, reliability]
---

# Retry-safe checkout (`record_sale_cart` idempotency) — design

**Status:** built 2026-10-14. Migration `0010_sale_cart_idempotent.sql`
applied to the live database the same day (pasted into the SQL editor; checked
afterwards: one `record_sale_cart`, six arguments, lock present), so the app
build is safe to ship (see §4 for why the order mattered). Found while designing [[2026-10-13-offline-selling-sync-design]]
(its §3 trap 1), and fixed on its own because it is a live bug today, not only
an offline one.

## 1. The bug

`record_sale_cart` minted the sale id (`v_group := gen_random_uuid()`). On weak
signal the server can commit a sale and the reply can be lost. The app sees a
failure, keeps the cart (it is cleared only on success), and the shopkeeper taps
Checkout again: a brand-new id, so the same sale is recorded twice — stock taken
twice, revenue doubled, and on credit the khata debt doubled.

The existing `_inFlight` guard in `CartCheckoutController` does not help: it
stops two *overlapping* taps, not a retry after the first call has returned.

## 2. Fix

- **Phone mints the id.** `CartCheckoutController` creates a UUID (`uuid`
  package, already a transitive dependency) and sends it as `p_sale_group_id`.
- **Server records an id once.** If rows with that `(shop_id, sale_group_id)`
  exist, it returns them and changes nothing.
- **Retry reuses the id only for an identical request.** The controller keeps
  the id plus a JSON snapshot of the request (shop, items, source, customer,
  discount). Same snapshot → same id; anything changed → new id. Cleared on
  success.

## 3. Decisions and why

- **Replay check runs before the stock check.** The first call already took
  the stock, so a replay that re-checked would fail with "Insufficient stock"
  for a sale that went through — telling the shopkeeper a completed sale
  failed. Verified by the probe: replay with stock forced to 0 still succeeds.
- **Advisory lock on the id** (`pg_advisory_xact_lock(hashtextextended(...))`).
  `sale_group_id` cannot be a unique column (one sale = several rows), so the
  exists-check alone could let two simultaneous calls both insert. The lock
  serialises them; the second waits for the first to commit, then replays.
- **A changed request gets a new id, not the old one.** Reusing it would make
  the server hand back the *old* sale and silently drop the edit. Rejected
  alternative: having the server compare the payload against stored rows and
  error on mismatch — more SQL, and it turns a legitimate "I changed my mind"
  into an error.
- **Accepted gap:** if attempt 1 actually saved and the shopkeeper then edits
  the cart and retries, both sales are recorded. The app cannot know attempt 1
  saved; the second is a genuinely different request. Rare, and visible in
  History.
- **The id is held in memory only.** If the app is killed between a lost reply
  and the retry, the retry gets a fresh id. Persisting it was judged not worth
  it for the online case; the offline-sync design will persist ids anyway.
- **`p_sale_group_id` defaults to null** (= fresh id, 0009 behaviour), so app
  builds from before 0010 keep working once the migration is live.
- **Not changed:** `record_restock` has the same weakness. Single item, lower
  stakes; left for later.

## 4. Deploy order (gotcha)

Migration first, then the app. The new app always sends `p_sale_group_id`; on a
database without 0010, PostgREST finds no function with that argument and
**every checkout fails**. The reverse order is safe (old app → default null).

0010 drops every earlier `record_sale_cart` signature before creating the new
one — the same overload trap as 0006/0009.

## 5. Verification

- `test/cart_checkout_idempotency_test.dart`: retry reuses the id; changed
  items / discount / customer each get a new id; the sale after a success gets
  a new id.
- SQL probe on the live database, run as a `pg_temp` copy of the function inside
  a `DO` block that ends in `raise exception` (so everything rolls back; live
  stock confirmed unchanged afterwards): stock 9 → 8 on the first call, still 8
  and one row on a same-id replay, replay succeeds with stock at 0, null id
  records a fresh sale (8 → 7).
