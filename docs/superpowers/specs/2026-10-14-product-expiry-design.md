---
tags: [design, inventory, expiry, notifications]
---

# Product expiry dates and alerts — design

**Status:** built 2026-10-14 on `feat/product-expiry` (plan:
[[2026-10-14-product-expiry]]). Migration `0011` applied and probed before the
app work. Edge-case review in §11.

## 1. Goal

Let the shopkeeper record an expiry date when stock comes in, warn them before
it expires, and stop expired stock from being sold by default — without
touching how a sale is recorded.

Success looks like:
- Bread added Monday that expires Saturday is warned about on Friday, not the
  moment it is added.
- After a restock, old and new stock keep their own dates; neither overwrites
  the other.
- Expired units stay counted as expired until the shopkeeper removes them;
  sales are counted against good stock.
- A sale of more than the good stock is blocked in the cart with a way out.
- A daily phone reminder arrives even with no internet.
- A restock retried after a lost reply adds stock (and its delivery) once.

## 2. Decisions (all made with the user, 2026-10-14)

| Question | Decision | Why |
|---|---|---|
| How dates are stored | **A date per delivery**, estimated, not exact lot tracking | One date per product breaks on the first restock (overwrite → old stock unwarned; keep → false alarm on fresh stock). Exact lot tracking means every sale picks a delivery, which changes `record_sale_cart`, voice, scan and the offline plan. |
| How alerts reach the seller | **In-app + a daily phone reminder, built now** | User chose this knowing CLAUDE.md §1/§7 assign phone notifications to Member C. This feature's reminder is built here; record that ownership note. |
| When the warning starts | **Automatic from shelf life, with an optional per-product override** | A fixed window (e.g. 7 days) flags 5-day bread the moment it is added. User raised this case. |
| Expired stock vs sales | **Sales never count against expired stock by default** (user's idea) | Replaced the first proposal (a cart warning). Keeps the expired count correct when the shopkeeper sells before removing expired units. |
| Only expired stock left | **Block in the cart** with "Remove expired" and "They're not expired"; no "Sell anyway" | "Never sell expired by default." The second button is the escape hatch when the estimate is wrong. |
| Restock retries | **Make `record_restock` retry-safe in the same change** | Restock had the double-record gap that 0010 fixed for sales; with deliveries it would also duplicate the delivery. The signature changes anyway, so one change instead of two. |

Rejected along the way:
- **Cart warning only** (my first suggestion): selling before removing expired
  units made the estimate assume an expired unit was sold.
- **"I still have N" correction on a delivery:** makes the estimate much harder
  to reason about. v1 offers "Edit", "None left" and "Remove from stock"; the
  product page lists deliveries so the shopkeeper can check.
- **Server push (FCM + `pg_cron`):** needs Firebase, a server job (`pg_cron`
  is not installed on the project) and Member C's area. Phone-scheduled
  reminders work offline and need no server.

## 3. Data (migration `0011_product_expiry.sql`)

### `product_batches` (new) — one row per delivery that has an expiry date

```
id            uuid primary key default gen_random_uuid()
shop_id       uuid not null references shops(id) on delete cascade
product_id    uuid not null
quantity      numeric(10,3) not null check (quantity > 0)   -- amount received
buying_price  numeric(10,2) not null    -- frozen at delivery, values the loss
received_on   date not null             -- phone's local date, §3.4
expiry_date   date not null
expired_qty   numeric(10,3) check (expired_qty >= 0)        -- locked, §4.2
closed_at     timestamptz               -- null = open
closed_reason text check (closed_reason in
                ('removed','none_left','not_expired','sold_out'))
created_at    timestamptz not null default now()

foreign key (product_id, shop_id) references products(id, shop_id)
  on delete cascade
```

- **The product must belong to the same shop.** RLS checks `shop_id` on the
  batch row only, so with a plain `product_id` foreign key a row could carry the
  caller's `shop_id` and another shop's `product_id`. The composite foreign key
  makes the database refuse it. It needs `unique (id, shop_id)` on `products`
  (added by 0011; `id` is already unique, so this cannot fail on existing data).
- RLS enabled, same shop-owner policy shape as `products` (CLAUDE.md §4).
- Index on `(shop_id, product_id) where closed_at is null`.
- No check that `expiry_date >= received_on`: "Add expiry date" to stock already
  on the shelf may legitimately enter a date that has passed. The app confirms
  odd dates instead (§5).

### `products.expiry_warn_days` (new column)

`integer null check (expiry_warn_days >= 0)`. Null = automatic rule (§4.3).

### 3.1 `record_restock`: optional expiry date + retry-safe

New signature:

```
record_restock(p_shop_id uuid, p_product_id uuid, p_quantity numeric,
               p_source text default 'manual',
               p_expiry_date date default null,
               p_received_on date default null,
               p_restock_id uuid default null)
```

1. `v_id := coalesce(p_restock_id, gen_random_uuid())`. The phone mints it.
2. `pg_advisory_xact_lock` on `v_id`; if a `transactions` row with `id = v_id`
   and this shop already exists, **return it and change nothing** (same method
   and reasoning as 0010: a lost reply plus a retry must not add stock twice).
3. Otherwise as today: lock the product row, add stock, insert the `restock`
   transaction **with `id = v_id`**.
4. If `p_expiry_date` is set, insert the batch in the same transaction
   (`buying_price` = the product's current buying price, `received_on =
   coalesce(p_received_on, current_date)`). Stock, transaction and delivery
   commit together or not at all.

**Overload trap (same as 0006/0009/0010):** drop the old 4-argument signature
(and any 7-argument one, for re-runs) first, or PostgREST cannot pick one and
every restock breaks. Old app builds keep working: all new parameters default
to null.

App side: the restock sheet mints the id on the first Confirm and reuses it
only for an identical retry (same product, quantity, date), cleared on success —
the `CartCheckoutController` pattern from 0010.

### 3.2 `remove_expired_stock(p_shop_id, p_batch_id)` (new RPC)

1. Lock the batch row and the product row (`for update`), both checked against
   `p_shop_id`.
2. If the batch is already closed, return without changing anything — a second
   tap or a retry after a lost reply must not remove stock twice.
3. If `expired_qty` is null, raise "not expired" — removal only acts on a locked
   count.
4. `v_qty := least(expired_qty, product.quantity)`.
5. If `v_qty > 0`: decrement stock by `v_qty` and insert a `transactions` row:
   `type = 'adjustment'`, `quantity = v_qty` (**positive**),
   `buying_price` = **the batch's** buying price, `selling_price` = the
   product's current one, `source = 'manual'`.
   If `v_qty = 0` (stock was lowered by hand), write no transaction.
6. Close the batch: `closed_at = now()`, `closed_reason = 'removed'`.

Convention set here: an `adjustment` row's quantity is **units removed**. It
must be positive — `transactions_discount_within_line` (0009) checks
`discount_amount <= selling_price * quantity`, which a negative quantity fails.
No `adjustment` rows exist yet (live: only `sale` and `restock`).

Nothing that reads `transactions` is affected: every report RPC
(`get_dashboard_summary`, `get_sales_series`) and every app query
(`recentSales`, `salesForDay`, `earliestSaleDate`) filters `type = 'sale'`, and
`record_sale_cart` only reads its own `sale_group_id`. The rows keep the loss
(`v_qty × batch buying_price`) for a later "loss from expiry" report.

### 3.3 Other writes (plain repository calls under RLS)

- **New product with an expiry date:** insert the product (as today), then
  insert the batch with `quantity` = starting stock. If the second insert
  fails, the product stays saved and the user is told to add the date from the
  product page. (No RPC: the product insert is already a client insert.)
- **"Add expiry date"** on the product page: inserts a batch. Quantity defaults
  to stock not covered by open batches (editable). `received_on` defaults to the
  date of the product's latest `restock` transaction, else the product's
  `created_at` date (editable) — see §4.3 for why "today" is wrong here.
- **"Edit" a delivery** (open batches only): change expiry date and/or amount.
  If the new expiry date is today or later, clear `expired_qty` — this undoes a
  lock caused by a mistyped date.
- **"None left" / "They're not expired":** close the batch with the matching
  `closed_reason`. "They're not expired" closes the *expired* delivery, so those
  units count as good stock again.
- **Reconcile writes** (§4.2): lock an expired count, or close a delivery as
  `sold_out`. Each is `update ... where id = ? and closed_at is null` (plus
  `and expired_qty is null` for a lock), so if two phones race, the first
  writer wins and the second write is a no-op.

### 3.4 Dates are the phone's local date

`received_on`, "today" and the expiry comparison all use the **phone's local
date**. The server's `current_date` is UTC: in Bangladesh (UTC+6) it is still
"yesterday" from midnight to 6 AM, which would shift a 5-day shelf life to 6
and move the warning. The app always sends `p_received_on`; the server's
`current_date` is only a fallback for old callers.

A wrong phone clock gives wrong dates. Accepted: the app has no trusted clock
offline, and sales already use server time for `created_at`.

## 4. The estimate (pure Dart, `features/expiry/domain/`)

One pure function computes everything shown or blocked. Inputs: the product's
current stock `Q`, its open batches, the warning settings and "today". Output:
per-batch estimated units left and status, the product's good and expired
counts, and a list of **reconcile writes** (§4.2). It writes nothing itself.

### 4.1 Allocation

1. `R = Q`.
2. **Locked expired batches first**, oldest expiry first (then `created_at`):
   each takes `min(expired_qty, R)`. These are reserved, so sales never eat
   into them. If `Q` has been lowered by hand below their total, the earliest
   expiries keep their units and later ones shrink.
3. **All other open batches, newest received first** (`received_on` desc, then
   `created_at` desc): each takes `min(quantity, R)`. This is "older sells
   first": whatever is left over lands on the oldest deliveries.
4. Any `R` still left is **untracked** stock (no date) and counts as good.
   Untracked stock is therefore treated as the oldest, sold first. When an
   undated restock lands on top of an older dated delivery this is wrong, but
   on the safe side: the dated delivery keeps its count and is over-warned
   rather than missed.

Because it reads only the current `Q`, it stays correct however stock changed:
cart sale, voice, scan, restock, or a quantity edited in the product form (which
writes no transaction).

`good = Q − (units allocated to expired batches)`.

### 4.2 Reconcile: locking expired counts and closing sold-out deliveries

A batch is **expired when today > expiry_date**. "Expires 20 Oct" is good
through 20 Oct.

The estimate emits two kinds of reconcile write:

- **Lock:** an expired batch with `expired_qty` null and a step-3 allocation
  above 0 → write that allocation as `expired_qty`. From then on step 2
  reserves it. Without the stored lock, the next sale lowers `Q` and step 3
  would quietly assign the shortfall to the oldest (expired) delivery — "the
  expired bottle was sold".
- **Sold out:** an open, unlocked batch whose step-3 allocation is 0 → close it
  with `closed_reason = 'sold_out'`. This covers both an expired delivery that
  sold out before it expired (no "Expired: 0 bread" alerts, no pile-up of open
  rows for daily bread) and a dated delivery that sold out before an undated
  restock. Without closing it, the estimate would hand the undated new stock to
  the old delivery in step 3 and raise a false alarm.
  Accepted cost: stock edited by hand to 0 and back up closes deliveries that
  were still on the shelf; their units then count as untracked.

**When reconcile runs:** whenever the products stream, the batches, or
"today" change. **Checkout awaits any pending reconcile writes first.** If
they cannot be written (no signal), checkout stops with the normal network
error — the sale could not have reached the server either. This closes the gap
where a lock write fails and the next sale shrinks the expired count.

**"Today" must move.** A provider holds the local date; it updates on a timer
at local midnight and when the app returns to the foreground. Without it, an
app left open overnight never marks anything expired.

Known gaps, accepted: a second phone running an **older app version** can sell
past the block (the block is app-side; the server does not know about expiry),
and a second phone selling in the moment before the first phone's lock lands.
Both only shrink the expired count, capped at stock.

### 4.3 Warning rule

- `shelf = expiry_date − received_on` in days.
- If `products.expiry_warn_days` is set, `w = expiry_warn_days`.
- Otherwise `w = min(shopSetting, max(1, floor(shelf / 3)))`, `shopSetting`
  default 7.
- Status: **expired** if today > expiry_date; **expiring soon** if today ≥
  expiry_date − w and estimated left > 0; otherwise **good**.

Worked examples (shopSetting 7): bread, shelf 5 → w 1 → warned the day before.
Yogurt, shelf 14 → w 4. Rice, shelf 365 → w 7.

Why "Add expiry date" must not default `received_on` to today: a one-year item
that is 6 days from expiry would get shelf 6 → w 2 and be warned 2 days ahead
instead of 7. Defaulting to the last restock date restores the real shelf life.

### 4.4 Worked example (the user's Pepsi case)

Old delivery 5 (expired 20 Oct), new delivery 10 (expires 15 Dec), Q = 15.
On 21 Oct: step 3 gives new 10, old 5 → reconcile locks old at 5. Sell 3 →
Q = 12: step 2 reserves 5 expired, step 3 gives new 7. Home shows "Expired: 5
Pepsi". "Remove from stock" → Q = 10, adjustment row of 5 at the old delivery's
buying price, old batch closed.

## 5. Screens

All new text in English and Bengali (`l10n_parity_test` enforces both). Dates
shown with the app's locale formatting.

- **Add-product form:** optional **Expiry date** under Quantity, shown only
  when quantity is above 0 (a delivery of 0 is rejected by the database).
  **More options:** "Warn me __ days before" (empty = automatic).
  **Changing the unit** (e.g. pieces → kg) is blocked while the product has
  open deliveries: "Clear this product's deliveries before changing its unit",
  because their amounts are in the old unit.
- **Restock sheet:** optional **Expiry date**.
- **Odd dates (any date entry):** a past date asks "This date has already
  passed. Save anyway?"; a date more than 5 years ahead asks "Is this year
  right?". Both allow saving.
- **Product page:** **Deliveries** list — date added, expiry date, estimated
  left, status label (Good / Expiring soon / Expired). Expired rows: **Remove
  from stock**. All open rows: **Edit** and **None left**. A short "Closed"
  history below (sold out / removed / none left). Plus **Add expiry date**,
  shown only when stock is above 0 (same reason as the form field).
- **Home:** **"Expiring & expired"** card beside Low stock ("Expired: 5 Pepsi",
  "Bread: 3 expire tomorrow"); tap → product page.
- **Bell:** lists the same items with a count badge, replacing the placeholder
  sheet in `dashboard_screen.dart` (`_showNotificationsSheet`).
- **Items tab:** **"Expiring"** filter beside "Low stock".
- **Low stock uses good stock.** 5 expired + 1 good with threshold 3 is low.
  Applies to the Home card, the Items filter, inventory totals and the product
  page. `Product.isLowStock` stays as is for products with no expired stock.
- **Cart:**
  - The add-to-cart limit (`remainingStockFor`) uses **good** stock, so the
    sheet never offers units the cart would then block. The voice review
    sheet's low-stock hint uses good stock too.
  - A line whose quantity exceeds the product's good stock while expired units
    exist shows "Only 1 good Pepsi left (5 expired)" with **Remove expired**
    and **They're not expired**. Checkout is blocked until resolved.
  - After **Remove expired**, a line still above the remaining stock shows
    "Only X left" so the shopkeeper lowers or removes it.
  - The rule lives in a provider that `CartCheckoutController` also checks
    (logic in controllers, CLAUDE.md §6), so voice and scan carts are covered.
    A quantity above *total* stock still fails in `record_sale_cart` as today.
- **Settings:** "Warn me up to __ days before" (default 7) and a phone reminder
  on/off switch, both stored on the phone (`shared_preferences`), like theme.
  If notification permission is permanently denied, the switch reads "Blocked —
  turn on in phone settings".

Archived products are excluded from every alert, filter and reminder (the
products stream already drops them). Restoring a product brings its open
deliveries back.

## 6. Phone reminder

- Package `flutter_local_notifications` (+ `timezone`, `flutter_timezone` to
  schedule at local 9 AM).
- **One notification per day at 9 AM**, only on days with something to report,
  e.g. "Expired: 5 Pepsi, 2 Milk +4 more". Tap → the alerts list (via
  `rootNavigatorKey`; a signed-out tap lands on login as usual).
- Scheduled on the phone, so it works offline. Cancel and reschedule the next
  **7 days** on: app open, any stock or delivery change, a settings change, and
  a **language change** (the text is baked in when scheduled). Each day's text
  comes from running §4 with that day as "today" (assuming no further sales).
  If 9 AM has already passed today, start from tomorrow.
- **Sign-out cancels every scheduled reminder**, so a shared phone does not
  keep showing the previous account's stock.
- `AndroidScheduleMode.inexactAllowWhileIdle`: may arrive minutes late, but needs
  no exact-alarm permission. Android 14 no longer grants `SCHEDULE_EXACT_ALARM`
  by default, and a missing permission can throw from the plugin.
- `POST_NOTIFICATIONS` is requested once, the first time an expiry date is
  saved (Android 13+). Refusal leaves in-app alerts working.
- Android setup the plan must include: the manifest permission; the plugin's
  boot receiver registered for **boot and app update**
  (`BOOT_COMPLETED`, `MY_PACKAGE_REPLACED`), since both can drop scheduled
  alarms; and core-library desugaring in `android/app/build.gradle`, which the
  plugin requires.
- **Limits:** not opening the app for more than 7 days lets reminders run out.
  Samsung's battery optimisation ("deep sleeping apps") can delay or drop them;
  the in-app alerts are the reliable surface.
- **Ownership:** CLAUDE.md gives phone notifications to Member C; the user chose
  to build this one here (2026-10-14). Leave a `// MEMBER C` note at the
  scheduler seam so their wider notification work can absorb it.

## 7. What does not change

- `record_sale_cart`, checkout's server side, voice sale, scan sale, the
  double-sale fix (0010).
- Reports and dashboard money figures (sales-only filters, §3.2).
- Inventory value still counts expired units until removed — they are on hand.
- History lists sales only, so removals are not shown there; the product page's
  Deliveries list shows them.
- Products without any expiry date behave exactly as today.
- Offline-selling plan ([[2026-10-13-offline-selling-sync-design]]): the
  estimate runs on the phone from cached data, so it fits.

## 8. Deploy order

Apply `0011` **before** shipping the app. The new app calls `record_restock`
with the new parameters and reads `product_batches`; on a database without
0011, restock fails and the new screens error. Old app builds keep working on
the new database (the new parameters default to null).

## 9. Testing

- **Estimator unit tests:** the Pepsi case (§4.4); a sale before removal keeps 5
  expired; a lock capped by a hand-lowered stock; two locked expiries with too
  little stock (earliest expiry kept); untracked stock; an undated restock after
  a sold-out dated delivery raises no false alarm; a newer delivery expiring
  sooner; bread/yogurt/rice warning windows; the override; the expiry-day
  boundary (good on the day, expired the day after).
- **Reconcile output:** lock emitted once; sold-out closes emitted; nothing
  emitted for already-locked or closed batches.
- **Edit:** moving a locked delivery's date into the future clears the lock.
- **"Today":** midnight rollover and app resume update the date.
- **Cart:** add-to-cart limit is good stock; a line over good stock blocks
  checkout; "They're not expired" unblocks; voice/scan lines are blocked the
  same way; checkout waits for pending locks and stops if they fail.
- **Low stock** with expired units.
- **Restock retry:** same id twice adds stock and the delivery once; a changed
  restock gets a new id.
- **Reminder:** text for each of the 7 days; truncation ("+4 more"); after 9 AM
  starts tomorrow; sign-out cancels; language change reschedules.
- **SQL probes** on the live database in a rolled-back `DO` block (same method
  as 0010): restock with and without a date; restock replay; another shop's
  product rejected by the composite key; `remove_expired_stock` twice removes
  once; a removal at stock 0 writes no transaction; adjustment row positive with
  the batch's buying price; report RPCs unchanged.
- l10n parity.

## 10. Out of scope (v1)

Exact per-delivery sales, an "I still have N" correction, a loss-from-expiry
report screen (data is recorded for it), server push, and iOS-specific setup.

## 11. Edge-case review (2026-10-14)

After the first draft the spec was reviewed for edge cases. Each finding and
where it is now handled:

| # | Edge case | Handled in |
|---|---|---|
| 1 | Mistyped expiry date had no fix; a wrongly "expired" delivery stayed locked | §3.3 Edit (clears the lock), §5 |
| 2 | Past or far-future date entered by mistake | §5 Odd dates |
| 3 | New product with quantity 0 + expiry date fails the `quantity > 0` check | §5 field hidden at 0 |
| 4 | "Add expiry date" with `received_on` = today shrinks the shelf life and the warning | §3.3, §4.3 |
| 5 | Undated restock after a sold-out dated delivery revived it (false alarm) | §4.2 sold-out close |
| 6 | Expired deliveries that sold out showed "Expired: 0" and piled up | §4.2 sold-out close |
| 7 | Removal at stock 0 would write a 0-quantity adjustment | §3.2 step 5 |
| 8 | Two locked expiries with too little stock had no defined order | §4.1 step 2 |
| 9 | App open across midnight never moved "today" | §4.2 "Today" provider |
| 10 | Failed lock write followed by a sale shrank the expired count | §4.2 checkout awaits reconcile |
| 11 | Add-to-cart limit and voice hint used total stock | §5 Cart |
| 12 | After "Remove expired" a cart line could exceed stock | §5 Cart |
| 13 | An older app version on another phone can sell past the block | §4.2 known gaps |
| 14 | Low stock ignored expired units | §5 Low stock |
| 15 | Reminders continued after sign-out | §6 |
| 16 | Reminder text stayed in the old language | §6 |
| 17 | Scheduling after 9 AM | §6 |
| 18 | App update / restart dropped scheduled reminders | §6 receiver + reschedule on open |
| 19 | Many items overflow one notification | §6 "+N more" |
| 20 | Permission permanently denied | §5 Settings |
| 21 | Batch could reference another shop's product (RLS checks only `shop_id`) | §3 composite foreign key |
| 22 | Loss valued at the current buying price, not the delivery's | §3 `buying_price` on batch, §3.2 |
| 23 | Changing a product's unit left deliveries in the old unit | §5 unit change blocked |
| 24 | Restock retry after a lost reply added stock (and a delivery) twice | §3.1 retry-safe restock (user chose to include) |
