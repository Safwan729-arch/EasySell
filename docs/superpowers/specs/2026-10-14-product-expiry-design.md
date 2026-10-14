---
tags: [design, inventory, expiry, notifications]
---

# Product expiry dates and alerts — design

**Status:** design approved in conversation 2026-10-14; spec awaiting review.
Not built. Next step: implementation plan.

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

## 2. Decisions (all made with the user, 2026-10-14)

| Question | Decision | Why |
|---|---|---|
| How dates are stored | **A date per delivery**, estimated, not exact lot tracking | One date per product breaks on the first restock (overwrite → old stock unwarned; keep → false alarm on fresh stock). Exact lot tracking means every sale picks a delivery, which changes `record_sale_cart`, voice, scan and the offline plan. |
| How alerts reach the seller | **In-app + a daily phone reminder, built now** | User chose this knowing CLAUDE.md §1/§7 assign phone notifications to Member C. This feature's reminder is built here; record that ownership note. |
| When the warning starts | **Automatic from shelf life, with an optional per-product override** | A fixed window (e.g. 7 days) flags 5-day bread the moment it is added. User raised this case. |
| Expired stock vs sales | **Sales never count against expired stock by default** (user's idea) | Replaced the first proposal (a cart warning). Keeps the expired count correct when the shopkeeper sells before removing expired units. |
| Only expired stock left | **Block in the cart** with "Remove expired" and "They're not expired"; no "Sell anyway" | "Never sell expired by default." The second button is the escape hatch when the estimate is wrong. |

Rejected along the way:
- **Cart warning only** (my first suggestion): selling before removing expired
  units made the estimate assume an expired unit was sold.
- **"I still have N" correction on a delivery:** makes the estimate much harder
  to reason about. v1 offers only "None left" and "Remove from stock"; the
  product page lists deliveries so the shopkeeper can check.
- **Server push (FCM + `pg_cron`):** needs Firebase, a server job (`pg_cron`
  is not installed on the project) and Member C's area. Phone-scheduled
  reminders work offline and need no server.

## 3. Data (migration `0011_product_expiry.sql`)

### `product_batches` (new) — one row per delivery that has an expiry date

```
id            uuid primary key default gen_random_uuid()
shop_id       uuid not null references shops(id) on delete cascade
product_id    uuid not null references products(id) on delete cascade
quantity      numeric(10,3) not null check (quantity > 0)   -- amount received
received_on   date not null          -- phone's local date, see §3.3
expiry_date   date not null
expired_qty   numeric(10,3) check (expired_qty >= 0)        -- locked, §4.2
closed_at     timestamptz            -- null = open
closed_reason text check (closed_reason in ('removed','none_left','not_expired'))
created_at    timestamptz not null default now()
```

- RLS enabled, same shop-owner policy shape as `products` (CLAUDE.md §4).
- Index on `(shop_id, product_id) where closed_at is null`.
- No check that `expiry_date >= received_on`: "Add expiry date" to stock already
  on the shelf may legitimately enter a date that has passed.

### `products.expiry_warn_days` (new column)

`integer null check (expiry_warn_days >= 0)`. Null = automatic rule (§4.3).

### 3.1 `record_restock` gains an optional expiry date

New signature: `record_restock(p_shop_id, p_product_id, p_quantity, p_source,
p_expiry_date date default null, p_received_on date default null)`. When
`p_expiry_date` is set, the batch row is inserted **in the same transaction**
as the stock increase, so stock and delivery cannot disagree.

**Overload trap (same as 0006/0009/0010):** drop the old 4-argument signature
first, or PostgREST cannot pick one and every restock breaks.

### 3.2 `remove_expired_stock(p_shop_id, p_batch_id)` (new RPC)

1. Lock the batch row and the product row (`for update`).
2. If the batch is already closed, return without changing anything — a second
   tap or a retry after a lost reply must not remove stock twice (same lesson
   as [[2026-10-14-sale-cart-idempotent-design]]).
3. If `expired_qty` is null, raise "not expired" — removal only acts on a locked
   count.
4. `v_qty := least(expired_qty, product.quantity)`; decrement stock by `v_qty`.
5. Insert a `transactions` row: `type = 'adjustment'`, `quantity = v_qty`,
   **positive**, with frozen `buying_price`/`selling_price`, `source='manual'`.
   Convention: an `adjustment` row's quantity is **units removed**. It must be
   positive: `transactions_discount_within_line` (0009) checks
   `discount_amount <= selling_price * quantity`, which a negative quantity
   would fail. No `adjustment` rows exist yet (live: only `sale` and `restock`),
   so this sets the convention.
6. Close the batch: `closed_at = now()`, `closed_reason = 'removed'`.

Reports are unaffected: `get_dashboard_summary` and `get_sales_series` filter
`type = 'sale'` (checked in 0009). The rows keep the loss (`v_qty ×
buying_price`) for a later "loss from expiry" report.

### 3.3 Dates are the phone's local date

`received_on`, "today" and the expiry comparison all use the **phone's local
date**. The server's `current_date` is UTC: in Bangladesh (UTC+6) it is still
"yesterday" from midnight to 6 AM, which would shift a 5-day shelf life to 6
and move the warning. The app sends `p_received_on`; the server only falls back
to `current_date` for old callers.

### 3.4 Other writes (plain repository calls under RLS)

- **New product with an expiry date:** insert the product (as today), then
  insert the batch with `quantity` = starting stock. If the second insert
  fails, the product stays saved and the user is told to add the date from the
  product page. (No RPC: the product insert is already a client insert.)
- **"Add expiry date"** on the product page: inserts a batch. Quantity defaults
  to stock not covered by open batches; editable.
- **"None left" / "They're not expired":** close the batch with the matching
  `closed_reason`. "They're not expired" closes the *expired* delivery, so those
  units count as good stock again.
- **Locking `expired_qty`:** `update ... set expired_qty = X where id = ? and
  expired_qty is null`. The `is null` makes the first writer win if two phones
  race.

## 4. The estimate (pure Dart, `features/expiry/domain/`)

One pure function computes everything shown or blocked. It takes the product's
current stock `Q`, its open batches, the shop's warning setting and "today", and
returns per-batch estimated units left and status, plus the product's good and
expired counts. No database state is written except the lock in §4.2.

### 4.1 Allocation

1. `R = Q`.
2. **Locked expired batches first:** each takes `min(expired_qty, R)`. These are
   reserved, so sales never eat into them.
3. **All other open batches, newest received first** (`received_on` desc, then
   `created_at` desc): each takes `min(quantity, R)`. This is "older sells
   first": whatever is left over lands on the oldest deliveries.
4. Any `R` still left is **untracked** stock (no date) and counts as good.
   Untracked stock is therefore treated as the oldest, sold first. When an
   undated restock lands on top of an older dated delivery this is wrong, but
   on the safe side: the dated delivery keeps its full count and is
   over-warned rather than missed.

Because it reads only the current `Q`, it stays correct however stock changed:
cart sale, voice, scan, restock, or a quantity edited in the product form (which
writes no transaction).

### 4.2 Locking the expired count

A batch is **expired when today > expiry_date**. "Expires 20 Oct" is good
through 20 Oct.

When the estimate sees an expired batch with `expired_qty` null, its step-3
allocation is the count to lock, and the app writes it (§3.4). From then on step
2 reserves it.

Why this has to be stored: without it, the next sale lowers `Q` and step 3 would
quietly assign the shortfall to the oldest (expired) delivery, i.e. "the expired
bottle was sold". The lock is written the first time the app computes the
estimate after expiry. Every sale goes through the app, which computes the
estimate before showing the cart, so the lock lands before a sale can touch it.
Two known gaps, both accepted: a second phone selling in the window before the
first phone locks, and an app left open across midnight (mitigated by
recomputing on cart open).

`expired_qty` is capped by `Q` when read (stock can be edited down by hand).

### 4.3 Warning rule

- `shelf = expiry_date − received_on` in days.
- If `products.expiry_warn_days` is set, `w = expiry_warn_days`.
- Otherwise `w = min(shopSetting, max(1, floor(shelf / 3)))`, `shopSetting`
  default 7.
- Status: **expired** if today > expiry_date; **expiring soon** if today ≥
  expiry_date − w and estimated left > 0; otherwise **good**. A batch estimated
  at 0 and not expired raises no alert (shown as "sold" on the product page).

Worked examples (shopSetting 7): bread, shelf 5 → w 1 → warned the day before.
Yogurt, shelf 14 → w 4. Rice, shelf 365 → w 7.

### 4.4 Worked example (the user's Pepsi case)

Old delivery 5 (expired 20 Oct), new delivery 10 (expires 15 Dec), Q = 15.
On 21 Oct: step 3 gives new 10, old 5 → old locked at 5. Sell 3 → Q = 12:
step 2 reserves 5 expired, step 3 gives new 7. Home shows "Expired: 5 Pepsi".
"Remove from stock" → Q = 10, adjustment row of 5, old batch closed.

## 5. Screens

All new text in English and Bengali (`l10n_parity_test` enforces both).

- **Add-product form:** optional **Expiry date** under Quantity. **More
  options:** "Warn me __ days before" (empty = automatic).
- **Restock sheet:** optional **Expiry date**.
- **Product page:** **Deliveries** list — date added, expiry date, estimated
  left, status label (Good / Expiring soon / Expired / Sold). Expired rows:
  **Remove from stock**. All rows: **None left**. Plus **Add expiry date**.
- **Home:** **"Expiring & expired"** card beside Low stock ("Expired: 5 Pepsi",
  "Bread: 3 expire tomorrow"); tap → product page.
- **Bell:** lists the same items with a count badge, replacing the placeholder
  sheet in `dashboard_screen.dart` (`_showNotificationsSheet`).
- **Items tab:** **"Expiring"** filter beside "Low stock".
- **Cart:** a line whose quantity exceeds the product's **good** stock while
  expired units exist shows "Only 1 good Pepsi left (5 expired)" with **Remove
  expired** and **They're not expired**. Checkout is blocked until resolved.
  The rule lives in a provider that `CartCheckoutController` also checks
  (logic in controllers, CLAUDE.md §6), so voice and scan carts are covered too.
  A quantity above *total* stock still fails in `record_sale_cart` as today.
- **Settings:** "Warn me up to __ days before" (default 7) and a phone reminder
  on/off switch. Both stored on the phone (`shared_preferences`), like theme.

Archived products are excluded from every alert, filter and reminder.

## 6. Phone reminder

- Package `flutter_local_notifications` (+ `timezone`, `flutter_timezone` to
  schedule at local 9 AM).
- **One notification per day at 9 AM**, only on days with something to report,
  e.g. "Expired: 5 Pepsi · Bread: 3 expire tomorrow". Tap → the alerts list.
- Scheduled on the phone, so it works offline. On app open and whenever stock or
  deliveries change, cancel and reschedule the next **7 days**; each day's text
  comes from running §4 with that day as "today" (assuming no further sales).
- `AndroidScheduleMode.inexactAllowWhileIdle`: may arrive minutes late, but needs
  no exact-alarm permission. Android 14 no longer grants `SCHEDULE_EXACT_ALARM`
  by default, and a missing permission can throw from the plugin.
- `POST_NOTIFICATIONS` is requested once, the first time an expiry date is
  saved (Android 13+). Refusal leaves in-app alerts working.
- Android setup the plan must include: manifest permission, the plugin's boot
  receiver (reminders survive a restart), and core-library desugaring in
  `android/app/build.gradle`, which the plugin requires.
- **Limit:** not opening the app for more than 7 days lets reminders run out.
- **Ownership:** CLAUDE.md gives phone notifications to Member C; the user chose
  to build this one here (2026-10-14). Leave a `// MEMBER C` note at the
  scheduler seam so their wider notification work can absorb it.

## 7. What does not change

- `record_sale_cart`, checkout, voice sale, scan sale, the double-sale fix
  (0010).
- Reports and dashboard money figures (sales-only filters).
- Inventory value still counts expired units until removed — they are on hand.
- History lists sales only, so removals are not shown there; the product page's
  Deliveries list shows them.
- Products without any expiry date behave exactly as today.
- Offline-selling plan ([[2026-10-13-offline-selling-sync-design]]): the
  estimate runs on the phone from cached data, so it fits.

## 8. Deploy order

Apply `0011` **before** shipping the app. The new app calls `record_restock`
with `p_expiry_date` and reads `product_batches`; on a database without 0011,
restock fails and the new screens error. Old app builds keep working on the new
database (the new parameters default to null).

## 9. Testing

- Estimator unit tests: the Pepsi case (§4.4); sale before removal keeps 5
  expired; locked count capped by a hand-lowered stock; untracked stock; newer
  delivery expiring sooner; bread/yogurt/rice warning windows; override;
  expiry-day boundary (good on the day, expired the day after).
- Cart block: line over good stock blocks checkout; "They're not expired"
  unblocks; voice/scan lines are blocked the same way.
- Reminder text for each of the 7 scheduled days (pure function).
- SQL probes on the live database in a rolled-back `DO` block (same method as
  0010): restock with and without a date; `remove_expired_stock` twice removes
  once; adjustment row positive with frozen prices; reports unchanged.
- l10n parity.

## 10. Out of scope (v1)

Exact per-delivery sales, an "I still have N" correction, a loss-from-expiry
report screen (data is recorded for it), server push, iOS-specific setup, and
retry-safety for restock (separate known gap).
