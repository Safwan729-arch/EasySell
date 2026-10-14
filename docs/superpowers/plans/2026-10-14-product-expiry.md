# Product Expiry Dates and Alerts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let shopkeepers record an expiry date per delivery, warn them before stock expires (in the app and with a daily phone reminder), and never sell expired stock by default — without changing how a sale is recorded.

**Architecture:** A new `product_batches` table holds one row per dated delivery. A pure Dart estimator turns "current stock + open deliveries + today" into per-delivery estimates, good/expired counts and a list of *reconcile writes* (lock an expired count, close a sold-out delivery). Screens read the estimate from Riverpod providers; writes are computed only from a fresh server read (deliveries first, then stock), and checkout runs that reconcile before it records a sale. `record_sale_cart` is untouched; `record_restock` gains an optional expiry date and a phone-minted id for retry safety.

**Tech Stack:** Flutter / Dart, Riverpod 3 (`flutter_riverpod`), `go_router`, `supabase_flutter` (Postgres + RLS + RPC), `freezed` + `json_serializable`, `shared_preferences`, `clock`, `uuid`, `intl`; new: `flutter_local_notifications` ^19.4.0 and `timezone` ^0.10.0.

**Spec:** [docs/superpowers/specs/2026-10-14-product-expiry-design.md](../specs/2026-10-14-product-expiry-design.md) — read it first. Section numbers below (§3.1 etc.) refer to it.

## Global Constraints

- **Never change `record_sale_cart`**, checkout's RPC call, voice sale or scan sale logic. Expiry only adds a check *before* checkout and screens around it.
- **Dates are the phone's local date** (`dateOnly(clock.now())`), sent to the server as `yyyy-MM-dd`. Never rely on the server's `current_date` (UTC) except as a fallback for old callers.
- **"Expires 20 Oct" is good through 20 Oct**; a delivery is expired when `today > expiry_date`.
- **Warning rule:** `w = productOverride ?? min(shopWarnDays, max(1, floor(shelfDays / 3)))`, `shopWarnDays` default **7**, choices **3 / 7 / 14 / 30**; *expiring soon* when `daysBetween(today, expiry) <= w`.
- **Reconcile reads deliveries FIRST, then stock** (spec §4.2 and the "stale snapshot" note in Task 5). Screens may display from streams; *writes* are computed only from that fresh read.
- **An `adjustment` transaction's quantity is units removed and is always positive** (0009's `transactions_discount_within_line` check rejects a negative one).
- **Overload trap:** any migration that changes a function's argument list drops every earlier signature first.
- **Deploy order:** migration `0011` is applied to the live database **before** any build containing this feature is installed.
- **Supabase access:** do NOT use the Supabase MCP connector (user preference, token cost). Every database step is SQL the user pastes into the Supabase SQL editor; tell them the result to expect and wait for them to report it.
- **l10n:** every new user-visible string goes into BOTH `lib/l10n/app_en.arb` and `lib/l10n/app_bn.arb` (`test/l10n_parity_test.dart` enforces it), then run `flutter gen-l10n`. Values containing quantities/dates are passed as `String` placeholders so digits localise through `Qty.format` / `DateFormat`.
- **Formatting:** never run `dart format .` repo-wide (it reformats ~50 committed files). Format only the files you touched: `dart format <paths>`.
- **Daily reminder:** one notification per day at **09:00** local, next **7** days, ids **4100–4106**, `AndroidScheduleMode.inexactAllowWhileIdle` (no exact-alarm permission). Body lists at most **2** items then "+N more".
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Work on a feature branch `feat/product-expiry`, never directly on `main`.

## Review Focus

Conditions the spec implies but no spec-listed test pins; each now has a test in the owning task:

1. **A restock landing between the two reconcile reads** must never close a delivery that still has stock. Expected: reconcile fetches deliveries before products, so a stale read can only *over*-allocate old deliveries. Pinned in Task 5 (`reconcile reads deliveries before products`).
2. **Fractional stock (kg/litre) and float error** — 0.1 + 0.2 must not leave a 0.0000001 remainder that keeps a delivery open, nor a 0.0999999 that closes one. Expected: everything rounded to 3 decimals. Pinned in Task 3 (`fractional stock does not trip float error`).
3. **Checkout with no signal** must report "no internet", not "expired stock", and must not record the sale. Pinned in Task 9 (`a failed expiry check stops checkout with that failure`).
4. **A per-product warning of 0 days** warns on the expiry day only. Pinned in Task 3 (`override of 0 warns on the expiry day only`).
5. **Bengali** alert and reminder text uses Bengali digits and wording. Pinned in Task 10 (`alert text is Bengali in bn`) and Task 11 (`reminder text follows the app language`).

---

## File Structure

**Create**
- `supabase/migrations/0011_product_expiry.sql` — table, RLS, composite key, `record_restock` (dated + retry-safe), `remove_expired_stock`.
- `lib/features/expiry/domain/expiry_dates.dart` — `dateOnly`, `daysBetween`, `ymd`, `OddDate`, `classifyExpiryDate`.
- `lib/features/expiry/domain/product_batch.dart` — `ProductBatch` (freezed) + `BatchCloseReason`.
- `lib/features/expiry/domain/expiry_estimate.dart` — estimator, `warningDays`, `estimateAll`, `goodStockOf`, `applyReconcileWrites`, `round3`.
- `lib/features/expiry/domain/expiry_alerts.dart` — `ExpiryAlert`, `buildExpiryAlerts`.
- `lib/features/expiry/domain/cart_expiry.dart` — cart line notices + blocked product ids.
- `lib/features/expiry/domain/reminder_plan.dart` — 7-day reminder planner + body builder.
- `lib/features/expiry/data/batch_repository.dart` — Supabase access for deliveries.
- `lib/features/expiry/data/reminder_service.dart` — notification service interface + local implementation + no-op.
- `lib/features/expiry/presentation/expiry_prefs.dart` — warn days / reminder switch / permission-asked (shared_preferences).
- `lib/features/expiry/presentation/today_provider.dart` — `nowProvider`, `todayProvider`.
- `lib/features/expiry/presentation/expiry_providers.dart` — streams, estimate map, good stock, alerts, closed deliveries, auto-reconcile keeper.
- `lib/features/expiry/presentation/expiry_reconciler.dart` — fresh-read reconcile.
- `lib/features/expiry/presentation/expiry_gate.dart` — checkout gate.
- `lib/features/expiry/presentation/batch_actions_controller.dart` — add / edit / none left / not expired / remove.
- `lib/features/expiry/presentation/expiry_date_field.dart` — date field + odd-date confirm + formatter.
- `lib/features/expiry/presentation/batch_form_sheet.dart` — add/edit a delivery.
- `lib/features/expiry/presentation/deliveries_section.dart` — product page section.
- `lib/features/expiry/presentation/expiry_text.dart` — alert sentence builder (shared by screens and reminders).
- `lib/features/expiry/presentation/expiry_alerts_card.dart` — Home card.
- `lib/features/expiry/presentation/expiry_alerts_screen.dart` — the bell's list.
- `lib/features/expiry/presentation/reminder_sync.dart` — schedules reminders, routes taps.
- `lib/features/expiry/presentation/expiry_settings_tiles.dart` — Settings tiles.
- Tests: `test/expiry_dates_test.dart`, `test/product_batch_test.dart`, `test/expiry_estimate_test.dart`, `test/expiry_alerts_test.dart`, `test/cart_expiry_test.dart`, `test/expiry_prefs_test.dart`, `test/today_provider_test.dart`, `test/expiry_reconciler_test.dart`, `test/expiry_gate_test.dart`, `test/restock_idempotency_test.dart`, `test/inventory_save_expiry_test.dart`, `test/batch_actions_controller_test.dart`, `test/cart_checkout_expiry_test.dart`, `test/expiry_text_test.dart`, `test/reminder_plan_test.dart`, `test/reminder_sync_test.dart`, `test/inventory_totals_expiry_test.dart`, `test/widgets/expiry_date_field_test.dart`, `test/widgets/deliveries_section_test.dart`, `test/widgets/expiry_settings_tiles_test.dart`.

**Modify**
- `lib/features/inventory/domain/product.dart` — `expiryWarnDays`, `isLowStockAt`.
- `lib/features/inventory/data/product_repository.dart` — `fetchActiveProducts`.
- `lib/features/inventory/domain/inventory_totals.dart` — low count from good stock.
- `lib/features/inventory/presentation/inventory_controller.dart` — save outcome + first delivery.
- `lib/features/inventory/presentation/product_form_screen.dart` — expiry field, warn-days override, unit guard.
- `lib/features/inventory/presentation/product_detail_screen.dart` — deliveries section, low stock from good stock.
- `lib/features/inventory/presentation/inventory_list_screen.dart` — "Expiring" filter, good-stock low filter.
- `lib/features/transactions/data/transaction_repository.dart` — new `recordRestock`.
- `lib/features/transactions/presentation/transaction_controller.dart` — restock id + expiry.
- `lib/features/transactions/presentation/transaction_confirmation_sheet.dart` — expiry date on restock.
- `lib/features/cart/domain/cart_math.dart`, `lib/features/cart/presentation/cart_controller.dart` — good-stock limit.
- `lib/features/cart/presentation/add_to_cart_sheet.dart`, `cart_screen.dart`, `cart_checkout_controller.dart` — notices, block, gate.
- `lib/features/voice/presentation/voice_review_sheet.dart` — low-stock hint from good stock.
- `lib/features/dashboard/presentation/dashboard_screen.dart` — card, bell badge, good-stock low list.
- `lib/features/settings/presentation/settings_screen.dart` — Expiry section.
- `lib/core/error/failure.dart`, `lib/core/l10n/failure_text.dart` — `expiredStockInCart`.
- `lib/core/router/app_router.dart` — `/alerts`.
- `lib/app.dart`, `lib/main.dart` — keepers, prefs seeding, reminder service.
- `android/app/build.gradle.kts`, `android/app/src/main/AndroidManifest.xml` — notification setup.
- `pubspec.yaml` — two packages.
- `test/support/cart_harness.dart`, `test/cart_checkout_guard_test.dart` — stub the expiry gate.
- `lib/l10n/app_en.arb`, `lib/l10n/app_bn.arb` (+ regenerated `app_localizations*.dart`).
- `docs/00-Map.md`, the spec's status line.

---

### Task 0: Branch

- [ ] **Step 1: Create the feature branch**

```bash
git checkout -b feat/product-expiry
```

Expected: `Switched to a new branch 'feat/product-expiry'`. Leave the user's uncommitted files (`.gitignore`, `docs/business/`, `new design/`, the offline design doc, their map lines) alone — never stage them.

---

### Task 1: Migration 0011 (database)

**Files:**
- Create: `supabase/migrations/0011_product_expiry.sql`

**Interfaces:**
- Produces (SQL): table `product_batches`; column `products.expiry_warn_days`; `record_restock(p_shop_id uuid, p_product_id uuid, p_quantity numeric, p_source text default 'manual', p_expiry_date date default null, p_received_on date default null, p_restock_id uuid default null) returns transactions`; `remove_expired_stock(p_shop_id uuid, p_batch_id uuid) returns product_batches`.

- [ ] **Step 1: Write the migration file**

```sql
-- =============================================================================
-- 0011_product_expiry.sql — expiry dates per delivery, retry-safe restock.
-- Run AFTER 0010_sale_cart_idempotent.sql (Dashboard SQL Editor -> paste -> Run).
-- Idempotent (safe to re-run).
--
-- Design: docs/superpowers/specs/2026-10-14-product-expiry-design.md
--
-- product_batches holds one row per delivery that has an expiry date. The app
-- ESTIMATES how much of each delivery is left from the product's current stock
-- (older sells first), so record_sale_cart is untouched. Two kinds of write
-- come back from the app: lock an expired count (expired_qty) and close a
-- delivery as sold out. Both are plain RLS-scoped updates.
--
-- OVERLOAD WARNING (same trap as 0006/0009/0010): record_restock's argument
-- list changes, so every earlier signature is dropped first or PostgREST could
-- no longer pick one -- silently breaking restock.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- products: a composite-key target, and the per-product warning override.
-- ---------------------------------------------------------------------------
-- RLS on product_batches checks shop_id on the batch row only. With a plain
-- product_id foreign key a row could carry the caller's shop_id and another
-- shop's product_id. Referencing (id, shop_id) makes the database refuse it.
-- id is already the primary key, so this unique constraint cannot fail.
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'products_id_shop_unique') then
    alter table products add constraint products_id_shop_unique unique (id, shop_id);
  end if;
end $$;

alter table products add column if not exists expiry_warn_days integer;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'products_expiry_warn_days_non_negative'
  ) then
    alter table products
      add constraint products_expiry_warn_days_non_negative
      check (expiry_warn_days >= 0);
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- product_batches
-- ---------------------------------------------------------------------------
create table if not exists product_batches (
  id            uuid primary key default gen_random_uuid(),
  shop_id       uuid not null references shops(id) on delete cascade,
  product_id    uuid not null,
  quantity      numeric(10,3) not null check (quantity > 0),
  -- Frozen at delivery: the loss on removal is valued at what was paid for
  -- THIS delivery, not at today's price.
  buying_price  numeric(10,2) not null default 0,
  -- The phone's local date. The server's current_date is UTC, which in
  -- Bangladesh is still "yesterday" until 6 AM.
  received_on   date not null,
  expiry_date   date not null,
  -- Locked by the app the first time it sees the delivery expired; from then
  -- on sales are never counted against these units.
  expired_qty   numeric(10,3) check (expired_qty >= 0),
  closed_at     timestamptz,
  closed_reason text check (closed_reason in
                  ('removed', 'none_left', 'not_expired', 'sold_out')),
  created_at    timestamptz not null default now(),
  constraint product_batches_product_same_shop
    foreign key (product_id, shop_id) references products (id, shop_id)
    on delete cascade
);

create index if not exists idx_product_batches_open
  on product_batches (shop_id, product_id) where closed_at is null;

alter table product_batches enable row level security;

drop policy if exists "shop members read/write own product batches" on product_batches;
create policy "shop members read/write own product batches"
  on product_batches for all
  using (shop_id in (select id from shops where owner_id = auth.uid()))
  with check (shop_id in (select id from shops where owner_id = auth.uid()));

-- ---------------------------------------------------------------------------
-- record_restock: optional expiry date, and retry-safe.
-- ---------------------------------------------------------------------------
-- A lost reply plus a retry used to add the stock twice. The phone now mints
-- p_restock_id and re-sends it on a retry; the transaction row is inserted with
-- that id, so a repeat finds it and returns it without changing anything (the
-- 0010 method). The integer-quantity signature from 0001 is dropped too, in
-- case 0003's numeric version was created beside it rather than over it.
drop function if exists record_restock(uuid, uuid, integer, text);
drop function if exists record_restock(uuid, uuid, numeric, text);
drop function if exists record_restock(uuid, uuid, numeric, text, date, date, uuid);

create function record_restock(
  p_shop_id      uuid,
  p_product_id   uuid,
  p_quantity     numeric,
  p_source       text default 'manual',
  p_expiry_date  date default null,
  p_received_on  date default null,
  p_restock_id   uuid default null
) returns transactions
language plpgsql
as $$
declare
  v_id      uuid := coalesce(p_restock_id, gen_random_uuid());
  v_product products;
  v_txn     transactions;
begin
  -- Serialise calls with the same id so two overlapping retries cannot both
  -- miss the row below and both insert.
  perform pg_advisory_xact_lock(hashtextextended(v_id::text, 0));

  select * into v_txn from transactions
    where id = v_id and shop_id = p_shop_id;
  if found then
    return v_txn;
  end if;

  if p_quantity is null or p_quantity <= 0 then
    raise exception 'Quantity must be greater than zero';
  end if;

  select * into v_product from products
    where id = p_product_id and shop_id = p_shop_id
    for update;

  if v_product is null then
    raise exception 'Product not found';
  end if;

  update products set quantity = quantity + p_quantity, updated_at = now()
    where id = p_product_id;

  insert into transactions(id, shop_id, product_id, type, quantity,
                           buying_price, selling_price, source)
  values (v_id, p_shop_id, p_product_id, 'restock', p_quantity,
          v_product.buying_price, v_product.selling_price, p_source)
  returning * into v_txn;

  -- Same transaction as the stock change: stock, transaction and delivery
  -- commit together or not at all.
  if p_expiry_date is not null then
    insert into product_batches(shop_id, product_id, quantity, buying_price,
                                received_on, expiry_date)
    values (p_shop_id, p_product_id, p_quantity, v_product.buying_price,
            coalesce(p_received_on, current_date), p_expiry_date);
  end if;

  return v_txn;
end;
$$;

-- ---------------------------------------------------------------------------
-- remove_expired_stock: throw away a delivery's expired units.
-- ---------------------------------------------------------------------------
drop function if exists remove_expired_stock(uuid, uuid);

create function remove_expired_stock(
  p_shop_id  uuid,
  p_batch_id uuid
) returns product_batches
language plpgsql
as $$
declare
  v_batch   product_batches;
  v_product products;
  v_qty     numeric;
begin
  select * into v_batch from product_batches
    where id = p_batch_id and shop_id = p_shop_id
    for update;
  if not found then
    raise exception 'Delivery not found';
  end if;

  -- Already closed: a second tap, or a retry after a lost reply. Change
  -- nothing, so stock is never removed twice.
  if v_batch.closed_at is not null then
    return v_batch;
  end if;

  if v_batch.expired_qty is null then
    raise exception 'Delivery is not expired';
  end if;

  select * into v_product from products
    where id = v_batch.product_id and shop_id = p_shop_id
    for update;
  if not found then
    raise exception 'Product not found';
  end if;

  -- Stock may have been lowered by hand below the locked count.
  v_qty := least(v_batch.expired_qty, v_product.quantity);

  if v_qty > 0 then
    update products set quantity = quantity - v_qty, updated_at = now()
      where id = v_product.id;

    -- quantity is units REMOVED and must be positive:
    -- transactions_discount_within_line (0009) checks
    -- discount_amount <= selling_price * quantity, which a negative fails.
    -- Every report filters type = 'sale', so this row moves no money figure.
    insert into transactions(shop_id, product_id, type, quantity,
                             buying_price, selling_price, source)
    values (p_shop_id, v_product.id, 'adjustment', v_qty,
            v_batch.buying_price, v_product.selling_price, 'manual');
  end if;

  update product_batches
    set closed_at = now(), closed_reason = 'removed'
    where id = p_batch_id
    returning * into v_batch;

  return v_batch;
end;
$$;
```

- [ ] **Step 2: Commit the migration**

```bash
git add supabase/migrations/0011_product_expiry.sql
git commit -m "feat(expiry): migration 0011 for deliveries, retry-safe restock, expired removal

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 3: Ask the user to apply it**

Tell the user: "Please paste the whole of `supabase/migrations/0011_product_expiry.sql` into the Supabase SQL editor and click Run. Expected: `Success. No rows returned`." Wait for confirmation.

- [ ] **Step 4: Ask the user to run the rolled-back probe**

Give the user this block to paste. It ends in `raise exception`, so **everything rolls back** and the message carries the results.

```sql
do $t$
declare
  v_p      products;
  v_other  uuid;
  v_id     uuid := gen_random_uuid();
  r        transactions;
  s0 numeric; s1 numeric; s2 numeric; s3 numeric; s4 numeric;
  n_batches int; n_txn int; n_adj int;
  v_b      product_batches;
  v_done   product_batches;
  fk_ok    boolean := false;
begin
  select * into v_p from products
    where quantity >= 3 and not is_archived
    order by updated_at desc limit 1;
  select id into v_other from shops where id <> v_p.shop_id limit 1;
  s0 := v_p.quantity;

  -- dated restock, then the SAME id again (a retry)
  r := record_restock(v_p.shop_id, v_p.id, 2, 'manual', current_date + 10, current_date, v_id);
  select quantity into s1 from products where id = v_p.id;
  r := record_restock(v_p.shop_id, v_p.id, 2, 'manual', current_date + 10, current_date, v_id);
  select quantity into s2 from products where id = v_p.id;
  select count(*) into n_batches from product_batches
    where product_id = v_p.id and closed_at is null;
  select count(*) into n_txn from transactions where id = v_id;

  -- make the new delivery look expired and locked at 2, then remove twice
  select * into v_b from product_batches
    where product_id = v_p.id and closed_at is null
    order by created_at desc limit 1;
  update product_batches set expiry_date = current_date - 1, expired_qty = 2
    where id = v_b.id;
  v_done := remove_expired_stock(v_p.shop_id, v_b.id);
  select quantity into s3 from products where id = v_p.id;
  v_done := remove_expired_stock(v_p.shop_id, v_b.id);
  select quantity into s4 from products where id = v_p.id;
  select count(*) into n_adj from transactions
    where product_id = v_p.id and type = 'adjustment' and created_at = now();

  -- a delivery pointing at another shop's product must be refused
  begin
    insert into product_batches(shop_id, product_id, quantity, received_on, expiry_date)
    values (v_other, v_p.id, 1, current_date, current_date + 5);
  exception when foreign_key_violation then
    fk_ok := true;
  end;

  raise exception 'PROBE stock % -> % -> % -> % -> % | open_batches=% restock_rows=% adjustments=% reason=% cross_shop_rejected=%',
    s0, s1, s2, s3, s4, n_batches, n_txn, n_adj, v_done.closed_reason, fk_ok;
end
$t$;
```

Expected error text (with `S` = the product's starting stock): `PROBE stock S -> S+2 -> S+2 -> S -> S | open_batches=1 restock_rows=1 adjustments=1 reason=removed cross_shop_rejected=t`. (`open_batches` is 1 only if the product had no open deliveries before, which is true on first apply.) If any value differs, stop and fix the migration before Task 2.

---
### Task 2: Date helpers, `ProductBatch`, `Product.expiryWarnDays`

**Files:**
- Create: `lib/features/expiry/domain/expiry_dates.dart`, `lib/features/expiry/domain/product_batch.dart`
- Modify: `lib/features/inventory/domain/product.dart`
- Test: `test/expiry_dates_test.dart`, `test/product_batch_test.dart`

**Interfaces:**
- Produces: `DateTime dateOnly(DateTime)`, `int daysBetween(DateTime from, DateTime to)`, `String ymd(DateTime)`, `enum OddDate { none, past, farFuture }`, `OddDate classifyExpiryDate(DateTime picked, DateTime today)`; `ProductBatch` (fields `id, shopId, productId, quantity, buyingPrice, receivedOn, expiryDate, expiredQty?, closedAt?, closedReason?, createdAt?`, getter `isOpen`); `BatchCloseReason.removed/noneLeft/notExpired/soldOut`; `Product.expiryWarnDays` (`int?`), `Product.isLowStockAt(double available)`.

- [ ] **Step 1: Write the failing tests**

`test/expiry_dates_test.dart`:

```dart
import 'package:ai_shopkeeper/features/expiry/domain/expiry_dates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dateOnly drops the time of day', () {
    expect(dateOnly(DateTime(2026, 10, 20, 23, 59)), DateTime(2026, 10, 20));
  });

  test('daysBetween counts calendar days and can be negative', () {
    expect(daysBetween(DateTime(2026, 10, 13), DateTime(2026, 10, 18)), 5);
    expect(daysBetween(DateTime(2026, 10, 18, 23), DateTime(2026, 10, 19, 1)), 1);
    expect(daysBetween(DateTime(2026, 10, 20), DateTime(2026, 10, 18)), -2);
  });

  test('ymd is the Postgres date wire format', () {
    expect(ymd(DateTime(2026, 1, 5)), '2026-01-05');
  });

  group('classifyExpiryDate', () {
    final today = DateTime(2026, 10, 14);
    test('a past date is flagged', () {
      expect(classifyExpiryDate(DateTime(2026, 10, 13), today), OddDate.past);
    });
    test('today and the near future are fine', () {
      expect(classifyExpiryDate(today, today), OddDate.none);
      expect(classifyExpiryDate(DateTime(2031, 10, 14), today), OddDate.none);
    });
    test('more than five years ahead is flagged', () {
      expect(classifyExpiryDate(DateTime(2031, 10, 15), today), OddDate.farFuture);
    });
  });
}
```

`test/product_batch_test.dart`:

```dart
import 'package:ai_shopkeeper/features/expiry/domain/product_batch.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ProductBatch reads a product_batches row', () {
    final b = ProductBatch.fromJson({
      'id': 'b1',
      'shop_id': 's1',
      'product_id': 'p1',
      'quantity': 5,
      'buying_price': 30.5,
      'received_on': '2026-10-01',
      'expiry_date': '2026-10-20',
      'expired_qty': null,
      'closed_at': null,
      'closed_reason': null,
      'created_at': '2026-10-01T04:00:00Z',
    });
    expect(b.quantity, 5.0);
    expect(b.receivedOn, DateTime(2026, 10, 1));
    expect(b.expiryDate, DateTime(2026, 10, 20));
    expect(b.isOpen, isTrue);
  });

  test('Product carries the expiry warning override both ways', () {
    final p = Product.fromJson({
      'id': 'p1',
      'shop_id': 's1',
      'name': 'Bread',
      'expiry_warn_days': 1,
    });
    expect(p.expiryWarnDays, 1);
    expect(p.toRow()['expiry_warn_days'], 1);
    expect(p.copyWith(expiryWarnDays: null).toRow()['expiry_warn_days'], isNull);
  });

  test('isLowStockAt judges a given amount, isLowStock the whole stock', () {
    const p = Product(
      id: 'p1',
      shopId: 's1',
      name: 'Pepsi',
      quantity: 6,
      reorderThreshold: 3,
    );
    expect(p.isLowStock, isFalse);
    expect(p.isLowStockAt(1), isTrue);
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/expiry_dates_test.dart test/product_batch_test.dart`
Expected: compile errors — `expiry_dates.dart` / `product_batch.dart` not found, `expiryWarnDays` / `isLowStockAt` undefined.

- [ ] **Step 3: Write `expiry_dates.dart`**

```dart
/// Local calendar-date helpers for the expiry feature.
///
/// Every date here is the PHONE's local date (spec §3.4). The server's
/// `current_date` is UTC, which in Bangladesh (UTC+6) is still "yesterday"
/// from midnight to 6 AM -- that would stretch a 5-day shelf life to 6 and move
/// the warning a day.
library;

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Whole calendar days from [from] to [to]; negative when [to] is earlier.
/// Done in UTC so a daylight-saving change can never make a day 23 hours.
int daysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays;

/// `yyyy-MM-dd`, the wire format of a Postgres `date`.
String ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

enum OddDate { none, past, farFuture }

/// Flags an expiry date worth a second look (spec §5 "Odd dates"): one that
/// has already passed, or one more than five years ahead (a mistyped year).
/// Both are still allowed -- the UI only asks for confirmation.
OddDate classifyExpiryDate(DateTime picked, DateTime today) {
  final p = dateOnly(picked);
  final t = dateOnly(today);
  if (p.isBefore(t)) return OddDate.past;
  if (p.isAfter(DateTime(t.year + 5, t.month, t.day))) return OddDate.farFuture;
  return OddDate.none;
}
```

- [ ] **Step 4: Write `product_batch.dart`**

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'product_batch.freezed.dart';
part 'product_batch.g.dart';

/// `product_batches.closed_reason` values (CHECK constraint in 0011).
abstract final class BatchCloseReason {
  static const removed = 'removed';
  static const noneLeft = 'none_left';
  static const notExpired = 'not_expired';
  static const soldOut = 'sold_out';
}

/// One delivery that has an expiry date. How much of it is LEFT is never
/// stored -- it is estimated from the product's current stock (see
/// `expiry_estimate.dart`), so sales never have to know about deliveries.
///
/// `receivedOn` / `expiryDate` are Postgres `date`s: `DateTime.parse` reads
/// "2026-10-20" as local midnight, which is exactly the local calendar date.
@freezed
abstract class ProductBatch with _$ProductBatch {
  const ProductBatch._();

  const factory ProductBatch({
    required String id,
    required String shopId,
    required String productId,
    required double quantity,
    @Default(0) double buyingPrice,
    required DateTime receivedOn,
    required DateTime expiryDate,
    // Locked the first time the app sees this delivery expired; from then on
    // sales are never counted against these units (spec §4.2).
    double? expiredQty,
    DateTime? closedAt,
    String? closedReason,
    DateTime? createdAt,
  }) = _ProductBatch;

  factory ProductBatch.fromJson(Map<String, dynamic> json) =>
      _$ProductBatchFromJson(json);

  bool get isOpen => closedAt == null;
}
```

- [ ] **Step 5: Add the override and `isLowStockAt` to `Product`**

In `lib/features/inventory/domain/product.dart`, add the field after `reorderThreshold`:

```dart
    // Expressed in the same unit as quantity.
    @Default(0) double reorderThreshold,
    // "Warn me N days before expiry" for this product. Null = the automatic
    // shelf-life rule (expiry spec §4.3).
    int? expiryWarnDays,
```

Replace the `isLowStock` getter with:

```dart
  /// At or below the reorder threshold (threshold of 0 disables the alert).
  bool get isLowStock => isLowStockAt(quantity);

  /// Low-stock check against a given amount -- the GOOD (unexpired) stock when
  /// the product has expired units, so 5 expired + 1 good counts as low.
  bool isLowStockAt(double available) =>
      reorderThreshold > 0 && available <= reorderThreshold;
```

In `toRow()`, after `'reorder_threshold': reorderThreshold,` add:

```dart
    'expiry_warn_days': expiryWarnDays,
```

- [ ] **Step 6: Run codegen**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: completes, creating `product_batch.freezed.dart` / `product_batch.g.dart` and updating `product.freezed.dart` / `product.g.dart`.

- [ ] **Step 7: Run the tests to verify they pass**

Run: `flutter test test/expiry_dates_test.dart test/product_batch_test.dart`
Expected: all pass.

- [ ] **Step 8: Commit**

```bash
git add lib/features/expiry/domain/ lib/features/inventory/domain/product.dart lib/features/inventory/domain/product.freezed.dart lib/features/inventory/domain/product.g.dart test/expiry_dates_test.dart test/product_batch_test.dart
git commit -m "feat(expiry): date helpers, ProductBatch model, product warning override

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: The estimator, alerts and cart notices (pure Dart)

**Files:**
- Create: `lib/features/expiry/domain/expiry_estimate.dart`, `lib/features/expiry/domain/expiry_alerts.dart`, `lib/features/expiry/domain/cart_expiry.dart`
- Test: `test/expiry_estimate_test.dart`, `test/expiry_alerts_test.dart`, `test/cart_expiry_test.dart`

**Interfaces:**
- Consumes: `ProductBatch`, `dateOnly`, `daysBetween` (Task 2); `Product`; `CartLine` (`lib/features/cart/domain/cart_line.dart`, fields `product`, `quantity`).
- Produces:
  - `enum BatchStatus { good, expiringSoon, expired, soldOut }`
  - `sealed class ReconcileWrite { String batchId }`, `LockExpired(String batchId, double quantity)`, `CloseSoldOut(String batchId)` (value equality)
  - `class BatchEstimate { ProductBatch batch; double left; BatchStatus status; int warnDays }`
  - `class ProductExpiry { String productId; double stock, good, expired; List<BatchEstimate> batches; List<ReconcileWrite> writes; Iterable<BatchEstimate> expiredWithStock; Iterable<BatchEstimate> expiringSoon }`
  - `double round3(double)`, `int warningDays({required DateTime receivedOn, required DateTime expiryDate, required int shopWarnDays, int? productWarnDays})`
  - `ProductExpiry estimateProductExpiry({required String productId, required double stock, required List<ProductBatch> openBatches, required DateTime today, required int shopWarnDays, int? productWarnDays})`
  - `Map<String, ProductExpiry> estimateAll({required List<Product> products, required List<ProductBatch> openBatches, required DateTime today, required int shopWarnDays})`
  - `double goodStockOf(Product p, Map<String, ProductExpiry> byProduct)`
  - `List<ProductBatch> applyReconcileWrites(List<ProductBatch>, List<ReconcileWrite>)`
  - `enum ExpiryAlertKind { expired, expiringSoon }`, `class ExpiryAlert { Product product; ExpiryAlertKind kind; double quantity; DateTime expiryDate; int daysLeft }`, `List<ExpiryAlert> buildExpiryAlerts({required List<Product> products, required Map<String, ProductExpiry> byProduct, required DateTime today})`
  - `sealed class CartLineNotice`, `ExpiredStockNotice({double good, double expired, List<String> expiredBatchIds})`, `OverStockNotice(double stock)`, `Map<String, CartLineNotice> cartLineNotices({required List<CartLine> lines, required Map<String, Product> liveProducts, required Map<String, ProductExpiry> byProduct})`, `List<String> expiredBlockedProductIds(List<CartLine> lines, Map<String, ProductExpiry> byProduct)`

- [ ] **Step 1: Write the failing estimator tests**

`test/expiry_estimate_test.dart`:

```dart
import 'package:ai_shopkeeper/features/expiry/domain/expiry_estimate.dart';
import 'package:ai_shopkeeper/features/expiry/domain/product_batch.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:flutter_test/flutter_test.dart';

ProductBatch b(
  String id, {
  required double qty,
  required DateTime received,
  required DateTime expiry,
  double? locked,
  DateTime? created,
}) => ProductBatch(
  id: id,
  shopId: 's1',
  productId: 'p1',
  quantity: qty,
  receivedOn: received,
  expiryDate: expiry,
  expiredQty: locked,
  createdAt: created ?? received,
);

ProductExpiry est(
  double stock,
  List<ProductBatch> batches,
  DateTime today, {
  int shopWarnDays = 7,
  int? override,
}) => estimateProductExpiry(
  productId: 'p1',
  stock: stock,
  openBatches: batches,
  today: today,
  shopWarnDays: shopWarnDays,
  productWarnDays: override,
);

BatchEstimate of(ProductExpiry e, String id) =>
    e.batches.firstWhere((x) => x.batch.id == id);

void main() {
  final oldPepsi = b(
    'old',
    qty: 5,
    received: DateTime(2026, 10, 1),
    expiry: DateTime(2026, 10, 20),
  );
  final newPepsi = b(
    'new',
    qty: 10,
    received: DateTime(2026, 10, 10),
    expiry: DateTime(2026, 12, 15),
  );

  group('the Pepsi case (spec §4.4)', () {
    test('on 21 Oct the old delivery is expired and gets locked at 5', () {
      final e = est(15, [oldPepsi, newPepsi], DateTime(2026, 10, 21));
      expect(of(e, 'old').left, 5);
      expect(of(e, 'old').status, BatchStatus.expired);
      expect(of(e, 'new').left, 10);
      expect(e.good, 10);
      expect(e.expired, 5);
      expect(e.writes, [const LockExpired('old', 5)]);
    });

    test('a sale before removal is counted against good stock only', () {
      final locked = oldPepsi.copyWith(expiredQty: 5);
      final e = est(12, [locked, newPepsi], DateTime(2026, 10, 21));
      expect(of(e, 'old').left, 5);
      expect(of(e, 'new').left, 7);
      expect(e.good, 7);
      expect(e.expired, 5);
      expect(e.writes, isEmpty);
    });
  });

  test('a lock is capped by stock lowered by hand', () {
    final e = est(3, [oldPepsi.copyWith(expiredQty: 5)], DateTime(2026, 10, 21));
    expect(e.expired, 3);
    expect(e.good, 0);
  });

  test('two locked expiries with too little stock keep the earliest', () {
    final a = b('a', qty: 4, received: DateTime(2026, 10, 1), expiry: DateTime(2026, 10, 18), locked: 4);
    final c = b('c', qty: 3, received: DateTime(2026, 10, 2), expiry: DateTime(2026, 10, 19), locked: 3);
    final e = est(5, [c, a], DateTime(2026, 10, 21));
    expect(of(e, 'a').left, 4);
    expect(of(e, 'c').left, 1);
  });

  test('stock beyond the deliveries is untracked and good', () {
    final e = est(20, [newPepsi], DateTime(2026, 10, 21));
    expect(of(e, 'new').left, 10);
    expect(e.good, 20);
    expect(e.expired, 0);
  });

  test('older deliveries are sold first', () {
    final e = est(12, [oldPepsi, newPepsi], DateTime(2026, 10, 15));
    expect(of(e, 'new').left, 10);
    expect(of(e, 'old').left, 2);
  });

  test('a sold-out delivery is closed so an undated restock cannot revive it', () {
    final bread = b('mon', qty: 10, received: DateTime(2026, 10, 13), expiry: DateTime(2026, 10, 18));
    final soldOut = est(0, [bread], DateTime(2026, 10, 15));
    expect(of(soldOut, 'mon').status, BatchStatus.soldOut);
    expect(soldOut.writes, [const CloseSoldOut('mon')]);

    // After the close is applied, 10 undated loaves raise nothing.
    final after = applyReconcileWrites([bread], soldOut.writes);
    const product = Product(id: 'p1', shopId: 's1', name: 'Bread', quantity: 10);
    final map = estimateAll(
      products: [product],
      openBatches: after,
      today: DateTime(2026, 10, 19),
      shopWarnDays: 7,
    );
    expect(map, isEmpty);
  });

  test('an expired delivery that sold out first is closed, not shown as expired 0', () {
    final e = est(10, [oldPepsi, newPepsi], DateTime(2026, 10, 21));
    expect(of(e, 'old').status, BatchStatus.soldOut);
    expect(e.writes, [const CloseSoldOut('old')]);
    expect(e.expired, 0);
  });

  test('a newer delivery that expires sooner is warned on its own date', () {
    final longLife = b('long', qty: 10, received: DateTime(2026, 10, 1), expiry: DateTime(2026, 12, 30));
    final shortLife = b('short', qty: 10, received: DateTime(2026, 10, 10), expiry: DateTime(2026, 10, 25));
    final e = est(15, [longLife, shortLife], DateTime(2026, 10, 22));
    expect(of(e, 'short').left, 10);
    expect(of(e, 'short').status, BatchStatus.expiringSoon);
    expect(of(e, 'long').left, 5);
    expect(of(e, 'long').status, BatchStatus.good);
  });

  group('warning window (spec §4.3)', () {
    // Bread added Monday 13 Oct, expires Saturday 18 Oct: shelf 5 -> w 1.
    final bread = b('bread', qty: 10, received: DateTime(2026, 10, 13), expiry: DateTime(2026, 10, 18));

    test('bread is good two days out', () {
      expect(of(est(10, [bread], DateTime(2026, 10, 16)), 'bread').status, BatchStatus.good);
    });
    test('bread is expiring soon the day before and on the day', () {
      expect(of(est(10, [bread], DateTime(2026, 10, 17)), 'bread').status, BatchStatus.expiringSoon);
      expect(of(est(10, [bread], DateTime(2026, 10, 18)), 'bread').status, BatchStatus.expiringSoon);
    });
    test('bread is expired the day after', () {
      expect(of(est(10, [bread], DateTime(2026, 10, 19)), 'bread').status, BatchStatus.expired);
    });

    test('yogurt (14 days) warns 4 days ahead, rice (a year) 7', () {
      expect(
        warningDays(receivedOn: DateTime(2026, 10, 1), expiryDate: DateTime(2026, 10, 15), shopWarnDays: 7),
        4,
      );
      expect(
        warningDays(receivedOn: DateTime(2026, 1, 1), expiryDate: DateTime(2027, 1, 1), shopWarnDays: 7),
        7,
      );
    });

    test('the shop setting caps the automatic window', () {
      expect(
        warningDays(receivedOn: DateTime(2026, 1, 1), expiryDate: DateTime(2027, 1, 1), shopWarnDays: 3),
        3,
      );
    });

    test('a date already passed at entry still warns at least a day', () {
      expect(
        warningDays(receivedOn: DateTime(2026, 10, 14), expiryDate: DateTime(2026, 10, 10), shopWarnDays: 7),
        1,
      );
    });

    test('override of 0 warns on the expiry day only', () {
      expect(of(est(10, [bread], DateTime(2026, 10, 17), override: 0), 'bread').status, BatchStatus.good);
      expect(of(est(10, [bread], DateTime(2026, 10, 18), override: 0), 'bread').status, BatchStatus.expiringSoon);
    });

    test('an override wins over the automatic rule', () {
      expect(
        warningDays(receivedOn: DateTime(2026, 1, 1), expiryDate: DateTime(2027, 1, 1), shopWarnDays: 7, productWarnDays: 30),
        30,
      );
    });
  });

  test('fractional stock does not trip float error', () {
    final a = b('a', qty: 0.1, received: DateTime(2026, 10, 1), expiry: DateTime(2026, 12, 1));
    final c = b('c', qty: 0.2, received: DateTime(2026, 10, 2), expiry: DateTime(2026, 12, 1));
    final e = est(0.1 + 0.2, [a, c], DateTime(2026, 10, 14));
    expect(of(e, 'a').left, 0.1);
    expect(of(e, 'c').left, 0.2);
    expect(e.writes, isEmpty);
  });

  test('negative stock is treated as zero', () {
    final e = est(-2, [newPepsi], DateTime(2026, 10, 14));
    expect(e.stock, 0);
    expect(e.good, 0);
  });

  test('batches come back earliest expiry first', () {
    final e = est(15, [newPepsi, oldPepsi], DateTime(2026, 10, 15));
    expect(e.batches.map((x) => x.batch.id), ['old', 'new']);
  });

  test('goodStockOf falls back to the whole stock when a product has no deliveries', () {
    const p = Product(id: 'p9', shopId: 's1', name: 'Soap', quantity: 4);
    expect(goodStockOf(p, const {}), 4);
  });

  test('applyReconcileWrites locks and closes in memory', () {
    final out = applyReconcileWrites(
      [oldPepsi, newPepsi],
      const [LockExpired('old', 5), CloseSoldOut('new')],
    );
    expect(out, hasLength(1));
    expect(out.single.expiredQty, 5);
  });
}
```

- [ ] **Step 2: Write the failing alerts and cart-notice tests**

`test/expiry_alerts_test.dart`:

```dart
import 'package:ai_shopkeeper/features/expiry/domain/expiry_alerts.dart';
import 'package:ai_shopkeeper/features/expiry/domain/expiry_estimate.dart';
import 'package:ai_shopkeeper/features/expiry/domain/product_batch.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:flutter_test/flutter_test.dart';

ProductBatch b(String id, String productId, double qty, DateTime received, DateTime expiry, {double? locked}) =>
    ProductBatch(
      id: id,
      shopId: 's1',
      productId: productId,
      quantity: qty,
      receivedOn: received,
      expiryDate: expiry,
      expiredQty: locked,
    );

void main() {
  const pepsi = Product(id: 'pepsi', shopId: 's1', name: 'Pepsi', quantity: 15);
  const bread = Product(id: 'bread', shopId: 's1', name: 'Bread', quantity: 3);
  final today = DateTime(2026, 10, 21);

  final batches = [
    b('p-old-1', 'pepsi', 3, DateTime(2026, 9, 1), DateTime(2026, 10, 19), locked: 3),
    b('p-old-2', 'pepsi', 2, DateTime(2026, 9, 2), DateTime(2026, 10, 20), locked: 2),
    b('p-new', 'pepsi', 10, DateTime(2026, 10, 10), DateTime(2026, 12, 15)),
    b('bread-1', 'bread', 3, DateTime(2026, 10, 18), DateTime(2026, 10, 22)),
  ];

  List<ExpiryAlert> alerts() => buildExpiryAlerts(
    products: [pepsi, bread],
    byProduct: estimateAll(
      products: [pepsi, bread],
      openBatches: batches,
      today: today,
      shopWarnDays: 7,
    ),
    today: today,
  );

  test('expired units are summed into one alert per product', () {
    final expired = alerts().where((a) => a.kind == ExpiryAlertKind.expired).toList();
    expect(expired, hasLength(1));
    expect(expired.single.product.id, 'pepsi');
    expect(expired.single.quantity, 5);
    expect(expired.single.expiryDate, DateTime(2026, 10, 19));
  });

  test('expired alerts come before expiring-soon ones', () {
    final all = alerts();
    expect(all.first.kind, ExpiryAlertKind.expired);
    expect(all.last.kind, ExpiryAlertKind.expiringSoon);
    expect(all.last.product.id, 'bread');
    expect(all.last.daysLeft, 1);
  });

  test('products missing from the list (archived) raise nothing', () {
    final only = buildExpiryAlerts(
      products: [bread],
      byProduct: estimateAll(products: [bread], openBatches: batches, today: today, shopWarnDays: 7),
      today: today,
    );
    expect(only.map((a) => a.product.id), ['bread']);
  });
}
```

`test/cart_expiry_test.dart`:

```dart
import 'package:ai_shopkeeper/features/cart/domain/cart_line.dart';
import 'package:ai_shopkeeper/features/expiry/domain/cart_expiry.dart';
import 'package:ai_shopkeeper/features/expiry/domain/expiry_estimate.dart';
import 'package:ai_shopkeeper/features/expiry/domain/product_batch.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const pepsi = Product(id: 'pepsi', shopId: 's1', name: 'Pepsi', quantity: 6);
  final expired = ProductBatch(
    id: 'old',
    shopId: 's1',
    productId: 'pepsi',
    quantity: 5,
    receivedOn: DateTime(2026, 9, 1),
    expiryDate: DateTime(2026, 10, 20),
    expiredQty: 5,
  );
  final byProduct = estimateAll(
    products: [pepsi],
    openBatches: [expired],
    today: DateTime(2026, 10, 21),
    shopWarnDays: 7,
  );

  test('a line within good stock raises no notice', () {
    final lines = [CartLine(product: pepsi, quantity: 1)];
    expect(cartLineNotices(lines: lines, liveProducts: {'pepsi': pepsi}, byProduct: byProduct), isEmpty);
    expect(expiredBlockedProductIds(lines, byProduct), isEmpty);
  });

  test('a line above good stock with expired units is blocked', () {
    final lines = [CartLine(product: pepsi, quantity: 2)];
    final n = cartLineNotices(lines: lines, liveProducts: {'pepsi': pepsi}, byProduct: byProduct)['pepsi'];
    expect(n, isA<ExpiredStockNotice>());
    n as ExpiredStockNotice;
    expect(n.good, 1);
    expect(n.expired, 5);
    expect(n.expiredBatchIds, ['old']);
    expect(expiredBlockedProductIds(lines, byProduct), ['pepsi']);
  });

  test('a line above live stock with no expired units says only X left', () {
    const soap = Product(id: 'soap', shopId: 's1', name: 'Soap', quantity: 2);
    final lines = [CartLine(product: soap.copyWith(quantity: 9), quantity: 4)];
    final n = cartLineNotices(lines: lines, liveProducts: {'soap': soap}, byProduct: const {})['soap'];
    expect(n, isA<OverStockNotice>());
    expect((n as OverStockNotice).stock, 2);
    expect(expiredBlockedProductIds(lines, const {}), isEmpty);
  });
}
```

- [ ] **Step 3: Run them to verify they fail**

Run: `flutter test test/expiry_estimate_test.dart test/expiry_alerts_test.dart test/cart_expiry_test.dart`
Expected: compile errors — the three domain files do not exist.

- [ ] **Step 4: Write `expiry_estimate.dart`**

```dart
import 'dart:math' as math;

import '../../inventory/domain/product.dart';
import 'expiry_dates.dart';
import 'product_batch.dart';

/// Status of one open delivery on a given day (spec §4.3).
enum BatchStatus { good, expiringSoon, expired, soldOut }

/// A write the estimate asks for (spec §4.2). The estimate itself never
/// writes; `ExpiryReconciler` applies these from a fresh server read.
sealed class ReconcileWrite {
  const ReconcileWrite(this.batchId);
  final String batchId;
}

/// Store [quantity] as the delivery's `expired_qty`. From then on sales are
/// never counted against those units.
final class LockExpired extends ReconcileWrite {
  const LockExpired(super.batchId, this.quantity);
  final double quantity;

  @override
  bool operator ==(Object other) =>
      other is LockExpired && other.batchId == batchId && other.quantity == quantity;

  @override
  int get hashCode => Object.hash('lock', batchId, quantity);

  @override
  String toString() => 'LockExpired($batchId, $quantity)';
}

/// Close the delivery as `sold_out`. Without this, an undated restock would
/// be handed to the old delivery and raise a false alarm.
final class CloseSoldOut extends ReconcileWrite {
  const CloseSoldOut(super.batchId);

  @override
  bool operator ==(Object other) => other is CloseSoldOut && other.batchId == batchId;

  @override
  int get hashCode => Object.hash('close', batchId);

  @override
  String toString() => 'CloseSoldOut($batchId)';
}

class BatchEstimate {
  const BatchEstimate({
    required this.batch,
    required this.left,
    required this.status,
    required this.warnDays,
  });

  final ProductBatch batch;

  /// Estimated units of this delivery still on the shelf.
  final double left;
  final BatchStatus status;
  final int warnDays;
}

class ProductExpiry {
  const ProductExpiry({
    required this.productId,
    required this.stock,
    required this.good,
    required this.expired,
    required this.batches,
    required this.writes,
  });

  final String productId;
  final double stock;

  /// Units that may be sold: stock minus expired units.
  final double good;
  final double expired;

  /// Open deliveries, earliest expiry first.
  final List<BatchEstimate> batches;
  final List<ReconcileWrite> writes;

  Iterable<BatchEstimate> get expiredWithStock =>
      batches.where((b) => b.status == BatchStatus.expired && b.left > 0);

  Iterable<BatchEstimate> get expiringSoon =>
      batches.where((b) => b.status == BatchStatus.expiringSoon);
}

/// Rounds to whole thousandths -- the `numeric(10,3)` precision the database
/// keeps. Without it 0.1 + 0.2 leaves a 0.00000000000000004 remainder that
/// keeps a "sold out" delivery open, or a 0.0999999 that wrongly closes one.
double round3(double v) => (v * 1000).roundToDouble() / 1000;

/// Days before expiry the warning starts (spec §4.3). Shelf life is
/// `expiryDate - receivedOn`; a short-lived item is warned near its end
/// (5-day bread: 1 day), a long-lived one [shopWarnDays] ahead.
int warningDays({
  required DateTime receivedOn,
  required DateTime expiryDate,
  required int shopWarnDays,
  int? productWarnDays,
}) {
  if (productWarnDays != null) return productWarnDays;
  final shelf = daysBetween(receivedOn, expiryDate);
  final auto = math.max(1, shelf ~/ 3);
  return math.min(shopWarnDays, auto);
}

DateTime _created(ProductBatch b) =>
    b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

/// Estimates every open delivery of one product (spec §4.1).
///
/// 1. Locked expired deliveries are reserved first, earliest expiry first.
/// 2. Every other delivery is filled newest-received first, so whatever is
///    left over lands on the oldest ("older sells first").
/// 3. Anything still left is untracked stock with no date, counted as good.
ProductExpiry estimateProductExpiry({
  required String productId,
  required double stock,
  required List<ProductBatch> openBatches,
  required DateTime today,
  required int shopWarnDays,
  int? productWarnDays,
}) {
  final t = dateOnly(today);
  final st = stock < 0 ? 0.0 : stock;
  var r = st;
  final alloc = <String, double>{};

  final locked = openBatches.where((b) => b.expiredQty != null).toList()
    ..sort((a, b) {
      final c = a.expiryDate.compareTo(b.expiryDate);
      return c != 0 ? c : _created(a).compareTo(_created(b));
    });
  for (final b in locked) {
    final take = math.min(b.expiredQty!, r);
    alloc[b.id] = take;
    r -= take;
  }

  final rest = openBatches.where((b) => b.expiredQty == null).toList()
    ..sort((a, b) {
      final c = b.receivedOn.compareTo(a.receivedOn);
      return c != 0 ? c : _created(b).compareTo(_created(a));
    });
  for (final b in rest) {
    final take = math.min(b.quantity, r);
    alloc[b.id] = take;
    r -= take;
  }

  final estimates = <BatchEstimate>[];
  final writes = <ReconcileWrite>[];
  var expired = 0.0;
  for (final b in openBatches) {
    final left = round3(alloc[b.id] ?? 0);
    final w = warningDays(
      receivedOn: b.receivedOn,
      expiryDate: b.expiryDate,
      shopWarnDays: shopWarnDays,
      productWarnDays: productWarnDays,
    );
    final BatchStatus status;
    if (b.expiredQty != null) {
      status = BatchStatus.expired;
      expired += left;
    } else if (left <= 0) {
      status = BatchStatus.soldOut;
      writes.add(CloseSoldOut(b.id));
    } else if (t.isAfter(dateOnly(b.expiryDate))) {
      status = BatchStatus.expired;
      expired += left;
      writes.add(LockExpired(b.id, left));
    } else if (daysBetween(t, b.expiryDate) <= w) {
      status = BatchStatus.expiringSoon;
    } else {
      status = BatchStatus.good;
    }
    estimates.add(BatchEstimate(batch: b, left: left, status: status, warnDays: w));
  }
  estimates.sort((a, b) => a.batch.expiryDate.compareTo(b.batch.expiryDate));

  final exp = round3(expired);
  return ProductExpiry(
    productId: productId,
    stock: st,
    good: round3(math.max(0, st - exp)),
    expired: exp,
    batches: estimates,
    writes: writes,
  );
}

/// Estimates every product in [products] that has at least one open
/// delivery. Products not in the list (archived) are skipped.
Map<String, ProductExpiry> estimateAll({
  required List<Product> products,
  required List<ProductBatch> openBatches,
  required DateTime today,
  required int shopWarnDays,
}) {
  final byProduct = <String, List<ProductBatch>>{};
  for (final b in openBatches) {
    if (b.isOpen) (byProduct[b.productId] ??= []).add(b);
  }
  return {
    for (final p in products)
      if (byProduct[p.id] != null)
        p.id: estimateProductExpiry(
          productId: p.id,
          stock: p.quantity,
          openBatches: byProduct[p.id]!,
          today: today,
          shopWarnDays: shopWarnDays,
          productWarnDays: p.expiryWarnDays,
        ),
  };
}

/// Units of [p] that may be sold. A product with no open deliveries is
/// entirely good stock.
double goodStockOf(Product p, Map<String, ProductExpiry> byProduct) =>
    byProduct[p.id]?.good ?? p.quantity;

/// [batches] as they will look once [writes] are stored: locks applied,
/// sold-out deliveries gone.
List<ProductBatch> applyReconcileWrites(
  List<ProductBatch> batches,
  List<ReconcileWrite> writes,
) {
  final locks = {
    for (final w in writes.whereType<LockExpired>()) w.batchId: w.quantity,
  };
  final closed = {for (final w in writes.whereType<CloseSoldOut>()) w.batchId};
  return [
    for (final b in batches)
      if (!closed.contains(b.id))
        locks.containsKey(b.id) ? b.copyWith(expiredQty: locks[b.id]) : b,
  ];
}
```

- [ ] **Step 5: Write `expiry_alerts.dart`**

```dart
import '../../inventory/domain/product.dart';
import 'expiry_dates.dart';
import 'expiry_estimate.dart';

enum ExpiryAlertKind { expired, expiringSoon }

/// One line on the Home card, the alerts screen and the daily reminder.
class ExpiryAlert {
  const ExpiryAlert({
    required this.product,
    required this.kind,
    required this.quantity,
    required this.expiryDate,
    required this.daysLeft,
  });

  final Product product;
  final ExpiryAlertKind kind;
  final double quantity;

  /// For an expired alert, the earliest expiry among the product's expired
  /// deliveries.
  final DateTime expiryDate;

  /// Days from today to [expiryDate]: 0 = today, 1 = tomorrow, negative once
  /// expired.
  final int daysLeft;
}

/// Expired units are summed into ONE alert per product ("Expired: 5 Pepsi");
/// each expiring-soon delivery gets its own. Expired first, then by date.
List<ExpiryAlert> buildExpiryAlerts({
  required List<Product> products,
  required Map<String, ProductExpiry> byProduct,
  required DateTime today,
}) {
  final alerts = <ExpiryAlert>[];
  for (final p in products) {
    final e = byProduct[p.id];
    if (e == null) continue;
    final expired = e.expiredWithStock.toList();
    if (expired.isNotEmpty) {
      final qty = expired.fold<double>(0, (s, b) => s + b.left);
      final earliest = expired
          .map((b) => b.batch.expiryDate)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      alerts.add(
        ExpiryAlert(
          product: p,
          kind: ExpiryAlertKind.expired,
          quantity: round3(qty),
          expiryDate: earliest,
          daysLeft: daysBetween(today, earliest),
        ),
      );
    }
    for (final b in e.expiringSoon) {
      alerts.add(
        ExpiryAlert(
          product: p,
          kind: ExpiryAlertKind.expiringSoon,
          quantity: b.left,
          expiryDate: b.batch.expiryDate,
          daysLeft: daysBetween(today, b.batch.expiryDate),
        ),
      );
    }
  }
  alerts.sort((a, b) {
    if (a.kind != b.kind) return a.kind == ExpiryAlertKind.expired ? -1 : 1;
    final c = a.expiryDate.compareTo(b.expiryDate);
    return c != 0 ? c : a.product.name.compareTo(b.product.name);
  });
  return alerts;
}
```

- [ ] **Step 6: Write `cart_expiry.dart`**

```dart
import '../../cart/domain/cart_line.dart';
import '../../inventory/domain/product.dart';
import 'expiry_estimate.dart';

/// Why a cart line cannot be checked out as it stands (spec §5 Cart).
sealed class CartLineNotice {
  const CartLineNotice();
}

/// The line wants more than the GOOD stock while expired units exist.
final class ExpiredStockNotice extends CartLineNotice {
  const ExpiredStockNotice({
    required this.good,
    required this.expired,
    required this.expiredBatchIds,
  });

  final double good;
  final double expired;

  /// The deliveries "Remove expired" / "They're not expired" act on.
  final List<String> expiredBatchIds;
}

/// The line wants more than the live stock (e.g. after "Remove expired").
final class OverStockNotice extends CartLineNotice {
  const OverStockNotice(this.stock);
  final double stock;
}

/// One notice per product whose line cannot go through. [liveProducts] is the
/// live product list keyed by id -- a cart line holds a snapshot of the
/// product from when it was added, so its own `quantity` may be stale.
Map<String, CartLineNotice> cartLineNotices({
  required List<CartLine> lines,
  required Map<String, Product> liveProducts,
  required Map<String, ProductExpiry> byProduct,
}) {
  final out = <String, CartLineNotice>{};
  for (final l in lines) {
    final id = l.product.id;
    final e = byProduct[id];
    if (e != null && e.expired > 0 && l.quantity > e.good + 1e-9) {
      out[id] = ExpiredStockNotice(
        good: e.good,
        expired: e.expired,
        expiredBatchIds: [for (final b in e.expiredWithStock) b.batch.id],
      );
      continue;
    }
    final live = liveProducts[id];
    if (live != null && l.quantity > live.quantity + 1e-9) {
      out[id] = OverStockNotice(live.quantity);
    }
  }
  return out;
}

/// Products whose line would sell expired units. Checkout refuses these.
List<String> expiredBlockedProductIds(
  List<CartLine> lines,
  Map<String, ProductExpiry> byProduct,
) => [
  for (final l in lines)
    if ((byProduct[l.product.id]?.expired ?? 0) > 0 &&
        l.quantity > byProduct[l.product.id]!.good + 1e-9)
      l.product.id,
];
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `flutter test test/expiry_estimate_test.dart test/expiry_alerts_test.dart test/cart_expiry_test.dart`
Expected: all pass.

- [ ] **Step 8: Commit**

```bash
git add lib/features/expiry/domain/ test/expiry_estimate_test.dart test/expiry_alerts_test.dart test/cart_expiry_test.dart
git commit -m "feat(expiry): estimator, alerts and cart notices

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Repositories

**Files:**
- Create: `lib/features/expiry/data/batch_repository.dart`
- Modify: `lib/features/inventory/data/product_repository.dart`

**Interfaces:**
- Consumes: `ProductBatch`, `BatchCloseReason`, `ymd`, `ReconcileWrite`/`LockExpired`/`CloseSoldOut`.
- Produces (`BatchRepository`, provider `batchRepositoryProvider`):
  - `Stream<List<ProductBatch>> watchOpenBatches(String shopId)`
  - `Future<Result<List<ProductBatch>>> fetchOpenBatches(String shopId)`
  - `Future<Result<List<ProductBatch>>> fetchClosedBatches(String productId, {int limit = 10})`
  - `Future<Result<ProductBatch>> addBatch({required String shopId, required String productId, required double quantity, required double buyingPrice, required DateTime receivedOn, required DateTime expiryDate})`
  - `Future<Result<void>> updateBatch({required String batchId, required double quantity, required DateTime expiryDate, required bool clearLock})`
  - `Future<Result<void>> closeBatch(String batchId, String reason)`
  - `Future<Result<void>> applyReconcile(List<ReconcileWrite> writes)`
  - `Future<Result<void>> removeExpiredStock({required String shopId, required String batchId})`
  - `Future<Result<DateTime?>> latestRestockDate(String productId)`
  - `ProductRepository.fetchActiveProducts(String shopId) → Future<Result<List<Product>>>`

These are thin Supabase wrappers with no logic worth a unit test (the project has no Supabase mock). They are exercised through fakes in Tasks 5–9 and against the real database by the Task 1 probe and the device checklist in Task 13.

- [ ] **Step 1: Write `batch_repository.dart`**

```dart
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../domain/expiry_dates.dart';
import '../domain/expiry_estimate.dart';
import '../domain/product_batch.dart';

/// Reads and writes `product_batches` (migration 0011). RLS scopes every row
/// to the signed-in shop.
///
/// No table is in the `supabase_realtime` publication, so [watchOpenBatches]
/// delivers the initial rows only -- callers invalidate the stream provider
/// after their own writes, the same way the products stream works.
class BatchRepository {
  BatchRepository(this._client);

  final SupabaseClient _client;
  static const _table = 'product_batches';

  Stream<List<ProductBatch>> watchOpenBatches(String shopId) {
    return _client
        .from(_table)
        .stream(primaryKey: ['id'])
        .eq('shop_id', shopId)
        .map(
          (rows) => rows
              .where((r) => r['closed_at'] == null)
              .map(ProductBatch.fromJson)
              .toList(),
        );
  }

  Future<Result<List<ProductBatch>>> fetchOpenBatches(String shopId) async {
    try {
      final rows = await _client
          .from(_table)
          .select()
          .eq('shop_id', shopId)
          .isFilter('closed_at', null);
      return Result.success(_parse(rows));
    } catch (e) {
      return Result.failure(_map(e));
    }
  }

  Future<Result<List<ProductBatch>>> fetchClosedBatches(
    String productId, {
    int limit = 10,
  }) async {
    try {
      final rows = await _client
          .from(_table)
          .select()
          .eq('product_id', productId)
          .not('closed_at', 'is', null)
          .order('closed_at', ascending: false)
          .limit(limit);
      return Result.success(_parse(rows));
    } catch (e) {
      return Result.failure(_map(e));
    }
  }

  Future<Result<ProductBatch>> addBatch({
    required String shopId,
    required String productId,
    required double quantity,
    required double buyingPrice,
    required DateTime receivedOn,
    required DateTime expiryDate,
  }) async {
    try {
      final row = await _client
          .from(_table)
          .insert({
            'shop_id': shopId,
            'product_id': productId,
            'quantity': quantity,
            'buying_price': buyingPrice,
            'received_on': ymd(receivedOn),
            'expiry_date': ymd(expiryDate),
          })
          .select()
          .single();
      return Result.success(ProductBatch.fromJson(row));
    } catch (e) {
      return Result.failure(_map(e));
    }
  }

  /// Edits an OPEN delivery. [clearLock] removes a locked expired count -- used
  /// when a mistyped date is corrected to today or later (spec §3.3).
  Future<Result<void>> updateBatch({
    required String batchId,
    required double quantity,
    required DateTime expiryDate,
    required bool clearLock,
  }) async {
    try {
      await _client
          .from(_table)
          .update({
            'quantity': quantity,
            'expiry_date': ymd(expiryDate),
            if (clearLock) 'expired_qty': null,
          })
          .eq('id', batchId)
          .isFilter('closed_at', null);
      return const Result.success(null);
    } catch (e) {
      return Result.failure(_map(e));
    }
  }

  Future<Result<void>> closeBatch(String batchId, String reason) async {
    try {
      await _close(batchId, reason);
      return const Result.success(null);
    } catch (e) {
      return Result.failure(_map(e));
    }
  }

  /// Stores reconcile writes. Each update only touches a still-open row (and a
  /// lock only a still-unlocked one), so when two phones race the first
  /// writer wins and the second write changes nothing.
  Future<Result<void>> applyReconcile(List<ReconcileWrite> writes) async {
    try {
      for (final w in writes) {
        switch (w) {
          case LockExpired(:final batchId, :final quantity):
            await _client
                .from(_table)
                .update({'expired_qty': quantity})
                .eq('id', batchId)
                .isFilter('closed_at', null)
                .isFilter('expired_qty', null);
          case CloseSoldOut(:final batchId):
            await _close(batchId, BatchCloseReason.soldOut);
        }
      }
      return const Result.success(null);
    } catch (e) {
      return Result.failure(_map(e));
    }
  }

  /// `remove_expired_stock` (0011): lowers stock by the locked expired count,
  /// records the loss as an `adjustment`, closes the delivery. Safe to retry.
  Future<Result<void>> removeExpiredStock({
    required String shopId,
    required String batchId,
  }) async {
    try {
      await _client.rpc(
        'remove_expired_stock',
        params: {'p_shop_id': shopId, 'p_batch_id': batchId},
      );
      return const Result.success(null);
    } catch (e) {
      return Result.failure(_map(e));
    }
  }

  /// Local date of the product's latest restock, or null if never restocked.
  /// The default "date added" for stock already on the shelf (spec §4.3).
  Future<Result<DateTime?>> latestRestockDate(String productId) async {
    try {
      final rows = await _client
          .from('transactions')
          .select('created_at')
          .eq('product_id', productId)
          .eq('type', 'restock')
          .order('created_at', ascending: false)
          .limit(1);
      final list = rows as List;
      if (list.isEmpty) return const Result.success(null);
      final raw = (list.first as Map)['created_at'] as String;
      return Result.success(dateOnly(DateTime.parse(raw).toLocal()));
    } catch (e) {
      return Result.failure(_map(e));
    }
  }

  Future<void> _close(String batchId, String reason) => _client
      .from(_table)
      .update({
        'closed_at': DateTime.now().toUtc().toIso8601String(),
        'closed_reason': reason,
      })
      .eq('id', batchId)
      .isFilter('closed_at', null);

  List<ProductBatch> _parse(Object? rows) => [
    for (final r in rows as List)
      ProductBatch.fromJson(Map<String, dynamic>.from(r as Map)),
  ];

  Failure _map(Object e) {
    if (e is PostgrestException) {
      return DatabaseFailure(
        e.message.isEmpty ? 'Could not save the delivery.' : e.message,
      );
    }
    if (e is SocketException) {
      return const NetworkFailure('No internet connection. Please try again.');
    }
    return const UnexpectedFailure('Something went wrong. Please try again.');
  }
}

final batchRepositoryProvider = Provider<BatchRepository>((ref) {
  return BatchRepository(ref.watch(supabaseClientProvider));
});
```

- [ ] **Step 2: Add `fetchActiveProducts` to `ProductRepository`**

In `lib/features/inventory/data/product_repository.dart`, add after `watchProducts`:

```dart
  /// A one-shot read of the shop's active (non-archived) products. Used by the
  /// expiry reconcile, which must read stock fresh AFTER reading deliveries
  /// rather than trust the stream (see `ExpiryReconciler`).
  Future<Result<List<Product>>> fetchActiveProducts(String shopId) async {
    try {
      final rows = await _client
          .from(_table)
          .select()
          .eq('shop_id', shopId)
          .eq('is_archived', false);
      return Result.success([
        for (final r in rows as List)
          Product.fromJson(Map<String, dynamic>.from(r as Map)),
      ]);
    } catch (e) {
      return Result.failure(_map(e));
    }
  }
```

(`_map` already exists in this repository — reuse it.)

- [ ] **Step 3: Analyze**

Run: `flutter analyze lib/features/expiry lib/features/inventory/data`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/features/expiry/data/batch_repository.dart lib/features/inventory/data/product_repository.dart
git commit -m "feat(expiry): delivery repository and a one-shot active-products read

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 5: Settings state, "today", providers, reconcile and the checkout gate

**Files:**
- Create: `lib/features/expiry/presentation/expiry_prefs.dart`, `today_provider.dart`, `expiry_providers.dart`, `expiry_reconciler.dart`, `expiry_gate.dart`
- Create: `test/support/expiry_fakes.dart`
- Modify: `lib/main.dart`, `lib/app.dart`
- Test: `test/expiry_prefs_test.dart`, `test/today_provider_test.dart`, `test/expiry_reconciler_test.dart`, `test/expiry_gate_test.dart`

**Interfaces:**
- Consumes: Tasks 2–4; `myShopProvider` (`lib/features/auth/data/auth_repository.dart`), `productsStreamProvider`, `productRepositoryProvider`, `cartControllerProvider`.
- Produces:
  - `class ExpiryPrefs { int warnDays; bool remindersOn; bool permissionAsked; copyWith(...); static const warnDayChoices = [3, 7, 14, 30]; }`, `initialExpiryPrefsProvider`, `expiryPrefsProvider` (`ExpiryPrefsController`: `setWarnDays(int)`, `setRemindersOn(bool)`, `markPermissionAsked()`), `Future<ExpiryPrefs> loadExpiryPrefs()`
  - `nowProvider` (`Provider<DateTime Function()>`), `todayProvider` (`NotifierProvider<TodayController, DateTime>`; `TodayController.refresh()`)
  - `batchesStreamProvider`, `productExpiryProvider` (`Map<String, ProductExpiry>`), `goodStockProvider` (family by `Product` → `double`), `expiryAlertsProvider` (`List<ExpiryAlert>`), `closedBatchesProvider` (family by product id), `latestRestockDateProvider` (family by product id), `cartLineNoticesProvider` (`Map<String, CartLineNotice>`), `expiryAutoReconcileProvider`
  - `class ReconcileOutcome { bool ok; Failure? failure; Map<String, ProductExpiry> byProduct; }`, `class ExpiryReconciler { Future<ReconcileOutcome> run(); }`, `expiryReconcilerProvider`
  - `sealed class GateResult`: `GatePass`, `GateBlocked(List<String> productIds)`, `GateFailed(Failure failure)`; `abstract class ExpiryGate { Future<GateResult> check(List<CartLine> lines); }`, `ReconcilingExpiryGate`, `expiryGateProvider`
  - Test fakes: `NoopReconciler`, `PassingExpiryGate`, `FixedGate(GateResult)`

**Why reconcile reads deliveries first.** The screens read products and deliveries from two separate streams that refresh independently. If a restock's new delivery reaches the phone before the restock's new stock does, the estimate hands the old stock to the new delivery, sees the old delivery at 0, and would close it as sold out — losing real units. So writes are never computed from the streams. `ExpiryReconciler` reads **deliveries first, then stock**: if anything changes between the two reads, the stock is the *newer* value, which can only give old deliveries *more*, never wrongly zero one.

- [ ] **Step 1: Write the shared test fakes**

`test/support/expiry_fakes.dart`:

```dart
import 'package:ai_shopkeeper/features/cart/domain/cart_line.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/expiry_gate.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/expiry_reconciler.dart';

/// A reconcile that does nothing and succeeds -- for tests whose subject is
/// not expiry but whose code path triggers a reconcile.
class NoopReconciler implements ExpiryReconciler {
  int runs = 0;

  @override
  Future<ReconcileOutcome> run() async {
    runs++;
    return const ReconcileOutcome.ok({});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Lets every checkout through.
class PassingExpiryGate implements ExpiryGate {
  const PassingExpiryGate();

  @override
  Future<GateResult> check(List<CartLine> lines) async => const GatePass();
}

/// Always answers [result].
class FixedGate implements ExpiryGate {
  const FixedGate(this.result);
  final GateResult result;

  @override
  Future<GateResult> check(List<CartLine> lines) async => result;
}
```

- [ ] **Step 2: Write the failing tests**

`test/expiry_prefs_test.dart`:

```dart
import 'package:ai_shopkeeper/features/expiry/presentation/expiry_prefs.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('defaults: 7 days, reminders on, permission not asked', () async {
    final p = await loadExpiryPrefs();
    expect(p.warnDays, 7);
    expect(p.remindersOn, isTrue);
    expect(p.permissionAsked, isFalse);
  });

  test('changes persist across a reload', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(expiryPrefsProvider.notifier);
    await n.setWarnDays(14);
    await n.setRemindersOn(false);
    await n.markPermissionAsked();
    expect(c.read(expiryPrefsProvider).warnDays, 14);

    final reloaded = await loadExpiryPrefs();
    expect(reloaded.warnDays, 14);
    expect(reloaded.remindersOn, isFalse);
    expect(reloaded.permissionAsked, isTrue);
  });
}
```

`test/today_provider_test.dart`:

```dart
import 'package:ai_shopkeeper/features/expiry/presentation/today_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('today is the local date and moves on refresh after midnight', () {
    var now = DateTime(2026, 10, 20, 23, 59);
    final c = ProviderContainer(
      overrides: [nowProvider.overrideWithValue(() => now)],
    );
    addTearDown(c.dispose);

    expect(c.read(todayProvider), DateTime(2026, 10, 20));

    now = DateTime(2026, 10, 21, 0, 0, 5);
    c.read(todayProvider.notifier).refresh();
    expect(c.read(todayProvider), DateTime(2026, 10, 21));
  });
}
```

`test/expiry_reconciler_test.dart`:

```dart
import 'package:ai_shopkeeper/core/error/failure.dart';
import 'package:ai_shopkeeper/core/error/result.dart';
import 'package:ai_shopkeeper/features/auth/data/auth_repository.dart';
import 'package:ai_shopkeeper/features/auth/domain/shop.dart';
import 'package:ai_shopkeeper/features/expiry/data/batch_repository.dart';
import 'package:ai_shopkeeper/features/expiry/domain/expiry_estimate.dart';
import 'package:ai_shopkeeper/features/expiry/domain/product_batch.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/expiry_reconciler.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/today_provider.dart';
import 'package:ai_shopkeeper/features/inventory/data/product_repository.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBatchRepo implements BatchRepository {
  _FakeBatchRepo(this.calls, {this.batches = const [], this.failRead = false});
  final List<String> calls;
  final List<ProductBatch> batches;
  final bool failRead;
  List<ReconcileWrite>? applied;

  @override
  Future<Result<List<ProductBatch>>> fetchOpenBatches(String shopId) async {
    calls.add('batches');
    if (failRead) return const Result.failure(NetworkFailure('offline'));
    return Result.success(batches);
  }

  @override
  Future<Result<void>> applyReconcile(List<ReconcileWrite> writes) async {
    calls.add('apply');
    applied = writes;
    return const Result.success(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProductRepo implements ProductRepository {
  _FakeProductRepo(this.calls, this.products);
  final List<String> calls;
  final List<Product> products;

  @override
  Future<Result<List<Product>>> fetchActiveProducts(String shopId) async {
    calls.add('products');
    return Result.success(products);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _pepsi = Product(id: 'pepsi', shopId: 's1', name: 'Pepsi', quantity: 15);
final _old = ProductBatch(
  id: 'old',
  shopId: 's1',
  productId: 'pepsi',
  quantity: 5,
  receivedOn: DateTime(2026, 10, 1),
  expiryDate: DateTime(2026, 10, 20),
);
final _new = ProductBatch(
  id: 'new',
  shopId: 's1',
  productId: 'pepsi',
  quantity: 10,
  receivedOn: DateTime(2026, 10, 10),
  expiryDate: DateTime(2026, 12, 15),
);

Future<ProviderContainer> _container(BatchRepository b, ProductRepository p) async {
  final c = ProviderContainer(
    overrides: [
      myShopProvider.overrideWith(
        (ref) async => const Shop(id: 's1', ownerId: 'o1', name: 'Shop', currency: 'BDT'),
      ),
      batchRepositoryProvider.overrideWithValue(b),
      productRepositoryProvider.overrideWithValue(p),
      nowProvider.overrideWithValue(() => DateTime(2026, 10, 21, 10)),
    ],
  );
  addTearDown(c.dispose);
  await c.read(myShopProvider.future);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reconcile reads deliveries before products, then writes', () async {
    final calls = <String>[];
    final batches = _FakeBatchRepo(calls, batches: [_old, _new]);
    final c = await _container(batches, _FakeProductRepo(calls, [_pepsi]));

    final outcome = await c.read(expiryReconcilerProvider).run();

    expect(calls, ['batches', 'products', 'apply']);
    expect(batches.applied, [const LockExpired('old', 5)]);
    expect(outcome.ok, isTrue);
    // The outcome reflects the lock already applied.
    expect(outcome.byProduct['pepsi']!.expired, 5);
    expect(outcome.byProduct['pepsi']!.good, 10);
    expect(outcome.byProduct['pepsi']!.writes, isEmpty);
  });

  test('a shop with no deliveries reads nothing else', () async {
    final calls = <String>[];
    final c = await _container(_FakeBatchRepo(calls), _FakeProductRepo(calls, [_pepsi]));
    final outcome = await c.read(expiryReconcilerProvider).run();
    expect(calls, ['batches']);
    expect(outcome.ok, isTrue);
    expect(outcome.byProduct, isEmpty);
  });

  test('a failed read is reported, not thrown', () async {
    final calls = <String>[];
    final c = await _container(
      _FakeBatchRepo(calls, failRead: true),
      _FakeProductRepo(calls, [_pepsi]),
    );
    final outcome = await c.read(expiryReconcilerProvider).run();
    expect(outcome.ok, isFalse);
    expect(outcome.failure, isA<NetworkFailure>());
  });

  test('overlapping runs do not interleave', () async {
    final calls = <String>[];
    final c = await _container(
      _FakeBatchRepo(calls, batches: [_old, _new]),
      _FakeProductRepo(calls, [_pepsi]),
    );
    final r = c.read(expiryReconcilerProvider);
    await Future.wait([r.run(), r.run()]);
    expect(calls, ['batches', 'products', 'apply', 'batches', 'products', 'apply']);
  });
}
```

`test/expiry_gate_test.dart`:

```dart
import 'package:ai_shopkeeper/core/error/failure.dart';
import 'package:ai_shopkeeper/features/cart/domain/cart_line.dart';
import 'package:ai_shopkeeper/features/expiry/domain/expiry_estimate.dart';
import 'package:ai_shopkeeper/features/expiry/domain/product_batch.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/expiry_gate.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/expiry_reconciler.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:flutter_test/flutter_test.dart';

class _FixedReconciler implements ExpiryReconciler {
  _FixedReconciler(this.outcome);
  final ReconcileOutcome outcome;

  @override
  Future<ReconcileOutcome> run() async => outcome;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const pepsi = Product(id: 'pepsi', shopId: 's1', name: 'Pepsi', quantity: 6);
  final byProduct = estimateAll(
    products: [pepsi],
    openBatches: [
      ProductBatch(
        id: 'old',
        shopId: 's1',
        productId: 'pepsi',
        quantity: 5,
        receivedOn: DateTime(2026, 9, 1),
        expiryDate: DateTime(2026, 10, 20),
        expiredQty: 5,
      ),
    ],
    today: DateTime(2026, 10, 21),
    shopWarnDays: 7,
  );

  test('passes when every line fits in good stock', () async {
    final gate = ReconcilingExpiryGate(_FixedReconciler(ReconcileOutcome.ok(byProduct)));
    expect(await gate.check([CartLine(product: pepsi, quantity: 1)]), isA<GatePass>());
  });

  test('blocks a line that would sell expired units', () async {
    final gate = ReconcilingExpiryGate(_FixedReconciler(ReconcileOutcome.ok(byProduct)));
    final r = await gate.check([CartLine(product: pepsi, quantity: 3)]);
    expect(r, isA<GateBlocked>());
    expect((r as GateBlocked).productIds, ['pepsi']);
  });

  test('a failed reconcile is passed on as that failure', () async {
    final gate = ReconcilingExpiryGate(
      _FixedReconciler(const ReconcileOutcome.failed(NetworkFailure('offline'))),
    );
    final r = await gate.check([CartLine(product: pepsi, quantity: 1)]);
    expect(r, isA<GateFailed>());
    expect((r as GateFailed).failure, isA<NetworkFailure>());
  });
}
```

- [ ] **Step 3: Run them to verify they fail**

Run: `flutter test test/expiry_prefs_test.dart test/today_provider_test.dart test/expiry_reconciler_test.dart test/expiry_gate_test.dart`
Expected: compile errors — the presentation files do not exist.

- [ ] **Step 4: Write `expiry_prefs.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Phone-local expiry settings (spec §5 Settings), stored like the theme.
class ExpiryPrefs {
  const ExpiryPrefs({
    this.warnDays = 7,
    this.remindersOn = true,
    this.permissionAsked = false,
  });

  /// The most days ahead the automatic warning may start (spec §4.3).
  final int warnDays;
  final bool remindersOn;

  /// Notification permission is requested once, the first time an expiry
  /// date is saved (spec §6).
  final bool permissionAsked;

  static const warnDayChoices = [3, 7, 14, 30];

  ExpiryPrefs copyWith({int? warnDays, bool? remindersOn, bool? permissionAsked}) =>
      ExpiryPrefs(
        warnDays: warnDays ?? this.warnDays,
        remindersOn: remindersOn ?? this.remindersOn,
        permissionAsked: permissionAsked ?? this.permissionAsked,
      );
}

const _kWarnDays = 'expiry_warn_days';
const _kRemindersOn = 'expiry_reminders_on';
const _kPermissionAsked = 'expiry_permission_asked';

/// Seeded in `main()` from SharedPreferences, like `initialThemeModeProvider`.
final initialExpiryPrefsProvider = Provider<ExpiryPrefs>((ref) => const ExpiryPrefs());

class ExpiryPrefsController extends Notifier<ExpiryPrefs> {
  @override
  ExpiryPrefs build() => ref.watch(initialExpiryPrefsProvider);

  Future<void> setWarnDays(int days) async {
    state = state.copyWith(warnDays: days);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kWarnDays, days);
  }

  Future<void> setRemindersOn(bool on) async {
    state = state.copyWith(remindersOn: on);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kRemindersOn, on);
  }

  Future<void> markPermissionAsked() async {
    state = state.copyWith(permissionAsked: true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPermissionAsked, true);
  }
}

final expiryPrefsProvider = NotifierProvider<ExpiryPrefsController, ExpiryPrefs>(
  ExpiryPrefsController.new,
);

Future<ExpiryPrefs> loadExpiryPrefs() async {
  final prefs = await SharedPreferences.getInstance();
  return ExpiryPrefs(
    warnDays: prefs.getInt(_kWarnDays) ?? 7,
    remindersOn: prefs.getBool(_kRemindersOn) ?? true,
    permissionAsked: prefs.getBool(_kPermissionAsked) ?? false,
  );
}
```

- [ ] **Step 5: Write `today_provider.dart`**

```dart
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/expiry_dates.dart';

/// The current instant. A provider so tests can pin it; production reads the
/// zone-scoped `clock`.
final nowProvider = Provider<DateTime Function()>((ref) => clock.now);

/// The phone's local calendar date. It must MOVE: an app left open overnight
/// would otherwise never mark anything expired (spec §4.2). Updated by a timer
/// at local midnight and whenever the app returns to the foreground.
class TodayController extends Notifier<DateTime> {
  Timer? _midnight;
  AppLifecycleListener? _lifecycle;

  @override
  DateTime build() {
    _lifecycle = AppLifecycleListener(onResume: refresh);
    ref.onDispose(() {
      _midnight?.cancel();
      _lifecycle?.dispose();
    });
    final now = ref.read(nowProvider)();
    _arm(now);
    return dateOnly(now);
  }

  void refresh() {
    final now = ref.read(nowProvider)();
    final today = dateOnly(now);
    if (today != state) state = today;
    _arm(now);
  }

  void _arm(DateTime now) {
    _midnight?.cancel();
    final next = DateTime(now.year, now.month, now.day + 1);
    _midnight = Timer(next.difference(now) + const Duration(seconds: 1), refresh);
  }
}

final todayProvider = NotifierProvider<TodayController, DateTime>(TodayController.new);
```

- [ ] **Step 6: Write `expiry_reconciler.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../auth/data/auth_repository.dart';
import '../../inventory/data/product_repository.dart';
import '../../inventory/domain/product.dart';
import '../data/batch_repository.dart';
import '../domain/expiry_estimate.dart';
import '../domain/product_batch.dart';
import 'expiry_prefs.dart';
import 'expiry_providers.dart';
import 'today_provider.dart';

class ReconcileOutcome {
  const ReconcileOutcome.ok(this.byProduct) : failure = null;
  const ReconcileOutcome.failed(Failure this.failure) : byProduct = const {};

  final Failure? failure;

  /// The estimate after this run's writes were stored.
  final Map<String, ProductExpiry> byProduct;

  bool get ok => failure == null;
}

/// Stores the estimate's reconcile writes (spec §4.2): locks expired counts
/// and closes sold-out deliveries.
///
/// Computed from a FRESH read, never from the screen streams, and the read
/// order matters: deliveries first, then stock. The streams refresh
/// independently, so a restock's new delivery can arrive before its new stock;
/// estimating from that pair hands the old stock to the new delivery and
/// closes the old one as "sold out" while its units are still on the shelf.
/// Reading deliveries first means anything that changes between the two reads
/// shows up as NEWER stock, which can only give old deliveries more.
class ExpiryReconciler {
  ExpiryReconciler(this._ref);

  final Ref _ref;
  Future<void> _tail = Future.value();

  /// Serialised: each call waits for the one before, so a checkout always
  /// gets a result computed after any reconcile already running.
  Future<ReconcileOutcome> run() {
    final next = _tail.then((_) => _runOnce());
    _tail = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<ReconcileOutcome> _runOnce() async {
    try {
      final shopId = _ref.read(myShopProvider).value?.id;
      if (shopId == null) return const ReconcileOutcome.ok({});
      final batchRepo = _ref.read(batchRepositoryProvider);

      final List<ProductBatch> batches;
      switch (await batchRepo.fetchOpenBatches(shopId)) {
        case ResultFailure(:final failure):
          return ReconcileOutcome.failed(failure);
        case Success(:final value):
          batches = value;
      }
      if (batches.isEmpty) return const ReconcileOutcome.ok({});

      final List<Product> products;
      switch (await _ref.read(productRepositoryProvider).fetchActiveProducts(shopId)) {
        case ResultFailure(:final failure):
          return ReconcileOutcome.failed(failure);
        case Success(:final value):
          products = value;
      }

      final today = _ref.read(todayProvider);
      final warnDays = _ref.read(expiryPrefsProvider).warnDays;
      final byProduct = estimateAll(
        products: products,
        openBatches: batches,
        today: today,
        shopWarnDays: warnDays,
      );
      final writes = [for (final e in byProduct.values) ...e.writes];
      if (writes.isEmpty) return ReconcileOutcome.ok(byProduct);

      if (await batchRepo.applyReconcile(writes) case ResultFailure(:final failure)) {
        return ReconcileOutcome.failed(failure);
      }
      _ref.invalidate(batchesStreamProvider);
      return ReconcileOutcome.ok(
        estimateAll(
          products: products,
          openBatches: applyReconcileWrites(batches, writes),
          today: today,
          shopWarnDays: warnDays,
        ),
      );
    } catch (_) {
      // Never let a reconcile crash its caller; checkout treats this as a
      // failure and stops, everyone else simply tries again later.
      return const ReconcileOutcome.failed(
        UnexpectedFailure('Could not check expiry dates.'),
      );
    }
  }
}

final expiryReconcilerProvider = Provider<ExpiryReconciler>(ExpiryReconciler.new);
```

- [ ] **Step 7: Write `expiry_providers.dart`**

```dart
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../../cart/presentation/cart_controller.dart';
import '../../inventory/domain/product.dart';
import '../../inventory/presentation/inventory_controller.dart';
import '../data/batch_repository.dart';
import '../domain/cart_expiry.dart';
import '../domain/expiry_alerts.dart';
import '../domain/expiry_estimate.dart';
import '../domain/product_batch.dart';
import 'expiry_prefs.dart';
import 'expiry_reconciler.dart';
import 'today_provider.dart';

/// The shop's open deliveries. Initial rows only (no realtime publication) --
/// invalidate after a write, as with `productsStreamProvider`.
final batchesStreamProvider = StreamProvider.autoDispose<List<ProductBatch>>((ref) {
  final shop = ref.watch(myShopProvider).value;
  if (shop == null) return Stream.value(const <ProductBatch>[]);
  return ref.watch(batchRepositoryProvider).watchOpenBatches(shop.id);
});

/// The estimate for every product with open deliveries, for DISPLAY. Writes
/// never come from here -- see `ExpiryReconciler`. While either stream is
/// loading or has failed (offline, or tests without a backend) this is empty,
/// which means "no expiry information": everything behaves as before.
final productExpiryProvider = Provider.autoDispose<Map<String, ProductExpiry>>((ref) {
  final products = ref.watch(productsStreamProvider).value ?? const <Product>[];
  final batches = ref.watch(batchesStreamProvider).value ?? const <ProductBatch>[];
  if (batches.isEmpty) return const {};
  return estimateAll(
    products: products,
    openBatches: batches,
    today: ref.watch(todayProvider),
    shopWarnDays: ref.watch(expiryPrefsProvider.select((p) => p.warnDays)),
  );
});

/// Units of a product that may be sold (stock minus expired units).
final goodStockProvider = Provider.autoDispose.family<double, Product>(
  (ref, product) => goodStockOf(product, ref.watch(productExpiryProvider)),
);

final expiryAlertsProvider = Provider.autoDispose<List<ExpiryAlert>>((ref) {
  return buildExpiryAlerts(
    products: ref.watch(productsStreamProvider).value ?? const <Product>[],
    byProduct: ref.watch(productExpiryProvider),
    today: ref.watch(todayProvider),
  );
});

final closedBatchesProvider =
    FutureProvider.autoDispose.family<List<ProductBatch>, String>((ref, productId) async {
      final r = await ref.watch(batchRepositoryProvider).fetchClosedBatches(productId);
      return r.valueOrNull ?? const <ProductBatch>[];
    });

final latestRestockDateProvider =
    FutureProvider.autoDispose.family<DateTime?, String>((ref, productId) async {
      final r = await ref.watch(batchRepositoryProvider).latestRestockDate(productId);
      return r.valueOrNull;
    });

/// Why each cart line cannot go through as it stands, keyed by product id.
final cartLineNoticesProvider = Provider.autoDispose<Map<String, CartLineNotice>>((ref) {
  final products = ref.watch(productsStreamProvider).value ?? const <Product>[];
  return cartLineNotices(
    lines: ref.watch(cartControllerProvider),
    liveProducts: {for (final p in products) p.id: p},
    byProduct: ref.watch(productExpiryProvider),
  );
});

/// Runs a reconcile when the shop loads, when the date changes and when the
/// app returns to the foreground. Kept alive by `App`.
final expiryAutoReconcileProvider = Provider<void>((ref) {
  final reconciler = ref.watch(expiryReconcilerProvider);
  void run() => unawaited(reconciler.run());

  ref.listen(todayProvider, (_, _) => run());
  ref.listen(myShopProvider, (prev, next) {
    final id = next.value?.id;
    if (id != null && id != prev?.value?.id) run();
  }, fireImmediately: true);
  final lifecycle = AppLifecycleListener(onResume: run);
  ref.onDispose(lifecycle.dispose);
});
```

- [ ] **Step 8: Write `expiry_gate.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../cart/domain/cart_line.dart';
import '../domain/cart_expiry.dart';
import 'expiry_reconciler.dart';

sealed class GateResult {
  const GateResult();
}

final class GatePass extends GateResult {
  const GatePass();
}

final class GateBlocked extends GateResult {
  const GateBlocked(this.productIds);
  final List<String> productIds;
}

final class GateFailed extends GateResult {
  const GateFailed(this.failure);
  final Failure failure;
}

/// Runs before checkout records a sale (spec §4.2, §5 Cart): stores any
/// pending expired-count locks, then refuses a cart that would sell expired
/// units. The block lives in the app; `record_sale_cart` does not know about
/// expiry.
abstract class ExpiryGate {
  Future<GateResult> check(List<CartLine> lines);
}

class ReconcilingExpiryGate implements ExpiryGate {
  const ReconcilingExpiryGate(this._reconciler);

  final ExpiryReconciler _reconciler;

  @override
  Future<GateResult> check(List<CartLine> lines) async {
    final outcome = await _reconciler.run();
    if (outcome.failure case final failure?) return GateFailed(failure);
    final blocked = expiredBlockedProductIds(lines, outcome.byProduct);
    return blocked.isEmpty ? const GatePass() : GateBlocked(blocked);
  }
}

final expiryGateProvider = Provider<ExpiryGate>(
  (ref) => ReconcilingExpiryGate(ref.watch(expiryReconcilerProvider)),
);
```

- [ ] **Step 9: Run the tests to verify they pass**

Run: `flutter test test/expiry_prefs_test.dart test/today_provider_test.dart test/expiry_reconciler_test.dart test/expiry_gate_test.dart`
Expected: all pass.

- [ ] **Step 10: Seed the prefs at startup and keep the reconcile alive**

In `lib/main.dart`, add the import and load next to the theme/locale loads:

```dart
import 'features/expiry/presentation/expiry_prefs.dart';
```

```dart
  final locale = await loadLocale();
  final expiryPrefs = await loadExpiryPrefs();
```

and add to the `ProviderScope` overrides:

```dart
        initialExpiryPrefsProvider.overrideWithValue(expiryPrefs),
```

In `lib/app.dart`, add the import and, as the first line of `build` after `final locale = ...`:

```dart
import 'features/expiry/presentation/expiry_providers.dart';
```

```dart
    // Locks expired counts / closes sold-out deliveries on shop load, date
    // change and app resume (expiry spec §4.2).
    ref.listen(expiryAutoReconcileProvider, (_, _) {});
```

- [ ] **Step 11: Run the whole suite**

Run: `flutter test`
Expected: all pass (nothing reads the new providers yet except `App`, which no test pumps).

- [ ] **Step 12: Commit**

```bash
git add lib/features/expiry/presentation/ lib/main.dart lib/app.dart test/support/expiry_fakes.dart test/expiry_prefs_test.dart test/today_provider_test.dart test/expiry_reconciler_test.dart test/expiry_gate_test.dart
git commit -m "feat(expiry): prefs, a moving today, providers, fresh-read reconcile and checkout gate

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Retry-safe restock with an optional expiry date

**Files:**
- Create: `lib/features/expiry/presentation/expiry_date_field.dart`
- Modify: `lib/features/transactions/data/transaction_repository.dart`, `lib/features/transactions/presentation/transaction_controller.dart`, `lib/features/transactions/presentation/transaction_confirmation_sheet.dart`, `test/support/cart_harness.dart`, `lib/l10n/app_en.arb`, `lib/l10n/app_bn.arb`
- Test: `test/restock_idempotency_test.dart`, `test/widgets/expiry_date_field_test.dart`

**Interfaces:**
- Consumes: `ymd`, `dateOnly`, `classifyExpiryDate`, `OddDate` (Task 2); `nowProvider`, `todayProvider`, `batchesStreamProvider`, `expiryReconcilerProvider` (Task 5).
- Produces:
  - `TransactionRepository.recordRestock({required String shopId, required String productId, required double quantity, required String restockId, String source = 'manual', DateTime? expiryDate, DateTime? receivedOn})`
  - `TransactionController.recordRestock({required String productId, required double quantity, String source = 'manual', DateTime? expiryDate})`
  - `ExpiryDateField({required DateTime? value, required ValueChanged<DateTime?> onChanged, String? label, bool enabled = true})`, `Future<bool> confirmOddExpiryDate(BuildContext, DateTime picked, DateTime today)`, `String formatExpiryDate(BuildContext, DateTime)`

- [ ] **Step 1: Add the strings**

Add to `lib/l10n/app_en.arb` (before the final `}`; add a comma after the previous last entry):

```json
  "expiry_dateLabel": "Expiry date",
  "expiry_dateOptional": "Optional",
  "expiry_dateClear": "Remove date",
  "expiry_pastDateTitle": "This date has already passed",
  "expiry_pastDateBody": "Save it anyway?",
  "expiry_farDateTitle": "Is this year right?",
  "expiry_farDateBody": "{date} is more than 5 years away.",
  "@expiry_farDateBody": { "placeholders": { "date": { "type": "String" } } },
  "expiry_saveAnyway": "Save anyway",
  "expiry_changeDate": "Change date"
```

Add to `lib/l10n/app_bn.arb`:

```json
  "expiry_dateLabel": "মেয়াদ শেষের তারিখ",
  "expiry_dateOptional": "ঐচ্ছিক",
  "expiry_dateClear": "তারিখ মুছুন",
  "expiry_pastDateTitle": "এই তারিখ পার হয়ে গেছে",
  "expiry_pastDateBody": "তবুও সংরক্ষণ করবেন?",
  "expiry_farDateTitle": "সালটা কি ঠিক আছে?",
  "expiry_farDateBody": "{date} পাঁচ বছরেরও বেশি পরে।",
  "@expiry_farDateBody": { "placeholders": { "date": { "type": "String" } } },
  "expiry_saveAnyway": "তবুও সংরক্ষণ",
  "expiry_changeDate": "তারিখ বদলান"
```

Run: `flutter gen-l10n`
Expected: regenerates `lib/l10n/app_localizations*.dart` with no errors.

- [ ] **Step 2: Write the failing tests**

`test/restock_idempotency_test.dart`:

```dart
import 'package:ai_shopkeeper/core/error/failure.dart';
import 'package:ai_shopkeeper/core/error/result.dart';
import 'package:ai_shopkeeper/features/auth/data/auth_repository.dart';
import 'package:ai_shopkeeper/features/auth/domain/shop.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/expiry_reconciler.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/today_provider.dart';
import 'package:ai_shopkeeper/features/transactions/data/transaction_repository.dart';
import 'package:ai_shopkeeper/features/transactions/domain/transaction.dart';
import 'package:ai_shopkeeper/features/transactions/presentation/transaction_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/expiry_fakes.dart';

class _FlakyRestockRepo implements TransactionRepository {
  bool fail = true;
  final ids = <String>[];
  final expiries = <DateTime?>[];
  final receivedOns = <DateTime?>[];

  @override
  Future<Result<Transaction>> recordRestock({
    required String shopId,
    required String productId,
    required double quantity,
    required String restockId,
    String source = 'manual',
    DateTime? expiryDate,
    DateTime? receivedOn,
  }) async {
    ids.add(restockId);
    expiries.add(expiryDate);
    receivedOns.add(receivedOn);
    if (fail) return const Result.failure(NetworkFailure('timed out'));
    return const Result.success(
      Transaction(id: 't', shopId: 's1', productId: 'p1', type: 'restock', quantity: 1),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<ProviderContainer> _container(TransactionRepository repo) async {
  final c = ProviderContainer(
    overrides: [
      myShopProvider.overrideWith(
        (ref) async => const Shop(id: 's1', ownerId: 'o1', name: 'Shop', currency: 'BDT'),
      ),
      transactionRepositoryProvider.overrideWithValue(repo),
      expiryReconcilerProvider.overrideWithValue(NoopReconciler()),
      nowProvider.overrideWithValue(() => DateTime(2026, 10, 14, 1, 30)),
    ],
  );
  addTearDown(c.dispose);
  await c.read(myShopProvider.future);
  return c;
}

void main() {
  test('a retry of the same restock reuses the restock id', () async {
    final repo = _FlakyRestockRepo();
    final c = await _container(repo);
    final n = c.read(transactionControllerProvider.notifier);

    expect(await n.recordRestock(productId: 'p1', quantity: 2), isFalse);
    repo.fail = false;
    expect(await n.recordRestock(productId: 'p1', quantity: 2), isTrue);

    expect(repo.ids, hasLength(2));
    expect(repo.ids[1], repo.ids[0]);
  });

  test('a changed restock gets a new id', () async {
    final repo = _FlakyRestockRepo();
    final c = await _container(repo);
    final n = c.read(transactionControllerProvider.notifier);

    await n.recordRestock(productId: 'p1', quantity: 2);
    await n.recordRestock(productId: 'p1', quantity: 3);
    await n.recordRestock(productId: 'p1', quantity: 3, expiryDate: DateTime(2026, 11, 1));

    expect(repo.ids.toSet(), hasLength(3));
  });

  test('the next restock after a success gets a new id', () async {
    final repo = _FlakyRestockRepo()..fail = false;
    final c = await _container(repo);
    final n = c.read(transactionControllerProvider.notifier);

    await n.recordRestock(productId: 'p1', quantity: 2);
    await n.recordRestock(productId: 'p1', quantity: 2);

    expect(repo.ids[1], isNot(repo.ids[0]));
  });

  test('the expiry date and the phone-local date added are sent', () async {
    final repo = _FlakyRestockRepo()..fail = false;
    final c = await _container(repo);
    await c
        .read(transactionControllerProvider.notifier)
        .recordRestock(productId: 'p1', quantity: 2, expiryDate: DateTime(2026, 11, 1));

    expect(repo.expiries.single, DateTime(2026, 11, 1));
    // 01:30 local on 14 Oct is still 13 Oct in UTC -- the phone's date wins.
    expect(repo.receivedOns.single, DateTime(2026, 10, 14));
  });
}
```

`test/widgets/expiry_date_field_test.dart`:

```dart
import 'package:ai_shopkeeper/features/expiry/presentation/expiry_date_field.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/today_provider.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:ai_shopkeeper/shared/providers/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

Widget _app(Widget child) => ProviderScope(
  overrides: [nowProvider.overrideWithValue(() => DateTime(2026, 10, 14, 9))],
  child: MaterialApp(
    locale: const Locale('en'),
    supportedLocales: supportedAppLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: child),
  ),
);

void main() {
  setUpAll(() => initializeDateFormatting());

  testWidgets('an empty field says Optional', (tester) async {
    await tester.pumpWidget(_app(ExpiryDateField(value: null, onChanged: (_) {})));
    expect(find.text('Expiry date'), findsOneWidget);
    expect(find.text('Optional'), findsOneWidget);
  });

  testWidgets('a set date shows and can be removed', (tester) async {
    DateTime? changed = DateTime(2000);
    await tester.pumpWidget(
      _app(ExpiryDateField(value: DateTime(2026, 10, 20), onChanged: (d) => changed = d)),
    );
    expect(find.text('Oct 20, 2026'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove date'));
    expect(changed, isNull);
  });
}
```

- [ ] **Step 3: Run them to verify they fail**

Run: `flutter test test/restock_idempotency_test.dart test/widgets/expiry_date_field_test.dart`
Expected: compile errors — `restockId` / `expiryDate` parameters and `expiry_date_field.dart` do not exist.

- [ ] **Step 4: Replace `recordRestock` in `TransactionRepository`**

Replace the existing `recordRestock` method **and delete `_callRpc`** (its only caller was `recordRestock`) with:

```dart
  /// Atomic restock via `record_restock` (0011). [restockId] is minted by the
  /// caller and re-sent on a retry: the server records a given id once and
  /// returns the existing row on a repeat, so a lost reply cannot add the
  /// stock twice. With [expiryDate] the delivery is recorded in the same
  /// transaction; [receivedOn] is the PHONE's local date (expiry spec §3.4).
  Future<Result<Transaction>> recordRestock({
    required String shopId,
    required String productId,
    required double quantity,
    required String restockId,
    String source = 'manual',
    DateTime? expiryDate,
    DateTime? receivedOn,
  }) async {
    try {
      final result = await _client.rpc(
        'record_restock',
        params: {
          'p_shop_id': shopId,
          'p_product_id': productId,
          'p_quantity': quantity,
          'p_source': source,
          'p_restock_id': restockId,
          if (expiryDate != null) 'p_expiry_date': ymd(expiryDate),
          if (receivedOn != null) 'p_received_on': ymd(receivedOn),
        },
      );
      // A function `returns transactions` yields a single composite object;
      // some setups return a single-element list. Handle both.
      final row = result is List ? result.first : result;
      return Result.success(
        Transaction.fromJson(Map<String, dynamic>.from(row as Map)),
      );
    } catch (e) {
      return Result.failure(_map(e));
    }
  }
```

Add the import: `import '../../expiry/domain/expiry_dates.dart';`

- [ ] **Step 5: Mint and reuse the restock id in `TransactionController`**

Add imports:

```dart
import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../expiry/domain/expiry_dates.dart';
import '../../expiry/presentation/expiry_providers.dart';
import '../../expiry/presentation/expiry_reconciler.dart';
import '../../expiry/presentation/today_provider.dart';
```

Add fields under `_inFlight`:

```dart
  /// The restock id of the last restock that did not come back as a success,
  /// and the exact request it was sent with -- the `CartCheckoutController`
  /// pattern from 0010. A failure does not prove nothing was saved, so an
  /// identical retry re-sends the id and the server records it once. Anything
  /// changed (product, quantity, date) is a different restock and gets a new
  /// id.
  String? _pendingRestockId;
  String? _pendingRestockRequest;
```

Replace `recordRestock` with:

```dart
  Future<bool> recordRestock({
    required String productId,
    required double quantity,
    String source = 'manual',
    DateTime? expiryDate,
  }) {
    final request = jsonEncode({
      'product': productId,
      'quantity': quantity,
      'source': source,
      'expiry': expiryDate == null ? null : ymd(expiryDate),
    });
    if (request != _pendingRestockRequest) {
      _pendingRestockId = const Uuid().v4();
      _pendingRestockRequest = request;
    }
    final restockId = _pendingRestockId!;
    final receivedOn = dateOnly(ref.read(nowProvider)());
    return _run(
      (shopId) => _repo.recordRestock(
        shopId: shopId,
        productId: productId,
        quantity: quantity,
        restockId: restockId,
        source: source,
        expiryDate: expiryDate,
        receivedOn: receivedOn,
      ),
      onSuccess: () {
        _pendingRestockId = null;
        _pendingRestockRequest = null;
        if (expiryDate != null) ref.invalidate(batchesStreamProvider);
        unawaited(ref.read(expiryReconcilerProvider).run());
      },
    );
  }
```

Change `_run`'s signature and call the hook first in `success`:

```dart
  Future<bool> _run(
    Future<Result<Transaction>> Function(String shopId) action, {
    void Function()? onSuccess,
  }) async {
```

```dart
      success: (_) {
        onSuccess?.call();
        // Refresh inventory immediately so the new stock level shows at once.
```

- [ ] **Step 6: Write `expiry_date_field.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../domain/expiry_dates.dart';
import 'today_provider.dart';

/// Medium date in the app's language ("Oct 20, 2026" / "২০ অক্টো, ২০২৬").
String formatExpiryDate(BuildContext context, DateTime d) =>
    DateFormat.yMMMd(Localizations.localeOf(context).languageCode).format(d);

/// Asks before accepting a past date or one more than five years ahead
/// (spec §5 "Odd dates"). Returns true to keep [picked].
Future<bool> confirmOddExpiryDate(
  BuildContext context,
  DateTime picked,
  DateTime today,
) async {
  final kind = classifyExpiryDate(picked, today);
  if (kind == OddDate.none) return true;
  final l10n = context.l10n;
  final keep = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(
        kind == OddDate.past ? l10n.expiry_pastDateTitle : l10n.expiry_farDateTitle,
      ),
      content: Text(
        kind == OddDate.past
            ? l10n.expiry_pastDateBody
            : l10n.expiry_farDateBody(formatExpiryDate(ctx, picked)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.expiry_changeDate),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l10n.expiry_saveAnyway),
        ),
      ],
    ),
  );
  return keep == true;
}

/// An optional expiry date: tap to pick, ✕ to clear. Odd dates are confirmed.
class ExpiryDateField extends ConsumerWidget {
  const ExpiryDateField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.enabled = true,
  });

  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final String? label;
  final bool enabled;

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final today = ref.read(todayProvider);
    final picked = await showDatePicker(
      context: context,
      initialDate: value ?? today,
      firstDate: DateTime(today.year - 2),
      lastDate: DateTime(today.year + 30),
    );
    if (picked == null || !context.mounted) return;
    if (await confirmOddExpiryDate(context, picked, today)) {
      onChanged(dateOnly(picked));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final date = value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: enabled ? () => _pick(context, ref) : null,
        borderRadius: BorderRadius.circular(8),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label ?? l10n.expiry_dateLabel,
            suffixIcon: date == null
                ? const Icon(Icons.event_outlined)
                : IconButton(
                    tooltip: l10n.expiry_dateClear,
                    icon: const Icon(Icons.close),
                    onPressed: enabled ? () => onChanged(null) : null,
                  ),
          ),
          child: Text(
            date == null ? l10n.expiry_dateOptional : formatExpiryDate(context, date),
            style: date == null
                ? theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  )
                : theme.textTheme.bodyLarge,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 7: Add the field to the restock sheet**

In `transaction_confirmation_sheet.dart`, import `'../../expiry/presentation/expiry_date_field.dart'`, add a field to the state:

```dart
  late double _qty;
  DateTime? _expiry;
  String? _error;
```

pass it in `_confirm`:

```dart
    final ok = await controller.recordRestock(
      productId: _product.id,
      quantity: _qty,
      source: widget.source,
      expiryDate: _expiry,
    );
```

and insert it between the quantity `Row` and `const Divider(height: 24)`:

```dart
          const SizedBox(height: 12),
          ExpiryDateField(
            value: _expiry,
            enabled: !isLoading,
            onChanged: (d) => setState(() => _expiry = d),
          ),
```

- [ ] **Step 8: Update the cart test harness's repository**

In `test/support/cart_harness.dart`, replace `CapturingTransactionRepository.recordRestock` with:

```dart
  @override
  Future<Result<Transaction>> recordRestock({
    required String shopId,
    required String productId,
    required double quantity,
    required String restockId,
    String source = 'manual',
    DateTime? expiryDate,
    DateTime? receivedOn,
  }) async => throw UnimplementedError();
```

- [ ] **Step 9: Run the tests to verify they pass**

Run: `flutter test test/restock_idempotency_test.dart test/widgets/expiry_date_field_test.dart`
Expected: all pass.

Run: `flutter test`
Expected: all pass.

- [ ] **Step 10: Commit**

```bash
git add lib/features/transactions/ lib/features/expiry/presentation/expiry_date_field.dart lib/l10n/ test/support/cart_harness.dart test/restock_idempotency_test.dart test/widgets/expiry_date_field_test.dart
git commit -m "feat(expiry): retry-safe restock with an optional expiry date

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 7: Product form — first delivery's date, warning override, unit guard

**Files:**
- Modify: `lib/features/inventory/presentation/inventory_controller.dart`, `lib/features/inventory/presentation/product_form_screen.dart`, `lib/l10n/app_en.arb`, `lib/l10n/app_bn.arb`
- Test: `test/inventory_save_expiry_test.dart`

**Interfaces:**
- Consumes: `batchRepositoryProvider.addBatch` (Task 4); `nowProvider`, `batchesStreamProvider`, `productExpiryProvider` (Task 5); `ExpiryDateField` (Task 6).
- Produces: `enum ProductSaveOutcome { failed, saved, savedWithoutExpiry }`; `InventoryController.save(Product draft, {required bool isNew, DateTime? expiryDate}) → Future<ProductSaveOutcome>`.

- [ ] **Step 1: Add the strings**

`app_en.arb`:

```json
  "expiry_moreOptions": "More options",
  "expiry_warnDaysLabel": "Warn me this many days before expiry",
  "expiry_warnDaysHint": "Leave empty to let the app decide",
  "expiry_unitChangeBlocked": "Clear this product's deliveries before changing its unit",
  "expiry_savedWithoutDate": "Product saved, but its expiry date wasn't. Add it from the product page."
```

`app_bn.arb`:

```json
  "expiry_moreOptions": "আরও অপশন",
  "expiry_warnDaysLabel": "মেয়াদ শেষের কত দিন আগে জানাবে",
  "expiry_warnDaysHint": "খালি রাখলে অ্যাপ নিজে ঠিক করবে",
  "expiry_unitChangeBlocked": "একক বদলানোর আগে এই পণ্যের ডেলিভারিগুলো বন্ধ করুন",
  "expiry_savedWithoutDate": "পণ্য সংরক্ষিত হয়েছে, কিন্তু মেয়াদের তারিখ হয়নি। পণ্যের পাতা থেকে যোগ করুন।"
```

Run: `flutter gen-l10n`

- [ ] **Step 2: Write the failing test**

`test/inventory_save_expiry_test.dart`:

```dart
import 'package:ai_shopkeeper/core/error/failure.dart';
import 'package:ai_shopkeeper/core/error/result.dart';
import 'package:ai_shopkeeper/features/auth/data/auth_repository.dart';
import 'package:ai_shopkeeper/features/auth/domain/shop.dart';
import 'package:ai_shopkeeper/features/expiry/data/batch_repository.dart';
import 'package:ai_shopkeeper/features/expiry/domain/product_batch.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/today_provider.dart';
import 'package:ai_shopkeeper/features/inventory/data/product_repository.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/inventory/presentation/inventory_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _ProductRepo implements ProductRepository {
  @override
  Future<Result<Product>> addProduct(Product product) async =>
      Result.success(product.copyWith(id: 'new-id'));

  @override
  Future<Result<Product>> updateProduct(Product product) async => Result.success(product);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BatchRepo implements BatchRepository {
  _BatchRepo({this.fail = false});
  final bool fail;
  final added = <Map<String, Object>>[];

  @override
  Future<Result<ProductBatch>> addBatch({
    required String shopId,
    required String productId,
    required double quantity,
    required double buyingPrice,
    required DateTime receivedOn,
    required DateTime expiryDate,
  }) async {
    added.add({
      'productId': productId,
      'quantity': quantity,
      'buyingPrice': buyingPrice,
      'receivedOn': receivedOn,
      'expiryDate': expiryDate,
    });
    if (fail) return const Result.failure(NetworkFailure('offline'));
    return Result.success(
      ProductBatch(
        id: 'b1',
        shopId: shopId,
        productId: productId,
        quantity: quantity,
        receivedOn: receivedOn,
        expiryDate: expiryDate,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<ProviderContainer> _container(_BatchRepo batches) async {
  final c = ProviderContainer(
    overrides: [
      myShopProvider.overrideWith(
        (ref) async => const Shop(id: 's1', ownerId: 'o1', name: 'Shop', currency: 'BDT'),
      ),
      productRepositoryProvider.overrideWithValue(_ProductRepo()),
      batchRepositoryProvider.overrideWithValue(batches),
      nowProvider.overrideWithValue(() => DateTime(2026, 10, 14, 9)),
    ],
  );
  addTearDown(c.dispose);
  await c.read(myShopProvider.future);
  return c;
}

const _bread = Product(id: '', shopId: '', name: 'Bread', quantity: 10, buyingPrice: 40);

void main() {
  test('a new product with an expiry date records its first delivery', () async {
    final batches = _BatchRepo();
    final c = await _container(batches);
    final outcome = await c
        .read(inventoryControllerProvider.notifier)
        .save(_bread, isNew: true, expiryDate: DateTime(2026, 10, 18));

    expect(outcome, ProductSaveOutcome.saved);
    expect(batches.added.single, {
      'productId': 'new-id',
      'quantity': 10.0,
      'buyingPrice': 40.0,
      'receivedOn': DateTime(2026, 10, 14),
      'expiryDate': DateTime(2026, 10, 18),
    });
  });

  test('a failed delivery insert keeps the product and says so', () async {
    final c = await _container(_BatchRepo(fail: true));
    final outcome = await c
        .read(inventoryControllerProvider.notifier)
        .save(_bread, isNew: true, expiryDate: DateTime(2026, 10, 18));
    expect(outcome, ProductSaveOutcome.savedWithoutExpiry);
  });

  test('no delivery for zero stock or for an edit', () async {
    final batches = _BatchRepo();
    final c = await _container(batches);
    final n = c.read(inventoryControllerProvider.notifier);
    await n.save(_bread.copyWith(quantity: 0), isNew: true, expiryDate: DateTime(2026, 10, 18));
    await n.save(_bread.copyWith(id: 'p1'), isNew: false, expiryDate: DateTime(2026, 10, 18));
    expect(batches.added, isEmpty);
  });
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `flutter test test/inventory_save_expiry_test.dart`
Expected: compile error — `save` has no `expiryDate` parameter / `ProductSaveOutcome` undefined.

- [ ] **Step 4: Change `InventoryController.save`**

Add imports to `inventory_controller.dart`:

```dart
import '../../../core/error/result.dart';
import '../../expiry/data/batch_repository.dart';
import '../../expiry/domain/expiry_dates.dart';
import '../../expiry/presentation/expiry_providers.dart';
import '../../expiry/presentation/today_provider.dart';
```

Add above the class:

```dart
enum ProductSaveOutcome { failed, saved, savedWithoutExpiry }
```

Replace `save` with:

```dart
  /// Saves a product. `draft` carries the form values; the shop id is injected
  /// here so the form never has to know it.
  ///
  /// A NEW product with [expiryDate] and stock above 0 also records its first
  /// delivery. That is a second insert after the product's, so it can fail on
  /// its own: the product then stays saved and the outcome says the date
  /// wasn't (expiry spec §3.3), so the form can tell the shopkeeper to add it
  /// from the product page.
  Future<ProductSaveOutcome> save(
    Product draft, {
    required bool isNew,
    DateTime? expiryDate,
  }) async {
    final shopId = _shopId;
    if (shopId == null) {
      state = AsyncError(
        const AuthFailure('No shop found for this account.'),
        StackTrace.current,
      );
      return ProductSaveOutcome.failed;
    }

    state = const AsyncLoading();
    final result = isNew
        ? await _repo.addProduct(draft.copyWith(shopId: shopId))
        : await _repo.updateProduct(draft);

    switch (result) {
      case ResultFailure(:final failure):
        state = AsyncError(failure, StackTrace.current);
        return ProductSaveOutcome.failed;
      case Success(value: final saved):
        var outcome = ProductSaveOutcome.saved;
        if (isNew && expiryDate != null && saved.quantity > 0) {
          final batch = await ref.read(batchRepositoryProvider).addBatch(
            shopId: shopId,
            productId: saved.id,
            quantity: saved.quantity,
            buyingPrice: saved.buyingPrice,
            receivedOn: dateOnly(ref.read(nowProvider)()),
            expiryDate: expiryDate,
          );
          if (batch.isSuccess) {
            ref.invalidate(batchesStreamProvider);
          } else {
            outcome = ProductSaveOutcome.savedWithoutExpiry;
          }
        }
        // Refresh the list immediately. Realtime normally pushes this change,
        // but invalidating guarantees the user's own write is reflected even if
        // realtime is momentarily unavailable or not yet enabled on the table.
        ref.invalidate(productsStreamProvider);
        state = const AsyncData(null);
        return outcome;
    }
  }
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/inventory_save_expiry_test.dart`
Expected: pass. (The form does not compile yet if `flutter analyze` is run now — Step 6 fixes it.)

- [ ] **Step 6: Update the product form**

In `product_form_screen.dart`, import:

```dart
import '../../expiry/presentation/expiry_date_field.dart';
import '../../expiry/presentation/expiry_providers.dart';
```

State fields — add under `_reorder`:

```dart
  late final TextEditingController _warnDays;

  /// The first delivery's expiry date (new products only, spec §5).
  DateTime? _expiryDate;
```

In `initState`, after `_reorder = ...`:

```dart
    _warnDays = TextEditingController(text: p?.expiryWarnDays?.toString() ?? '');
    // The expiry field only shows while quantity > 0 (a 0-quantity delivery
    // is rejected by the database), so rebuild as the quantity is typed.
    _quantity.addListener(_onQuantityChanged);
```

Add the method and dispose:

```dart
  void _onQuantityChanged() {
    if (mounted) setState(() {});
  }
```

```dart
    _quantity.removeListener(_onQuantityChanged);
    _quantity.dispose();
```

```dart
    _warnDays.dispose();
```

In `_save`, add to the `copyWith`:

```dart
      expiryWarnDays: _warnDays.text.trim().isEmpty
          ? null
          : int.parse(_warnDays.text.trim()),
```

and replace the tail of `_save` (from `final ok = await ref` to the end) with:

```dart
    final outcome = await ref
        .read(inventoryControllerProvider.notifier)
        .save(draft, isNew: widget.isNew, expiryDate: _expiryDate);

    if (!mounted || outcome == ProductSaveOutcome.failed) return;
    if (outcome == ProductSaveOutcome.savedWithoutExpiry) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.expiry_savedWithoutDate)),
      );
    }
    Navigator.of(context).pop();
```

Add a validator next to `_moneyField`:

```dart
  /// Optional whole number of days (the formatter already allows digits only).
  String? _optionalWholeDays(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    return int.tryParse(v.trim()) == null ? context.l10n.form_wholeNumberOnly : null;
  }

  void _unitChangeBlocked() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(context.l10n.expiry_unitChangeBlocked)));
  }
```

In `build`, after `final perUnit = ...`:

```dart
    // A product with open deliveries keeps its unit: their amounts are in it.
    final hasDeliveries = !widget.isNew &&
        ref.watch(productExpiryProvider).containsKey(widget.product!.id);
    final quantityTyped = double.tryParse(_quantity.text.trim()) ?? 0;
```

Change the two unit callbacks:

```dart
                    onChanged: (t) => hasDeliveries
                        ? _unitChangeBlocked()
                        : ref.read(productFormUnitProvider.notifier).selectType(t),
```

```dart
                        onUnitChanged: (u) => hasDeliveries
                            ? _unitChangeBlocked()
                            : ref.read(productFormUnitProvider.notifier).selectUnit(u),
```

After the stock + reorder `Row` (before `// Per-unit prices.`):

```dart
                if (widget.isNew && quantityTyped > 0)
                  ExpiryDateField(
                    value: _expiryDate,
                    enabled: !isLoading,
                    onChanged: (d) => setState(() => _expiryDate = d),
                  ),
```

Before `const SizedBox(height: 8),` that precedes the save button:

```dart
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(l10n.expiry_moreOptions),
                    initiallyExpanded: widget.product?.expiryWarnDays != null,
                    children: [
                      _field(
                        _warnDays,
                        l10n.expiry_warnDaysLabel,
                        helperText: l10n.expiry_warnDaysHint,
                        keyboardType: _numberKeyboard(false),
                        inputFormatters: _numberFormatters(false),
                        textInputAction: TextInputAction.done,
                        validator: _optionalWholeDays,
                      ),
                    ],
                  ),
                ),
```

Give `_field` a `helperText` parameter:

```dart
    String? suffixText,
    String? helperText,
```

```dart
        decoration: InputDecoration(
          labelText: label,
          suffixText: suffixText,
          helperText: helperText,
        ),
```

- [ ] **Step 7: Analyze and run the suite**

Run: `flutter analyze` — Expected: `No issues found!`
Run: `flutter test` — Expected: all pass.

- [ ] **Step 8: Commit**

```bash
git add lib/features/inventory/presentation/ lib/l10n/ test/inventory_save_expiry_test.dart
git commit -m "feat(expiry): expiry date and warning override on the product form

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Product page — Deliveries section and actions

**Files:**
- Create: `lib/features/expiry/presentation/batch_actions_controller.dart`, `batch_form_sheet.dart`, `deliveries_section.dart`
- Modify: `lib/features/inventory/presentation/product_detail_screen.dart`, `lib/l10n/app_en.arb`, `lib/l10n/app_bn.arb`
- Test: `test/batch_actions_controller_test.dart`, `test/widgets/deliveries_section_test.dart`

**Interfaces:**
- Consumes: `BatchRepository` (Task 4); `todayProvider`, `nowProvider`, `batchesStreamProvider`, `closedBatchesProvider`, `latestRestockDateProvider`, `productExpiryProvider`, `goodStockProvider`, `expiryReconcilerProvider` (Task 5); `ExpiryDateField`, `formatExpiryDate` (Task 6).
- Produces: `batchActionsControllerProvider` (`BatchActionsController`): `addBatch({required Product product, required double quantity, required DateTime expiryDate, required DateTime receivedOn})`, `editBatch(ProductBatch batch, {required double quantity, required DateTime expiryDate})`, `markNoneLeft(String batchId)`, `markNotExpired(List<String> batchIds)`, `removeExpired(List<String> batchIds)` — each `Future<bool>`. `showBatchFormSheet(BuildContext, {required Product product, ProductBatch? batch})`. `DeliveriesSection({required Product product})`.

- [ ] **Step 1: Add the strings**

`app_en.arb`:

```json
  "expiry_deliveries": "Deliveries",
  "expiry_addDate": "Add expiry date",
  "expiry_rowDates": "Added {added} · Expires {expiry}",
  "@expiry_rowDates": { "placeholders": { "added": { "type": "String" }, "expiry": { "type": "String" } } },
  "expiry_rowLeft": "About {qty} {unit} left",
  "@expiry_rowLeft": { "placeholders": { "qty": { "type": "String" }, "unit": { "type": "String" } } },
  "expiry_statusGood": "Good",
  "expiry_statusSoon": "Expiring soon",
  "expiry_statusExpired": "Expired",
  "expiry_removeFromStock": "Remove from stock",
  "expiry_noneLeft": "None left",
  "expiry_closedHistory": "Closed",
  "expiry_closedSoldOut": "Sold out",
  "expiry_closedRemoved": "Removed (expired)",
  "expiry_closedNoneLeft": "Marked none left",
  "expiry_closedNotExpired": "Marked not expired",
  "expiry_formAddTitle": "Add expiry date",
  "expiry_formEditTitle": "Edit delivery",
  "expiry_formAmount": "Amount",
  "expiry_formReceived": "Date added",
  "expiry_amountInvalid": "Enter an amount above 0",
  "expiry_dateRequired": "Choose an expiry date",
  "expiry_removeConfirmTitle": "Remove {qty} {unit} of {name}?",
  "@expiry_removeConfirmTitle": { "placeholders": { "qty": { "type": "String" }, "unit": { "type": "String" }, "name": { "type": "String" } } },
  "expiry_removeConfirmBody": "Stock goes down and the loss is recorded. Your sales figures don't change.",
  "expiry_removed": "Expired stock removed"
```

`app_bn.arb`:

```json
  "expiry_deliveries": "ডেলিভারি",
  "expiry_addDate": "মেয়াদের তারিখ যোগ করুন",
  "expiry_rowDates": "যোগ {added} · মেয়াদ {expiry}",
  "@expiry_rowDates": { "placeholders": { "added": { "type": "String" }, "expiry": { "type": "String" } } },
  "expiry_rowLeft": "আনুমানিক {qty} {unit} বাকি",
  "@expiry_rowLeft": { "placeholders": { "qty": { "type": "String" }, "unit": { "type": "String" } } },
  "expiry_statusGood": "ভালো",
  "expiry_statusSoon": "মেয়াদ শেষ হচ্ছে",
  "expiry_statusExpired": "মেয়াদোত্তীর্ণ",
  "expiry_removeFromStock": "স্টক থেকে বাদ দিন",
  "expiry_noneLeft": "আর নেই",
  "expiry_closedHistory": "বন্ধ",
  "expiry_closedSoldOut": "বিক্রি শেষ",
  "expiry_closedRemoved": "বাদ দেওয়া হয়েছে (মেয়াদোত্তীর্ণ)",
  "expiry_closedNoneLeft": "আর নেই হিসেবে চিহ্নিত",
  "expiry_closedNotExpired": "মেয়াদ শেষ নয় হিসেবে চিহ্নিত",
  "expiry_formAddTitle": "মেয়াদের তারিখ যোগ করুন",
  "expiry_formEditTitle": "ডেলিভারি সম্পাদনা",
  "expiry_formAmount": "পরিমাণ",
  "expiry_formReceived": "যোগের তারিখ",
  "expiry_amountInvalid": "০-এর বেশি পরিমাণ লিখুন",
  "expiry_dateRequired": "মেয়াদের তারিখ বেছে নিন",
  "expiry_removeConfirmTitle": "{name}-এর {qty} {unit} বাদ দেবেন?",
  "@expiry_removeConfirmTitle": { "placeholders": { "qty": { "type": "String" }, "unit": { "type": "String" }, "name": { "type": "String" } } },
  "expiry_removeConfirmBody": "স্টক কমবে এবং ক্ষতি লেখা থাকবে। বিক্রির হিসাব বদলাবে না।",
  "expiry_removed": "মেয়াদোত্তীর্ণ স্টক বাদ দেওয়া হয়েছে"
```

Run: `flutter gen-l10n`

- [ ] **Step 2: Write the failing controller test**

`test/batch_actions_controller_test.dart`:

```dart
import 'package:ai_shopkeeper/core/error/failure.dart';
import 'package:ai_shopkeeper/core/error/result.dart';
import 'package:ai_shopkeeper/features/auth/data/auth_repository.dart';
import 'package:ai_shopkeeper/features/auth/domain/shop.dart';
import 'package:ai_shopkeeper/features/expiry/data/batch_repository.dart';
import 'package:ai_shopkeeper/features/expiry/domain/product_batch.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/batch_actions_controller.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/expiry_reconciler.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/today_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/expiry_fakes.dart';

class _Repo implements BatchRepository {
  _Repo({this.fail = false});
  final bool fail;
  final log = <String>[];

  Result<void> get _r => fail
      ? const Result.failure(NetworkFailure('offline'))
      : const Result.success(null);

  @override
  Future<Result<void>> updateBatch({
    required String batchId,
    required double quantity,
    required DateTime expiryDate,
    required bool clearLock,
  }) async {
    log.add('update $batchId clearLock=$clearLock');
    return _r;
  }

  @override
  Future<Result<void>> closeBatch(String batchId, String reason) async {
    log.add('close $batchId $reason');
    return _r;
  }

  @override
  Future<Result<void>> removeExpiredStock({required String shopId, required String batchId}) async {
    log.add('remove $shopId $batchId');
    return _r;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _locked = ProductBatch(
  id: 'b1',
  shopId: 's1',
  productId: 'p1',
  quantity: 5,
  receivedOn: DateTime(2026, 10, 1),
  expiryDate: DateTime(2026, 10, 2),
  expiredQty: 5,
);

Future<ProviderContainer> _container(_Repo repo) async {
  final c = ProviderContainer(
    overrides: [
      myShopProvider.overrideWith(
        (ref) async => const Shop(id: 's1', ownerId: 'o1', name: 'Shop', currency: 'BDT'),
      ),
      batchRepositoryProvider.overrideWithValue(repo),
      expiryReconcilerProvider.overrideWithValue(NoopReconciler()),
      nowProvider.overrideWithValue(() => DateTime(2026, 10, 14, 9)),
    ],
  );
  addTearDown(c.dispose);
  await c.read(myShopProvider.future);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('correcting a mistyped date into the future clears the lock', () async {
    final repo = _Repo();
    final c = await _container(repo);
    await c
        .read(batchActionsControllerProvider.notifier)
        .editBatch(_locked, quantity: 5, expiryDate: DateTime(2026, 10, 20));
    expect(repo.log, ['update b1 clearLock=true']);
  });

  test('a date still in the past keeps the lock', () async {
    final repo = _Repo();
    final c = await _container(repo);
    await c
        .read(batchActionsControllerProvider.notifier)
        .editBatch(_locked, quantity: 5, expiryDate: DateTime(2026, 10, 5));
    expect(repo.log, ['update b1 clearLock=false']);
  });

  test('they-are-not-expired closes each expired delivery with that reason', () async {
    final repo = _Repo();
    final c = await _container(repo);
    await c.read(batchActionsControllerProvider.notifier).markNotExpired(['b1', 'b2']);
    expect(repo.log, ['close b1 not_expired', 'close b2 not_expired']);
  });

  test('remove expired calls the server once per delivery with the shop', () async {
    final repo = _Repo();
    final c = await _container(repo);
    final ok = await c.read(batchActionsControllerProvider.notifier).removeExpired(['b1']);
    expect(ok, isTrue);
    expect(repo.log, ['remove s1 b1']);
  });

  test('a failure is reported and surfaced as an error state', () async {
    final c = await _container(_Repo(fail: true));
    final ok = await c.read(batchActionsControllerProvider.notifier).markNoneLeft('b1');
    expect(ok, isFalse);
    expect(c.read(batchActionsControllerProvider).error, isA<NetworkFailure>());
  });
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `flutter test test/batch_actions_controller_test.dart`
Expected: compile error — `batch_actions_controller.dart` does not exist.

- [ ] **Step 4: Write `batch_actions_controller.dart`**

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../../shared/providers/refresh_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../../inventory/domain/product.dart';
import '../../inventory/presentation/inventory_controller.dart';
import '../data/batch_repository.dart';
import '../domain/expiry_dates.dart';
import '../domain/product_batch.dart';
import 'expiry_providers.dart';
import 'expiry_reconciler.dart';
import 'today_provider.dart';

/// The shopkeeper's actions on deliveries (spec §3.3, §3.2). Models the
/// in-flight action only; screens watch `isLoading` and listen for errors.
class BatchActionsController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  BatchRepository get _repo => ref.read(batchRepositoryProvider);

  Future<bool> addBatch({
    required Product product,
    required double quantity,
    required DateTime expiryDate,
    required DateTime receivedOn,
  }) => _run(() async {
    final r = await _repo.addBatch(
      shopId: product.shopId,
      productId: product.id,
      quantity: quantity,
      buyingPrice: product.buyingPrice,
      receivedOn: receivedOn,
      expiryDate: expiryDate,
    );
    return r.when(
      success: (_) => const Result<void>.success(null),
      failure: (f) => Result<void>.failure(f),
    );
  });

  /// Moving a locked delivery's date to today or later clears the lock -- the
  /// lock came from a mistyped date (spec §3.3).
  Future<bool> editBatch(
    ProductBatch batch, {
    required double quantity,
    required DateTime expiryDate,
  }) {
    final today = ref.read(todayProvider);
    final clearLock =
        batch.expiredQty != null && !today.isAfter(dateOnly(expiryDate));
    return _run(
      () => _repo.updateBatch(
        batchId: batch.id,
        quantity: quantity,
        expiryDate: expiryDate,
        clearLock: clearLock,
      ),
    );
  }

  Future<bool> markNoneLeft(String batchId) =>
      _run(() => _repo.closeBatch(batchId, BatchCloseReason.noneLeft));

  /// The escape hatch when the estimate is wrong: the expired deliveries are
  /// closed, so their units count as good stock again.
  Future<bool> markNotExpired(List<String> batchIds) => _run(() async {
    for (final id in batchIds) {
      final r = await _repo.closeBatch(id, BatchCloseReason.notExpired);
      if (r.isFailure) return r;
    }
    return const Result.success(null);
  });

  Future<bool> removeExpired(List<String> batchIds) {
    final shopId = ref.read(myShopProvider).value?.id;
    if (shopId == null) {
      state = AsyncError(
        const AuthFailure('No shop found for this account.'),
        StackTrace.current,
      );
      return Future.value(false);
    }
    return _run(stockChanged: true, () async {
      for (final id in batchIds) {
        final r = await _repo.removeExpiredStock(shopId: shopId, batchId: id);
        if (r.isFailure) return r;
      }
      return const Result.success(null);
    });
  }

  Future<bool> _run(
    Future<Result<void>> Function() action, {
    bool stockChanged = false,
  }) async {
    state = const AsyncLoading();
    final result = await action();
    switch (result) {
      case ResultFailure(:final failure):
        state = AsyncError(failure, StackTrace.current);
        return false;
      case Success():
        ref.invalidate(batchesStreamProvider);
        ref.invalidate(closedBatchesProvider);
        if (stockChanged) {
          ref.invalidate(productsStreamProvider);
          ref.read(dataRefreshProvider.notifier).bump();
        }
        unawaited(ref.read(expiryReconcilerProvider).run());
        state = const AsyncData(null);
        return true;
    }
  }
}

final batchActionsControllerProvider =
    AsyncNotifierProvider<BatchActionsController, void>(BatchActionsController.new);
```

- [ ] **Step 5: Run the controller test to verify it passes**

Run: `flutter test test/batch_actions_controller_test.dart`
Expected: all pass.

- [ ] **Step 6: Write `batch_form_sheet.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../inventory/domain/product.dart';
import '../domain/expiry_dates.dart';
import '../domain/product_batch.dart';
import 'batch_actions_controller.dart';
import 'expiry_date_field.dart';
import 'expiry_providers.dart';
import 'today_provider.dart';

/// Add an expiry date to stock already on the shelf ([batch] null), or edit a
/// delivery. Returns true when saved.
Future<bool?> showBatchFormSheet(
  BuildContext context, {
  required Product product,
  ProductBatch? batch,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (_) => _BatchFormSheet(product: product, batch: batch),
  );
}

class _BatchFormSheet extends ConsumerStatefulWidget {
  const _BatchFormSheet({required this.product, this.batch});

  final Product product;
  final ProductBatch? batch;

  @override
  ConsumerState<_BatchFormSheet> createState() => _BatchFormSheetState();
}

class _BatchFormSheetState extends ConsumerState<_BatchFormSheet> {
  late final TextEditingController _amount;
  DateTime? _expiry;
  DateTime? _received;
  String? _error;

  bool get _isEdit => widget.batch != null;

  @override
  void initState() {
    super.initState();
    final b = widget.batch;
    _expiry = b?.expiryDate;
    _received = b?.receivedOn;
    _amount = TextEditingController(text: _plain(b?.quantity ?? _uncovered()));
  }

  /// Stock not yet covered by an open delivery -- the default amount when
  /// adding a date to stock already on the shelf (spec §3.3).
  double _uncovered() {
    final e = ref.read(productExpiryProvider)[widget.product.id];
    final covered = e == null ? 0.0 : e.batches.fold<double>(0, (s, b) => s + b.left);
    final rest = widget.product.quantity - covered;
    return rest > 0 ? rest : widget.product.quantity;
  }

  /// Plain ASCII digits for the text field (see add_to_cart_sheet: `Qty.format`
  /// localises digits, which `double.tryParse` cannot read back).
  String _plain(double v) => v == v.roundToDouble()
      ? v.toStringAsFixed(0)
      : v.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickReceived() async {
    final today = ref.read(todayProvider);
    final picked = await showDatePicker(
      context: context,
      initialDate: _received ?? today,
      firstDate: DateTime(today.year - 5),
      lastDate: today,
    );
    if (picked != null) setState(() => _received = dateOnly(picked));
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final qty = double.tryParse(_amount.text.trim()) ?? 0;
    final wholeOnly = !widget.product.unitType.allowsDecimal;
    if (qty <= 0 || (wholeOnly && qty != qty.roundToDouble())) {
      setState(() => _error = l10n.expiry_amountInvalid);
      return;
    }
    final expiry = _expiry;
    if (expiry == null) {
      setState(() => _error = l10n.expiry_dateRequired);
      return;
    }
    setState(() => _error = null);
    final actions = ref.read(batchActionsControllerProvider.notifier);
    final ok = _isEdit
        ? await actions.editBatch(widget.batch!, quantity: qty, expiryDate: expiry)
        : await actions.addBatch(
            product: widget.product,
            quantity: qty,
            expiryDate: expiry,
            receivedOn: _received ?? ref.read(todayProvider),
          );
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final isLoading = ref.watch(batchActionsControllerProvider).isLoading;

    // Default "date added" for existing stock: the latest restock, else the
    // day the product was created, else today (spec §4.3 -- today would shrink
    // a long shelf life and the warning with it).
    if (!_isEdit && _received == null) {
      final latest = ref.watch(latestRestockDateProvider(widget.product.id));
      final fallback = widget.product.createdAt == null
          ? ref.read(todayProvider)
          : dateOnly(widget.product.createdAt!.toLocal());
      if (!latest.isLoading) _received = latest.value ?? fallback;
    }

    ref.listen<AsyncValue<void>>(batchActionsControllerProvider, (_, next) {
      if (next is AsyncError) {
        setState(() {
          _error = switch (next.error) {
            Failure(:final message) => message,
            _ => l10n.common_somethingWrong,
          };
        });
      }
    });

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _isEdit ? l10n.expiry_formEditTitle : l10n.expiry_formAddTitle,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(widget.product.name, style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),
          TextField(
            controller: _amount,
            enabled: !isLoading,
            keyboardType: TextInputType.numberWithOptions(
              decimal: widget.product.unitType.allowsDecimal,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                widget.product.unitType.allowsDecimal ? RegExp(r'[0-9.]') : RegExp(r'[0-9]'),
              ),
            ],
            decoration: InputDecoration(
              labelText: l10n.expiry_formAmount,
              suffixText: widget.product.unitLabel,
            ),
          ),
          const SizedBox(height: 16),
          ExpiryDateField(
            value: _expiry,
            enabled: !isLoading,
            onChanged: (d) => setState(() => _expiry = d),
          ),
          if (!_isEdit)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.expiry_formReceived),
              trailing: Text(
                _received == null ? '' : formatExpiryDate(context, _received!),
                style: theme.textTheme.bodyLarge,
              ),
              onTap: isLoading ? null : _pickReceived,
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: isLoading ? null : () => Navigator.of(context).pop(false),
                  child: Text(l10n.common_cancel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: isLoading ? null : _save,
                  child: Text(l10n.common_save),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 7: Write the failing widget test for the section**

`test/widgets/deliveries_section_test.dart`:

```dart
import 'package:ai_shopkeeper/core/config/theme.dart';
import 'package:ai_shopkeeper/core/error/result.dart';
import 'package:ai_shopkeeper/features/expiry/data/batch_repository.dart';
import 'package:ai_shopkeeper/features/expiry/domain/expiry_estimate.dart';
import 'package:ai_shopkeeper/features/expiry/domain/product_batch.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/deliveries_section.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/expiry_providers.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/today_provider.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:ai_shopkeeper/shared/providers/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';

class _Repo implements BatchRepository {
  @override
  Future<Result<List<ProductBatch>>> fetchClosedBatches(String productId, {int limit = 10}) async =>
      const Result.success([]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _pepsi = Product(id: 'pepsi', shopId: 's1', name: 'Pepsi', quantity: 15);

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting();
  });

  testWidgets('an expired delivery offers Remove from stock, a good one does not', (tester) async {
    final today = DateTime(2026, 10, 21);
    final byProduct = estimateAll(
      products: [_pepsi],
      openBatches: [
        ProductBatch(
          id: 'old',
          shopId: 's1',
          productId: 'pepsi',
          quantity: 5,
          receivedOn: DateTime(2026, 10, 1),
          expiryDate: DateTime(2026, 10, 20),
          expiredQty: 5,
        ),
        ProductBatch(
          id: 'new',
          shopId: 's1',
          productId: 'pepsi',
          quantity: 10,
          receivedOn: DateTime(2026, 10, 10),
          expiryDate: DateTime(2026, 12, 15),
        ),
      ],
      today: today,
      shopWarnDays: 7,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          productExpiryProvider.overrideWithValue(byProduct),
          batchRepositoryProvider.overrideWithValue(_Repo()),
          nowProvider.overrideWithValue(() => today),
        ],
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
          home: const Scaffold(
            body: SingleChildScrollView(child: DeliveriesSection(product: _pepsi)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Deliveries'), findsOneWidget);
    expect(find.text('Expired'), findsOneWidget);
    expect(find.text('Good'), findsOneWidget);
    expect(find.text('Remove from stock'), findsOneWidget);
    expect(find.text('Added Oct 1, 2026 · Expires Oct 20, 2026'), findsOneWidget);
  });
}
```

- [ ] **Step 8: Run it to verify it fails**

Run: `flutter test test/widgets/deliveries_section_test.dart`
Expected: compile error — `deliveries_section.dart` does not exist.

- [ ] **Step 9: Write `deliveries_section.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/theme.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../shared/extensions/format.dart';
import '../../inventory/domain/product.dart';
import '../domain/expiry_estimate.dart';
import '../domain/product_batch.dart';
import 'batch_actions_controller.dart';
import 'batch_form_sheet.dart';
import 'expiry_date_field.dart';
import 'expiry_providers.dart';

/// The product page's Deliveries list (spec §5): each open delivery with its
/// dates, estimated amount left and status, plus a short closed history.
class DeliveriesSection extends ConsumerWidget {
  const DeliveriesSection({super.key, required this.product});

  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final expiry = ref.watch(productExpiryProvider)[product.id];
    final closed = ref.watch(closedBatchesProvider(product.id)).value ?? const <ProductBatch>[];
    final open = expiry?.batches ?? const <BatchEstimate>[];

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.expiry_deliveries, style: theme.textTheme.titleMedium),
          for (final e in open) _DeliveryRow(product: product, estimate: e),
          if (product.quantity > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => showBatchFormSheet(context, product: product),
                icon: const Icon(Icons.event_available_outlined, size: 18),
                label: Text(l10n.expiry_addDate),
              ),
            ),
          if (closed.isNotEmpty)
            Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(l10n.expiry_closedHistory, style: theme.textTheme.bodyMedium),
                children: [
                  for (final b in closed)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(_closedLabel(context, b.closedReason)),
                      subtitle: Text(
                        l10n.expiry_rowDates(
                          formatExpiryDate(context, b.receivedOn),
                          formatExpiryDate(context, b.expiryDate),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _closedLabel(BuildContext context, String? reason) {
    final l10n = context.l10n;
    return switch (reason) {
      BatchCloseReason.removed => l10n.expiry_closedRemoved,
      BatchCloseReason.noneLeft => l10n.expiry_closedNoneLeft,
      BatchCloseReason.notExpired => l10n.expiry_closedNotExpired,
      _ => l10n.expiry_closedSoldOut,
    };
  }
}

class _DeliveryRow extends ConsumerWidget {
  const _DeliveryRow({required this.product, required this.estimate});

  final Product product;
  final BatchEstimate estimate;

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          l10n.expiry_removeConfirmTitle(
            Qty.format(estimate.left),
            product.unitLabel,
            product.name,
          ),
        ),
        content: Text(l10n.expiry_removeConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.common_cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.expiry_removeFromStock),
          ),
        ],
      ),
    );
    if (yes != true) return;
    final ok = await ref
        .read(batchActionsControllerProvider.notifier)
        .removeExpired([estimate.batch.id]);
    if (ok) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.expiry_removed)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final busy = ref.watch(batchActionsControllerProvider).isLoading;
    final b = estimate.batch;

    final (label, color) = switch (estimate.status) {
      BatchStatus.expired => (l10n.expiry_statusExpired, colors.negative),
      BatchStatus.expiringSoon => (l10n.expiry_statusSoon, colors.warning),
      _ => (l10n.expiry_statusGood, colors.positive),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.expiry_rowDates(
                        formatExpiryDate(context, b.receivedOn),
                        formatExpiryDate(context, b.expiryDate),
                      ),
                      style: theme.textTheme.bodyMedium,
                    ),
                    Text(
                      l10n.expiry_rowLeft(Qty.format(estimate.left), product.unitLabel),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
              PopupMenuButton<String>(
                enabled: !busy,
                onSelected: (v) {
                  if (v == 'edit') {
                    showBatchFormSheet(context, product: product, batch: b);
                  } else {
                    ref.read(batchActionsControllerProvider.notifier).markNoneLeft(b.id);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit', child: Text(l10n.common_edit)),
                  PopupMenuItem(value: 'none', child: Text(l10n.expiry_noneLeft)),
                ],
              ),
            ],
          ),
          if (estimate.status == BatchStatus.expired)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36)),
              onPressed: busy ? null : () => _confirmRemove(context, ref),
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              label: Text(l10n.expiry_removeFromStock),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 10: Put the section and the good-stock low check on the product page**

In `product_detail_screen.dart`, import:

```dart
import '../../expiry/presentation/deliveries_section.dart';
import '../../expiry/presentation/expiry_providers.dart';
```

In `_DetailView.build`, before `return Scaffold(`:

```dart
    // Low stock judges GOOD stock: 5 expired + 1 good is low (spec §5).
    final isLow = product.isLowStockAt(ref.watch(goodStockProvider(product)));
```

Change `if (product.isLowStock) ...[` to `if (isLow) ...[`, and add after the last `_statTile(...)` (reorder threshold) in the `ListView` children:

```dart
          DeliveriesSection(product: product),
```

- [ ] **Step 11: Run the tests**

Run: `flutter test test/widgets/deliveries_section_test.dart test/batch_actions_controller_test.dart`
Expected: pass.
Run: `flutter analyze` — Expected: `No issues found!`
Run: `flutter test` — Expected: all pass.

- [ ] **Step 12: Commit**

```bash
git add lib/features/expiry/presentation/ lib/features/inventory/presentation/product_detail_screen.dart lib/l10n/ test/batch_actions_controller_test.dart test/widgets/deliveries_section_test.dart
git commit -m "feat(expiry): deliveries on the product page with edit, none-left and removal

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 9: Cart — good-stock limits, the expired block, and the checkout gate

**Files:**
- Modify: `lib/features/cart/domain/cart_math.dart`, `lib/features/cart/presentation/cart_controller.dart`, `add_to_cart_sheet.dart`, `cart_screen.dart`, `cart_checkout_controller.dart`, `lib/features/voice/presentation/voice_review_sheet.dart`, `lib/core/error/failure.dart`, `lib/core/l10n/failure_text.dart`, `test/support/cart_harness.dart`, `test/cart_checkout_guard_test.dart`, `lib/l10n/app_en.arb`, `lib/l10n/app_bn.arb`
- Test: `test/cart_checkout_expiry_test.dart`, `test/cart_math_good_stock_test.dart`

**Interfaces:**
- Consumes: `goodStockProvider`, `productExpiryProvider`, `cartLineNoticesProvider`, `expiryGateProvider`, `expiryReconcilerProvider` (Task 5); `ExpiredStockNotice`, `OverStockNotice` (Task 3); `batchActionsControllerProvider` (Task 8); fakes `PassingExpiryGate`, `FixedGate`, `NoopReconciler`.
- Produces: `remainingStockForLines(lines, product, {double? stock})`; `CartController.remainingStockFor(product, {double? stock})`; `ServerErrorCodes.expiredStockInCart`; `cartContainer({TransactionRepository? repo, ExpiryGate gate = const PassingExpiryGate()})`.

- [ ] **Step 1: Add the strings**

`app_en.arb`:

```json
  "expiry_cartOnlyGood": "Only {good} good {name} left ({expired} expired)",
  "@expiry_cartOnlyGood": { "placeholders": { "good": { "type": "String" }, "name": { "type": "String" }, "expired": { "type": "String" } } },
  "expiry_cartOnlyExpired": "Only expired {name} left ({expired})",
  "@expiry_cartOnlyExpired": { "placeholders": { "name": { "type": "String" }, "expired": { "type": "String" } } },
  "expiry_cartRemoveExpired": "Remove expired",
  "expiry_cartNotExpired": "They're not expired",
  "expiry_cartOnlyLeft": "Only {qty} {unit} left",
  "@expiry_cartOnlyLeft": { "placeholders": { "qty": { "type": "String" }, "unit": { "type": "String" } } },
  "expiry_addSheetExpiredNote": "{qty} {unit} expired — not counted",
  "@expiry_addSheetExpiredNote": { "placeholders": { "qty": { "type": "String" }, "unit": { "type": "String" } } },
  "error_expiredStockInCart": "Some items in the cart are expired. Fix them before checkout."
```

`app_bn.arb`:

```json
  "expiry_cartOnlyGood": "ভালো {name} মাত্র {good} বাকি ({expired} মেয়াদোত্তীর্ণ)",
  "@expiry_cartOnlyGood": { "placeholders": { "good": { "type": "String" }, "name": { "type": "String" }, "expired": { "type": "String" } } },
  "expiry_cartOnlyExpired": "শুধু মেয়াদোত্তীর্ণ {name} বাকি ({expired})",
  "@expiry_cartOnlyExpired": { "placeholders": { "name": { "type": "String" }, "expired": { "type": "String" } } },
  "expiry_cartRemoveExpired": "মেয়াদোত্তীর্ণ বাদ দিন",
  "expiry_cartNotExpired": "মেয়াদ শেষ হয়নি",
  "expiry_cartOnlyLeft": "মাত্র {qty} {unit} বাকি",
  "@expiry_cartOnlyLeft": { "placeholders": { "qty": { "type": "String" }, "unit": { "type": "String" } } },
  "expiry_addSheetExpiredNote": "{qty} {unit} মেয়াদোত্তীর্ণ — গণনা হয়নি",
  "@expiry_addSheetExpiredNote": { "placeholders": { "qty": { "type": "String" }, "unit": { "type": "String" } } },
  "error_expiredStockInCart": "কার্টের কিছু পণ্যের মেয়াদ শেষ। চেকআউটের আগে ঠিক করুন।"
```

Run: `flutter gen-l10n`

- [ ] **Step 2: Stub the gate in the existing checkout harnesses**

In `test/support/cart_harness.dart`, add imports:

```dart
import 'package:ai_shopkeeper/features/expiry/presentation/expiry_gate.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/expiry_reconciler.dart';

import 'expiry_fakes.dart';
```

and change `cartContainer`:

```dart
Future<ProviderContainer> cartContainer({
  TransactionRepository? repo,
  ExpiryGate gate = const PassingExpiryGate(),
}) async {
  final container = ProviderContainer(
    overrides: [
      myShopProvider.overrideWith(
        (ref) async =>
            const Shop(id: 's1', ownerId: 'o1', name: 'Shop', currency: 'BDT'),
      ),
      if (repo != null) transactionRepositoryProvider.overrideWithValue(repo),
      // Checkout now runs the expiry gate (and a reconcile after a sale);
      // neither has a backend in tests.
      expiryGateProvider.overrideWithValue(gate),
      expiryReconcilerProvider.overrideWithValue(NoopReconciler()),
    ],
  );
```

In `test/cart_checkout_guard_test.dart`, add the same two imports (with `'support/expiry_fakes.dart'`) and add to `_container`'s overrides:

```dart
      expiryGateProvider.overrideWithValue(const PassingExpiryGate()),
      expiryReconcilerProvider.overrideWithValue(NoopReconciler()),
```

- [ ] **Step 3: Write the failing tests**

`test/cart_checkout_expiry_test.dart`:

```dart
import 'package:ai_shopkeeper/core/error/failure.dart';
import 'package:ai_shopkeeper/features/cart/presentation/cart_checkout_controller.dart';
import 'package:ai_shopkeeper/features/cart/presentation/cart_controller.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/expiry_gate.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/cart_harness.dart';
import 'support/expiry_fakes.dart';

void main() {
  test('a cart that would sell expired units is refused before the sale', () async {
    final repo = CapturingTransactionRepository();
    final c = await cartContainer(repo: repo, gate: const FixedGate(GateBlocked(['p2'])));
    c.read(cartControllerProvider.notifier).addOrIncrement(kOil, 1);

    final ok = await c.read(cartCheckoutControllerProvider.notifier).checkout();

    expect(ok, isFalse);
    expect(repo.calls, 0);
    final error = c.read(cartCheckoutControllerProvider).error;
    expect(error, isA<Failure>());
    expect((error as Failure).code, ServerErrorCodes.expiredStockInCart);
    // The cart is kept so the shopkeeper can fix it.
    expect(c.read(cartControllerProvider), isNotEmpty);
  });

  test('a failed expiry check stops checkout with that failure', () async {
    final repo = CapturingTransactionRepository();
    final c = await cartContainer(
      repo: repo,
      gate: const FixedGate(GateFailed(NetworkFailure('offline'))),
    );
    c.read(cartControllerProvider.notifier).addOrIncrement(kOil, 1);

    final ok = await c.read(cartCheckoutControllerProvider.notifier).checkout();

    expect(ok, isFalse);
    expect(repo.calls, 0);
    expect(c.read(cartCheckoutControllerProvider).error, isA<NetworkFailure>());
  });

  test('a passing check records the sale as before', () async {
    final repo = CapturingTransactionRepository();
    final c = await cartContainer(repo: repo);
    c.read(cartControllerProvider.notifier).addOrIncrement(kOil, 1);

    expect(await c.read(cartCheckoutControllerProvider.notifier).checkout(), isTrue);
    expect(repo.calls, 1);
  });
}
```

`test/cart_math_good_stock_test.dart`:

```dart
import 'package:ai_shopkeeper/features/cart/domain/cart_line.dart';
import 'package:ai_shopkeeper/features/cart/domain/cart_math.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const pepsi = Product(id: 'p1', shopId: 's1', name: 'Pepsi', quantity: 15);

  test('remaining stock can be measured against good stock', () {
    final lines = [CartLine(product: pepsi, quantity: 4)];
    expect(remainingStockForLines(lines, pepsi), 11);
    expect(remainingStockForLines(lines, pepsi, stock: 10), 6);
    expect(remainingStockForLines(lines, pepsi, stock: 3), 0);
  });
}
```

- [ ] **Step 4: Run them to verify they fail**

Run: `flutter test test/cart_checkout_expiry_test.dart test/cart_math_good_stock_test.dart`
Expected: compile errors — `expiredStockInCart` and the `stock:` parameter do not exist; the blocked test would otherwise record a sale.

- [ ] **Step 5: Add the failure code and its text**

In `lib/core/error/failure.dart`, inside `ServerErrorCodes`:

```dart
  /// Set by the app, not the server: checkout's expiry gate refused a cart
  /// that would sell expired units (expiry spec §5 Cart).
  static const expiredStockInCart = 'expiredStockInCart';
```

In `lib/core/l10n/failure_text.dart`, add to the `switch`:

```dart
      ServerErrorCodes.expiredStockInCart => l10n.error_expiredStockInCart,
```

- [ ] **Step 6: Gate checkout**

In `cart_checkout_controller.dart`, import:

```dart
import '../../expiry/presentation/expiry_gate.dart';
import '../../expiry/presentation/expiry_reconciler.dart';
```

Replace the `try { result = await ...recordSaleCart(...) } finally {...}` block with:

```dart
    try {
      // Expiry gate BEFORE the sale (expiry spec §4.2, §5 Cart): it first
      // stores any pending expired-count locks -- otherwise this sale would
      // shrink the expired count -- then refuses a cart that would sell
      // expired units. With no signal the gate fails, and the sale could not
      // have reached the server either.
      switch (await ref.read(expiryGateProvider).check(lines)) {
        case GateFailed(:final failure):
          state = AsyncError(failure, StackTrace.current);
          return false;
        case GateBlocked():
          state = AsyncError(
            const DatabaseFailure(
              'Expired stock in the cart.',
              code: ServerErrorCodes.expiredStockInCart,
            ),
            StackTrace.current,
          );
          return false;
        case GatePass():
          break;
      }
      result = await ref
          .read(transactionRepositoryProvider)
          .recordSaleCart(
            shopId: shopId,
            items: items,
            saleGroupId: _pendingSaleId!,
            source: source,
            customerId: customerId,
            discount: discount,
          );
    } finally {
      // Released in a finally so a throw from the repository cannot wedge
      // checkout shut for the rest of the session.
      _inFlight = false;
    }
```

In the `success:` branch, after `ref.read(dataRefreshProvider.notifier).bump();`:

```dart
        // Stock went down: a delivery may now be sold out (spec §4.2).
        unawaited(ref.read(expiryReconcilerProvider).run());
```

- [ ] **Step 7: Measure remaining stock against good stock**

In `cart_math.dart`, replace `remainingStockForLines`:

```dart
/// How much more of [product] can be added right now: [stock] (default: the
/// product's current stock) minus whatever of it is already staged in
/// [lines]. Never negative. Callers pass the GOOD stock so expired units are
/// never offered (expiry spec §5 Cart).
double remainingStockForLines(
  List<CartLine> lines,
  Product product, {
  double? stock,
}) {
  final staged = lines
      .where((l) => l.product.id == product.id)
      .fold<double>(0, (sum, l) => sum + l.quantity);
  final remaining = (stock ?? product.quantity) - staged;
  return remaining < 0 ? 0 : remaining;
}
```

In `cart_controller.dart`:

```dart
  /// How much more of [product] can still be added right now: [stock] (the
  /// good stock, by default the whole stock) minus what is already staged.
  double remainingStockFor(Product product, {double? stock}) =>
      remainingStockForLines(state, product, stock: stock);
```

- [ ] **Step 8: Use good stock in the add-to-cart sheet**

In `add_to_cart_sheet.dart`, import `'../../expiry/presentation/expiry_providers.dart'`. In `initState`:

```dart
    final remaining = ref
        .read(cartControllerProvider.notifier)
        .remainingStockFor(
          widget.product,
          stock: ref.read(goodStockProvider(widget.product)),
        );
```

In `build`, replace the `maxQty` lines with:

```dart
    final goodStock = ref.watch(goodStockProvider(product));
    final expired = ref.watch(productExpiryProvider)[product.id]?.expired ?? 0;
    final maxQty = ref
        .read(cartControllerProvider.notifier)
        .remainingStockFor(product, stock: goodStock);
```

and after the "available" `Text`, add:

```dart
          if (expired > 0)
            Text(
              l10n.expiry_addSheetExpiredNote(Qty.format(expired), product.unitLabel),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
```

- [ ] **Step 9: Show the notice on cart lines and block the checkout button**

In `cart_screen.dart`, import:

```dart
import '../../expiry/domain/cart_expiry.dart';
import '../../expiry/presentation/batch_actions_controller.dart';
import '../../expiry/presentation/expiry_providers.dart';
```

In `CartScreen.build`, after `final checkoutState = ...`:

```dart
    // A line that would sell expired units, or more than is left, blocks
    // checkout until it is fixed (expiry spec §5 Cart).
    final blocked = ref.watch(cartLineNoticesProvider).isNotEmpty;
```

and pass it: `_CheckoutBar(..., isLoading: checkoutState.isLoading, blocked: blocked, onCheckout: ...)`.

In `_CheckoutBar`, add the field `required this.blocked,` / `final bool blocked;` and change the button:

```dart
                  onPressed: (isLoading || blocked || !selection.isReady)
                      ? null
                      : onCheckout,
```

In `_CartLineCard.build`, replace `final maxQty = product.quantity;` (and its comment) with:

```dart
    // Exactly one line per product (see cart_math.dart), so the ceiling is
    // the product's own GOOD stock -- expired units are never offered.
    final maxQty = ref.watch(goodStockProvider(product));
    final notice = ref.watch(cartLineNoticesProvider)[product.id];
```

and add as the last child of the card's `Column` (after the stepper `Row`):

```dart
            if (notice != null) ...[
              const SizedBox(height: 10),
              _LineNotice(
                notice: notice,
                product: product,
                isCheckingOut: isCheckingOut,
              ),
            ],
```

Add this widget below `_CartLineCard`:

```dart
/// Why this line cannot be checked out, with the way out (expiry spec §5).
class _LineNotice extends ConsumerWidget {
  const _LineNotice({
    required this.notice,
    required this.product,
    required this.isCheckingOut,
  });

  final CartLineNotice notice;
  final Product product;
  final bool isCheckingOut;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.error,
      fontWeight: FontWeight.w600,
    );
    switch (notice) {
      case OverStockNotice(:final stock):
        return Text(
          l10n.expiry_cartOnlyLeft(Qty.format(stock), product.unitLabel),
          style: style,
        );
      case ExpiredStockNotice(:final good, :final expired, :final expiredBatchIds):
        final busy =
            isCheckingOut || ref.watch(batchActionsControllerProvider).isLoading;
        final actions = ref.read(batchActionsControllerProvider.notifier);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              good > 0
                  ? l10n.expiry_cartOnlyGood(
                      Qty.format(good),
                      product.name,
                      Qty.format(expired),
                    )
                  : l10n.expiry_cartOnlyExpired(product.name, Qty.format(expired)),
              style: style,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36)),
                  onPressed: busy ? null : () => actions.removeExpired(expiredBatchIds),
                  child: Text(l10n.expiry_cartRemoveExpired),
                ),
                TextButton(
                  onPressed: busy ? null : () => actions.markNotExpired(expiredBatchIds),
                  child: Text(l10n.expiry_cartNotExpired),
                ),
              ],
            ),
          ],
        );
    }
  }
}
```

Add `import '../../inventory/domain/product.dart';` to `cart_screen.dart` if it is not already imported.

- [ ] **Step 10: Use good stock in the voice review hint**

In `voice_review_sheet.dart`, import `'../../expiry/presentation/expiry_providers.dart'` and replace `_LowStockCaption` with:

```dart
/// A caption warning that the chosen product's GOOD stock can't cover the
/// line's quantity -- expired units cannot be sold (expiry spec §5). Advisory
/// only -- the cart and `record_sale_cart` remain the real authority, so this
/// never disables anything.
class _LowStockCaption extends ConsumerWidget {
  const _LowStockCaption({required this.product, required this.quantity});

  final Product? product;
  final double quantity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final product = this.product;
    if (product == null) return const SizedBox.shrink();
    final available = ref.watch(goodStockProvider(product));
    if (available >= quantity) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        context.l10n.voice_lowStock(available.round()),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
        ),
      ),
    );
  }
}
```

- [ ] **Step 11: Run the tests**

Run: `flutter test test/cart_checkout_expiry_test.dart test/cart_math_good_stock_test.dart`
Expected: pass.
Run: `flutter analyze` — Expected: `No issues found!`
Run: `flutter test` — Expected: all pass. The cart, add-to-cart and voice widget tests have no expiry backend: `batchesStreamProvider` errors, `productExpiryProvider` is empty, and every screen behaves exactly as before. If any of them fails, override `batchesStreamProvider` with `(ref) => Stream.value(const [])` in that test's harness rather than changing the providers.

- [ ] **Step 12: Commit**

```bash
git add lib/features/cart/ lib/features/voice/presentation/voice_review_sheet.dart lib/core/ lib/l10n/ test/support/cart_harness.dart test/cart_checkout_guard_test.dart test/cart_checkout_expiry_test.dart test/cart_math_good_stock_test.dart
git commit -m "feat(expiry): never sell expired stock by default in the cart

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 10: Home card, the alerts screen, the bell, the Items filter, low stock from good stock

**Files:**
- Create: `lib/features/expiry/presentation/expiry_text.dart`, `expiry_alerts_card.dart`, `expiry_alerts_screen.dart`
- Modify: `lib/core/router/app_router.dart`, `lib/features/dashboard/presentation/dashboard_screen.dart`, `lib/features/inventory/presentation/inventory_list_screen.dart`, `lib/features/inventory/domain/inventory_totals.dart`, `lib/l10n/app_en.arb`, `lib/l10n/app_bn.arb`
- Test: `test/expiry_text_test.dart`, `test/inventory_totals_expiry_test.dart`

**Interfaces:**
- Consumes: `ExpiryAlert`, `ExpiryAlertKind`, `goodStockOf`, `ProductExpiry` (Task 3); `expiryAlertsProvider`, `productExpiryProvider`, `goodStockProvider` (Task 5); `formatExpiryDate` (Task 6).
- Produces: `String expiryAlertText(AppLocalizations l10n, ExpiryAlert a)`, `String alertQtyText(ExpiryAlert a)`; `ExpiryAlertsCard`, `ExpiryAlertsScreen`; `AppRoutes.alerts = '/alerts'`; `InventoryTotals.of(List<Product>, {Map<String, ProductExpiry> expiry = const {}})`.

- [ ] **Step 1: Add the strings and update one**

`app_en.arb`:

```json
  "expiry_alertExpired": "Expired: {qty} {name}",
  "@expiry_alertExpired": { "placeholders": { "qty": { "type": "String" }, "name": { "type": "String" } } },
  "expiry_alertSoonToday": "{name}: {qty} expire today",
  "@expiry_alertSoonToday": { "placeholders": { "name": { "type": "String" }, "qty": { "type": "String" } } },
  "expiry_alertSoonTomorrow": "{name}: {qty} expire tomorrow",
  "@expiry_alertSoonTomorrow": { "placeholders": { "name": { "type": "String" }, "qty": { "type": "String" } } },
  "expiry_alertSoonDays": "{name}: {qty} expire in {days} days",
  "@expiry_alertSoonDays": { "placeholders": { "name": { "type": "String" }, "qty": { "type": "String" }, "days": { "type": "String" } } },
  "expiry_cardTitle": "Expiring & expired",
  "expiry_alertsTitle": "Expiry alerts",
  "expiry_filter": "Expiring"
```

`app_bn.arb`:

```json
  "expiry_alertExpired": "মেয়াদোত্তীর্ণ: {qty} {name}",
  "@expiry_alertExpired": { "placeholders": { "qty": { "type": "String" }, "name": { "type": "String" } } },
  "expiry_alertSoonToday": "{name}: {qty} আজ মেয়াদ শেষ",
  "@expiry_alertSoonToday": { "placeholders": { "name": { "type": "String" }, "qty": { "type": "String" } } },
  "expiry_alertSoonTomorrow": "{name}: {qty} আগামীকাল মেয়াদ শেষ",
  "@expiry_alertSoonTomorrow": { "placeholders": { "name": { "type": "String" }, "qty": { "type": "String" } } },
  "expiry_alertSoonDays": "{name}: {qty} {days} দিনে মেয়াদ শেষ",
  "@expiry_alertSoonDays": { "placeholders": { "name": { "type": "String" }, "qty": { "type": "String" }, "days": { "type": "String" } } },
  "expiry_cardTitle": "মেয়াদ শেষ ও শেষ হচ্ছে",
  "expiry_alertsTitle": "মেয়াদের সতর্কতা",
  "expiry_filter": "মেয়াদ শেষ হচ্ছে"
```

Change the existing `dashboard_notificationsHint` values (it becomes the alerts screen's empty-state hint):
- en: `"We'll show stock that is about to expire, or has expired, here."`
- bn: `"যে স্টকের মেয়াদ শেষ হচ্ছে বা শেষ হয়েছে, তা এখানে দেখাব।"`

Run: `flutter gen-l10n`

- [ ] **Step 2: Write the failing tests**

`test/expiry_text_test.dart`:

```dart
import 'package:ai_shopkeeper/features/expiry/domain/expiry_alerts.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/expiry_text.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

ExpiryAlert _a(Product p, ExpiryAlertKind kind, double qty, int daysLeft) => ExpiryAlert(
  product: p,
  kind: kind,
  quantity: qty,
  expiryDate: DateTime(2026, 10, 20),
  daysLeft: daysLeft,
);

void main() {
  const pepsi = Product(id: 'p', shopId: 's', name: 'Pepsi');
  const rice = Product(id: 'r', shopId: 's', name: 'Rice', unitType: UnitType.weight, unit: ProductUnit.kg);
  final en = lookupAppLocalizations(const Locale('en'));

  test('expired, with the unit only for weight and volume', () {
    expect(expiryAlertText(en, _a(pepsi, ExpiryAlertKind.expired, 5, -1)), 'Expired: 5 Pepsi');
    expect(expiryAlertText(en, _a(rice, ExpiryAlertKind.expired, 2.5, -1)), 'Expired: 2.5 kg Rice');
  });

  test('expiring today, tomorrow and in N days', () {
    expect(expiryAlertText(en, _a(pepsi, ExpiryAlertKind.expiringSoon, 3, 0)), 'Pepsi: 3 expire today');
    expect(expiryAlertText(en, _a(pepsi, ExpiryAlertKind.expiringSoon, 3, 1)), 'Pepsi: 3 expire tomorrow');
    expect(expiryAlertText(en, _a(pepsi, ExpiryAlertKind.expiringSoon, 2, 4)), 'Pepsi: 2 expire in 4 days');
  });

  test('alert text is Bengali in bn', () {
    final previous = Intl.defaultLocale;
    Intl.defaultLocale = 'bn';
    addTearDown(() => Intl.defaultLocale = previous);
    final bn = lookupAppLocalizations(const Locale('bn'));
    expect(expiryAlertText(bn, _a(pepsi, ExpiryAlertKind.expired, 5, -1)), 'মেয়াদোত্তীর্ণ: ৫ Pepsi');
  });
}
```

`test/inventory_totals_expiry_test.dart`:

```dart
import 'package:ai_shopkeeper/features/expiry/domain/expiry_estimate.dart';
import 'package:ai_shopkeeper/features/expiry/domain/product_batch.dart';
import 'package:ai_shopkeeper/features/inventory/domain/inventory_totals.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('5 expired + 1 good with a threshold of 3 counts as low stock', () {
    const pepsi = Product(id: 'pepsi', shopId: 's1', name: 'Pepsi', quantity: 6, reorderThreshold: 3);
    final expiry = estimateAll(
      products: [pepsi],
      openBatches: [
        ProductBatch(
          id: 'old',
          shopId: 's1',
          productId: 'pepsi',
          quantity: 5,
          receivedOn: DateTime(2026, 9, 1),
          expiryDate: DateTime(2026, 10, 20),
          expiredQty: 5,
        ),
      ],
      today: DateTime(2026, 10, 21),
      shopWarnDays: 7,
    );
    expect(InventoryTotals.of([pepsi]).lowStockCount, 0);
    expect(InventoryTotals.of([pepsi], expiry: expiry).lowStockCount, 1);
  });
}
```

- [ ] **Step 3: Run them to verify they fail**

Run: `flutter test test/expiry_text_test.dart test/inventory_totals_expiry_test.dart`
Expected: compile errors — `expiry_text.dart` missing, `expiry:` parameter missing.

- [ ] **Step 4: Write `expiry_text.dart`**

```dart
import '../../../l10n/app_localizations.dart';
import '../../../shared/extensions/format.dart';
import '../../inventory/domain/product.dart';
import '../domain/expiry_alerts.dart';

/// "5" for pieces, "2.5 kg" for weight/volume -- "5 pcs Pepsi" reads badly.
/// Digits follow `Intl.defaultLocale`, which the locale provider keeps in sync
/// with the app language, so Bengali shows ৫.
String alertQtyText(ExpiryAlert a) => a.product.unitType == UnitType.piece
    ? Qty.format(a.quantity)
    : '${Qty.format(a.quantity)} ${a.product.unitLabel}';

/// One alert as a sentence. Shared by the Home card, the alerts screen and
/// the daily reminder (which builds it with no BuildContext).
String expiryAlertText(AppLocalizations l10n, ExpiryAlert a) {
  final qty = alertQtyText(a);
  final name = a.product.name;
  if (a.kind == ExpiryAlertKind.expired) return l10n.expiry_alertExpired(qty, name);
  return switch (a.daysLeft) {
    <= 0 => l10n.expiry_alertSoonToday(name, qty),
    1 => l10n.expiry_alertSoonTomorrow(name, qty),
    final days => l10n.expiry_alertSoonDays(name, qty, Qty.format(days)),
  };
}
```

- [ ] **Step 5: Count low stock from good stock in `InventoryTotals`**

In `inventory_totals.dart`, import `'../../expiry/domain/expiry_estimate.dart'` and change `of`:

```dart
  /// [expiry] (the estimate map) makes low stock judge GOOD stock, so 5
  /// expired + 1 good counts as low (expiry spec §5).
  static InventoryTotals of(
    List<Product> products, {
    Map<String, ProductExpiry> expiry = const {},
  }) {
```

and inside the loop replace `if (p.isLowStock) low++;` with:

```dart
      if (p.isLowStockAt(goodStockOf(p, expiry))) low++;
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/expiry_text_test.dart test/inventory_totals_expiry_test.dart`
Expected: pass.

- [ ] **Step 7: Write the card and the screen**

`lib/features/expiry/presentation/expiry_alerts_card.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/theme.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../core/router/app_router.dart';
import '../domain/expiry_alerts.dart';
import 'expiry_providers.dart';
import 'expiry_text.dart';

/// Home's "Expiring & expired" card (spec §5). Hidden when there is nothing
/// to say, so shops that never record dates see no change.
class ExpiryAlertsCard extends ConsumerWidget {
  const ExpiryAlertsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(expiryAlertsProvider);
    if (alerts.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.event_busy_outlined, size: 18, color: colors.negative),
                  const SizedBox(width: 6),
                  Text(
                    l10n.expiry_cardTitle,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => context.push(AppRoutes.alerts),
                    child: Text(l10n.dashboard_viewAll),
                  ),
                ],
              ),
              for (final a in alerts.take(4))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    a.kind == ExpiryAlertKind.expired ? Icons.error_outline : Icons.schedule,
                    color: a.kind == ExpiryAlertKind.expired ? colors.negative : colors.warning,
                  ),
                  title: Text(expiryAlertText(l10n, a)),
                  onTap: () => context.push('/inventory/${a.product.id}'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
```

`lib/features/expiry/presentation/expiry_alerts_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/theme.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../domain/expiry_alerts.dart';
import 'expiry_date_field.dart';
import 'expiry_providers.dart';
import 'expiry_text.dart';

/// Every expiry alert -- opened from the bell and from a reminder tap.
class ExpiryAlertsScreen extends ConsumerWidget {
  const ExpiryAlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final alerts = ref.watch(expiryAlertsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.expiry_alertsTitle)),
      body: alerts.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.notifications_none_rounded, size: 48, color: theme.colorScheme.outline),
                    const SizedBox(height: 12),
                    Text(l10n.dashboard_notificationsCaughtUp, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      l10n.dashboard_notificationsHint,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: alerts.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final a = alerts[i];
                final expired = a.kind == ExpiryAlertKind.expired;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    expired ? Icons.error_outline : Icons.schedule,
                    color: expired ? colors.negative : colors.warning,
                  ),
                  title: Text(expiryAlertText(l10n, a)),
                  subtitle: Text(formatExpiryDate(context, a.expiryDate)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/inventory/${a.product.id}'),
                );
              },
            ),
    );
  }
}
```

- [ ] **Step 8: Add the route**

In `app_router.dart`: add `static const String alerts = '/alerts';` to `AppRoutes`, import `'../../features/expiry/presentation/expiry_alerts_screen.dart'`, and add next to the `AppRoutes.settings` route:

```dart
      GoRoute(
        path: AppRoutes.alerts,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (_, _) => _transitionPage(const ExpiryAlertsScreen()),
      ),
```

- [ ] **Step 9: Wire the Home screen**

In `dashboard_screen.dart`, import:

```dart
import '../../../core/router/app_router.dart';
import '../../expiry/domain/expiry_estimate.dart';
import '../../expiry/presentation/expiry_alerts_card.dart';
import '../../expiry/presentation/expiry_providers.dart';
```

Delete the whole `_showNotificationsSheet` method (the bell now opens the alerts screen).

Replace the `lowStock` computation with:

```dart
    // Low stock judges GOOD stock: 5 expired + 1 good is low (expiry spec §5).
    final expiry = ref.watch(productExpiryProvider);
    final lowStock =
        (ref.watch(productsStreamProvider).value ?? const <Product>[])
            .where((p) => p.isLowStockAt(goodStockOf(p, expiry)))
            .toList();
    final alertCount = ref.watch(expiryAlertsProvider).length;
```

Replace the bell `_HeaderIcon` (and its `// MEMBER C` comment) with:

```dart
                    // Expiry alerts (expiry spec §5). // MEMBER C: other
                    // notification kinds (sales, low stock) can join this
                    // screen later.
                    Badge.count(
                      count: alertCount,
                      isLabelVisible: alertCount > 0,
                      child: _HeaderIcon(
                        icon: Icons.notifications_none_rounded,
                        onTap: () {
                          AppHaptics.tap();
                          context.push(AppRoutes.alerts);
                        },
                      ),
                    ),
```

Replace the low-stock `Entrance` at the end of the list with:

```dart
              const Entrance(index: 6, child: ExpiryAlertsCard()),
              Entrance(
                index: 7,
                child: _LowStockCard(products: lowStock, currency: currency),
              ),
```

- [ ] **Step 10: Wire the Items tab**

In `inventory_list_screen.dart`, import:

```dart
import '../../expiry/domain/expiry_estimate.dart';
import '../../expiry/presentation/expiry_providers.dart';
```

Extend `_InvFilter`:

```dart
@immutable
class _InvFilter {
  const _InvFilter.all()
    : label = 'All',
      categoryId = null,
      lowOnly = false,
      expiringOnly = false;
  const _InvFilter.low()
    : label = 'Low stock',
      categoryId = null,
      lowOnly = true,
      expiringOnly = false;
  const _InvFilter.expiring()
    : label = 'Expiring',
      categoryId = null,
      lowOnly = false,
      expiringOnly = true;
  const _InvFilter.category(this.categoryId, this.label)
    : lowOnly = false,
      expiringOnly = false;

  final String label;
  final String? categoryId; // non-null only for a category filter
  final bool lowOnly;
  final bool expiringOnly;

  // Stable identity for selection matching.
  String get _key =>
      lowOnly ? 'low' : (expiringOnly ? 'expiring' : (categoryId ?? 'all'));

  @override
  bool operator ==(Object other) => other is _InvFilter && other._key == _key;

  @override
  int get hashCode => _key.hashCode;
}
```

Change `_filter`:

```dart
  List<Product> _filter(
    List<Product> products,
    _InvFilter active,
    Map<String, ProductExpiry> expiry,
    Set<String> alertIds,
  ) {
```

```dart
      final matchesFilter = switch (active) {
        _InvFilter(lowOnly: true) => p.isLowStockAt(goodStockOf(p, expiry)),
        _InvFilter(expiringOnly: true) => alertIds.contains(p.id),
        _InvFilter(categoryId: final id?) => p.categoryId == id,
        _ => true, // All
      };
```

In `build`, after `final currency = ...`:

```dart
    final expiry = ref.watch(productExpiryProvider);
    final alertIds = {for (final a in ref.watch(expiryAlertsProvider)) a.product.id};
```

Add `const _InvFilter.expiring(),` after `const _InvFilter.low(),` in the `filters` list; change `labelOf` to:

```dart
                labelOf: (f) => f.lowOnly
                    ? l10n.inventory_filterLowStock
                    : f.expiringOnly
                    ? l10n.expiry_filter
                    : (f.categoryId == null ? l10n.inventory_filterAll : f.label),
```

Change `InventoryTotals.of(products)` to `InventoryTotals.of(products, expiry: expiry)` and `_filter(products, activeFilter)` to `_filter(products, activeFilter, expiry, alertIds)`.

Make `_StockText` judge good stock — change it to a `ConsumerWidget`:

```dart
class _StockText extends ConsumerWidget {
  const _StockText({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final isLow = product.isLowStockAt(ref.watch(goodStockProvider(product)));
    final color = isLow ? colors.warning : colors.positive;
```

(the rest of its `build` is unchanged).

- [ ] **Step 11: Analyze and run the suite**

Run: `flutter analyze` — Expected: `No issues found!`
Run: `flutter test` — Expected: all pass.

- [ ] **Step 12: Commit**

```bash
git add lib/features/expiry/presentation/ lib/core/router/app_router.dart lib/features/dashboard/presentation/dashboard_screen.dart lib/features/inventory/ lib/l10n/ test/expiry_text_test.dart test/inventory_totals_expiry_test.dart
git commit -m "feat(expiry): Home card, alerts screen behind the bell, Items filter, good-stock low checks

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: The daily phone reminder

**Files:**
- Create: `lib/features/expiry/domain/reminder_plan.dart`, `lib/features/expiry/data/reminder_service.dart`, `lib/features/expiry/presentation/reminder_sync.dart`
- Modify: `pubspec.yaml`, `android/app/build.gradle.kts`, `android/app/src/main/AndroidManifest.xml`, `lib/main.dart`, `lib/app.dart`, `lib/features/expiry/presentation/expiry_prefs.dart`, `lib/features/transactions/presentation/transaction_controller.dart`, `lib/features/inventory/presentation/inventory_controller.dart`, `lib/features/expiry/presentation/batch_actions_controller.dart`, `lib/l10n/app_en.arb`, `lib/l10n/app_bn.arb`
- Test: `test/reminder_plan_test.dart`, `test/reminder_sync_test.dart`

**Interfaces:**
- Consumes: `estimateAll`, `buildExpiryAlerts` (Task 3); providers from Task 5; `expiryAlertText` (Task 10); `goRouterProvider`, `AppRoutes.alerts`; `localeProvider`, `lookupAppLocalizations`.
- Produces: `const reminderBaseId = 4100`, `const reminderSlots = 7`; `class PlannedReminder { int id; DateTime at; List<ExpiryAlert> alerts; }`; `List<PlannedReminder> planReminders({required DateTime now, required List<Product> products, required List<ProductBatch> openBatches, required int shopWarnDays, int days = reminderSlots, int hour = 9})`; `String reminderBody(List<String> lines, String Function(int more) moreText, {int max = 2})`; `class ScheduledReminder`; `abstract class ReminderService` (`replaceAll`, `cancelAll`, `requestPermission`, `notificationsEnabled`, `taps`, `consumeLaunchTap`), `NoopReminderService`, `LocalReminderService` (`init()`); `reminderServiceProvider`; `reminderSyncProvider`, `reminderTapRouterProvider`; `ExpiryPrefsController.askPermissionOnce()`.

- [ ] **Step 1: Add the packages**

Run: `flutter pub add flutter_local_notifications:^19.4.0 timezone:^0.10.0`
Expected: both added to `pubspec.yaml`, `pub get` succeeds.

- [ ] **Step 2: Android setup**

In `android/app/build.gradle.kts`, inside `compileOptions`:

```kotlin
        // flutter_local_notifications needs Java 8+ APIs on older Android.
        isCoreLibraryDesugaringEnabled = true
```

and add at the end of the file:

```kotlin
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

In `AndroidManifest.xml`, after the BLUETOOTH permissions:

```xml
    <!-- Daily expiry reminder (expiry spec §6). POST_NOTIFICATIONS is asked
         at runtime on Android 13+; RECEIVE_BOOT_COMPLETED lets scheduled
         reminders survive a restart. No exact-alarm permission: reminders are
         scheduled inexact on purpose. -->
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
```

and inside `<application>`, after the `</activity>`:

```xml
        <receiver
            android:exported="false"
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <!-- Re-schedules after a restart AND after an app update: both can
             drop scheduled alarms (expiry spec §6). -->
        <receiver
            android:exported="false"
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
```

- [ ] **Step 3: Add the strings**

`app_en.arb`:

```json
  "reminder_title": "Expiry check",
  "reminder_more": "+{count} more",
  "@reminder_more": { "placeholders": { "count": { "type": "String" } } },
  "reminder_channelName": "Expiry reminders"
```

`app_bn.arb`:

```json
  "reminder_title": "মেয়াদ যাচাই",
  "reminder_more": "+আরও {count}টি",
  "@reminder_more": { "placeholders": { "count": { "type": "String" } } },
  "reminder_channelName": "মেয়াদের রিমাইন্ডার"
```

Run: `flutter gen-l10n`

- [ ] **Step 4: Write the failing tests**

`test/reminder_plan_test.dart`:

```dart
import 'package:ai_shopkeeper/features/expiry/domain/product_batch.dart';
import 'package:ai_shopkeeper/features/expiry/domain/reminder_plan.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const bread = Product(id: 'bread', shopId: 's1', name: 'Bread', quantity: 10);
  // Added Mon 13 Oct, expires Sat 18 Oct: warned from Fri 17, expired Sun 19.
  final loaf = ProductBatch(
    id: 'b',
    shopId: 's1',
    productId: 'bread',
    quantity: 10,
    receivedOn: DateTime(2026, 10, 13),
    expiryDate: DateTime(2026, 10, 18),
  );

  List<PlannedReminder> plan(DateTime now) => planReminders(
    now: now,
    products: [bread],
    openBatches: [loaf],
    shopWarnDays: 7,
  );

  test('only days with something to say get a 9 AM reminder', () {
    final p = plan(DateTime(2026, 10, 14, 8));
    expect(p.map((r) => r.at), [
      DateTime(2026, 10, 17, 9),
      DateTime(2026, 10, 18, 9),
      DateTime(2026, 10, 19, 9),
      DateTime(2026, 10, 20, 9),
    ]);
    expect(p.first.id, reminderBaseId + 3);
  });

  test('after 9 AM today is skipped', () {
    final p = plan(DateTime(2026, 10, 17, 10));
    expect(p.first.at, DateTime(2026, 10, 18, 9));
  });

  test('the body lists two items then "+N more"', () {
    String more(int n) => '+$n more';
    expect(reminderBody(['a', 'b'], more), 'a, b');
    expect(reminderBody(['a', 'b', 'c', 'd'], more), 'a, b +2 more');
  });
}
```

`test/reminder_sync_test.dart`:

```dart
import 'package:ai_shopkeeper/features/auth/data/auth_repository.dart';
import 'package:ai_shopkeeper/features/auth/domain/shop.dart';
import 'package:ai_shopkeeper/features/expiry/data/reminder_service.dart';
import 'package:ai_shopkeeper/features/expiry/domain/product_batch.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/expiry_prefs.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/expiry_providers.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/reminder_sync.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/today_provider.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/inventory/presentation/inventory_controller.dart';
import 'package:ai_shopkeeper/shared/providers/locale_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

class _FakeService implements ReminderService {
  final replaced = <List<ScheduledReminder>>[];
  int cancels = 0;

  @override
  Future<void> replaceAll(List<ScheduledReminder> reminders, {required String channelName}) async =>
      replaced.add(reminders);

  @override
  Future<void> cancelAll() async => cancels++;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<bool> notificationsEnabled() async => true;

  @override
  Stream<void> get taps => const Stream.empty();

  @override
  bool consumeLaunchTap() => false;
}

const _pepsi = Product(id: 'pepsi', shopId: 's1', name: 'Pepsi', quantity: 15);
final _batches = [
  ProductBatch(
    id: 'old',
    shopId: 's1',
    productId: 'pepsi',
    quantity: 5,
    receivedOn: DateTime(2026, 10, 1),
    expiryDate: DateTime(2026, 10, 20),
    expiredQty: 5,
  ),
];

Future<_FakeService> _sync({
  Shop? shop = const Shop(id: 's1', ownerId: 'o1', name: 'Shop', currency: 'BDT'),
  ExpiryPrefs prefs = const ExpiryPrefs(),
  Locale locale = const Locale('en'),
}) async {
  final service = _FakeService();
  final c = ProviderContainer(
    overrides: [
      reminderServiceProvider.overrideWithValue(service),
      myShopProvider.overrideWith((ref) async => shop),
      productsStreamProvider.overrideWith((ref) => Stream.value([_pepsi])),
      batchesStreamProvider.overrideWith((ref) => Stream.value(_batches)),
      nowProvider.overrideWithValue(() => DateTime(2026, 10, 21, 8)),
      initialExpiryPrefsProvider.overrideWithValue(prefs),
      initialLocaleProvider.overrideWithValue(locale),
    ],
  );
  addTearDown(c.dispose);
  final sub = c.listen(reminderSyncProvider, (_, _) {});
  addTearDown(sub.close);
  await c.read(myShopProvider.future);
  await c.read(productsStreamProvider.future);
  await c.read(batchesStreamProvider.future);
  await Future<void>.delayed(Duration.zero);
  return service;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String? previousLocale;
  setUp(() => previousLocale = Intl.defaultLocale);
  tearDown(() => Intl.defaultLocale = previousLocale);

  test('schedules the next days with the alert text', () async {
    final service = await _sync();
    final first = service.replaced.last.first;
    expect(first.at, DateTime(2026, 10, 21, 9));
    expect(first.title, 'Expiry check');
    expect(first.body, 'Expired: 5 Pepsi');
  });

  test('reminder text follows the app language', () async {
    final service = await _sync(locale: const Locale('bn'));
    final first = service.replaced.last.first;
    expect(first.title, 'মেয়াদ যাচাই');
    expect(first.body, 'মেয়াদোত্তীর্ণ: ৫ Pepsi');
  });

  test('signed out or switched off cancels everything', () async {
    expect((await _sync(shop: null)).cancels, greaterThan(0));
    expect((await _sync(prefs: const ExpiryPrefs(remindersOn: false))).cancels, greaterThan(0));
  });
}
```

- [ ] **Step 5: Run them to verify they fail**

Run: `flutter test test/reminder_plan_test.dart test/reminder_sync_test.dart`
Expected: compile errors — the three new files do not exist.

- [ ] **Step 6: Write `reminder_plan.dart`**

```dart
import '../../inventory/domain/product.dart';
import 'expiry_alerts.dart';
import 'expiry_dates.dart';
import 'expiry_estimate.dart';
import 'product_batch.dart';

/// Notification ids 4100..4106: one slot per day ahead, so rescheduling
/// cancels exactly our reminders and nothing else the app may show.
const reminderBaseId = 4100;
const reminderSlots = 7;

class PlannedReminder {
  const PlannedReminder({required this.id, required this.at, required this.alerts});

  final int id;
  final DateTime at;
  final List<ExpiryAlert> alerts;
}

/// The next [days] daily reminders at [hour]:00 local (spec §6). Each day's
/// alerts come from the estimate run with that day as "today", assuming no
/// further sales. Days with nothing to say get no reminder; a slot whose time
/// has already passed is skipped.
List<PlannedReminder> planReminders({
  required DateTime now,
  required List<Product> products,
  required List<ProductBatch> openBatches,
  required int shopWarnDays,
  int days = reminderSlots,
  int hour = 9,
}) {
  final today = dateOnly(now);
  final out = <PlannedReminder>[];
  for (var i = 0; i < days; i++) {
    final day = DateTime(today.year, today.month, today.day + i);
    final at = DateTime(day.year, day.month, day.day, hour);
    if (!at.isAfter(now)) continue;
    final alerts = buildExpiryAlerts(
      products: products,
      byProduct: estimateAll(
        products: products,
        openBatches: openBatches,
        today: day,
        shopWarnDays: shopWarnDays,
      ),
      today: day,
    );
    if (alerts.isNotEmpty) {
      out.add(PlannedReminder(id: reminderBaseId + i, at: at, alerts: alerts));
    }
  }
  return out;
}

/// "a, b +2 more" -- a notification shows little, so list [max] then count.
String reminderBody(
  List<String> lines,
  String Function(int more) moreText, {
  int max = 2,
}) {
  if (lines.length <= max) return lines.join(', ');
  return '${lines.take(max).join(', ')} ${moreText(lines.length - max)}';
}
```

- [ ] **Step 7: Write `reminder_service.dart`**

```dart
import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../domain/reminder_plan.dart';

class ScheduledReminder {
  const ScheduledReminder({
    required this.id,
    required this.at,
    required this.title,
    required this.body,
  });

  final int id;

  /// Local wall-clock time.
  final DateTime at;
  final String title;
  final String body;
}

/// The phone-side reminder seam (spec §6). // MEMBER C: phone notifications
/// are Member C's area (CLAUDE.md §1/§7); the user chose to build this one
/// here (2026-10-14). Their wider notification work can replace
/// [LocalReminderService] behind this interface.
abstract class ReminderService {
  /// Cancels our reminder slots, then schedules [reminders].
  Future<void> replaceAll(List<ScheduledReminder> reminders, {required String channelName});
  Future<void> cancelAll();
  Future<bool> requestPermission();
  Future<bool> notificationsEnabled();

  /// Fires when the shopkeeper taps a reminder while the app is running.
  Stream<void> get taps;

  /// True once if the app was launched by tapping a reminder.
  bool consumeLaunchTap();
}

/// Used when the plugin is unavailable (tests, or a failed init).
class NoopReminderService implements ReminderService {
  const NoopReminderService();

  @override
  Future<void> replaceAll(List<ScheduledReminder> reminders, {required String channelName}) async {}

  @override
  Future<void> cancelAll() async {}

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<bool> notificationsEnabled() async => true;

  @override
  Stream<void> get taps => const Stream.empty();

  @override
  bool consumeLaunchTap() => false;
}

class LocalReminderService implements ReminderService {
  final _plugin = FlutterLocalNotificationsPlugin();
  final _taps = StreamController<void>.broadcast();
  bool _launchedFromTap = false;

  Future<void> init() async {
    tz_data.initializeTimeZones();
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (_) => _taps.add(null),
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    _launchedFromTap = launch?.didNotificationLaunchApp ?? false;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<void> replaceAll(List<ScheduledReminder> reminders, {required String channelName}) async {
    await cancelAll();
    for (final r in reminders) {
      await _plugin.zonedSchedule(
        r.id,
        r.title,
        r.body,
        // The alarm fires at an INSTANT, so expressing the local 9 AM as the
        // same instant in UTC is exact and needs no device time-zone lookup.
        // Rescheduling on every app open absorbs any clock-zone change.
        tz.TZDateTime.from(r.at, tz.UTC),
        NotificationDetails(
          android: AndroidNotificationDetails(
            'expiry_reminders',
            channelName,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            styleInformation: BigTextStyleInformation(r.body),
          ),
        ),
        // Inexact: may arrive minutes late, but needs no exact-alarm
        // permission. Android 14 no longer grants SCHEDULE_EXACT_ALARM by
        // default and a missing one can throw from the plugin.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  @override
  Future<void> cancelAll() async {
    for (var i = 0; i < reminderSlots; i++) {
      await _plugin.cancel(reminderBaseId + i);
    }
  }

  @override
  Future<bool> requestPermission() async =>
      await _android?.requestNotificationsPermission() ?? false;

  @override
  Future<bool> notificationsEnabled() async =>
      await _android?.areNotificationsEnabled() ?? true;

  @override
  Stream<void> get taps => _taps.stream;

  @override
  bool consumeLaunchTap() {
    final v = _launchedFromTap;
    _launchedFromTap = false;
    return v;
  }
}

/// Overridden in `main()` with an initialised [LocalReminderService].
final reminderServiceProvider = Provider<ReminderService>(
  (ref) => const NoopReminderService(),
);
```

If `flutter analyze` reports that `zonedSchedule` requires `uiLocalNotificationDateInterpretation` (the resolved 19.x release still has it), add `uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,` after `androidScheduleMode`. Change nothing else.

- [ ] **Step 8: Write `reminder_sync.dart`**

```dart
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router/app_router.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/providers/locale_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../../inventory/presentation/inventory_controller.dart';
import '../data/reminder_service.dart';
import '../domain/reminder_plan.dart';
import 'expiry_prefs.dart';
import 'expiry_providers.dart';
import 'expiry_text.dart';
import 'today_provider.dart';

/// Keeps the next 7 days of reminders in step with the data (spec §6).
/// Rebuilds -- and so reschedules -- on any stock or delivery change, a
/// settings change, a LANGUAGE change (the text is baked in when scheduled)
/// and a new day. Signed out or switched off: every reminder is cancelled, so
/// a shared phone never shows the previous account's stock.
final reminderSyncProvider = Provider<void>((ref) {
  final service = ref.watch(reminderServiceProvider);
  final shop = ref.watch(myShopProvider).value;
  final prefs = ref.watch(expiryPrefsProvider);
  final locale = ref.watch(localeProvider);
  ref.watch(todayProvider);

  if (shop == null || !prefs.remindersOn) {
    unawaited(service.cancelAll());
    return;
  }

  final products = ref.watch(productsStreamProvider).value;
  final batches = ref.watch(batchesStreamProvider).value;
  // Still loading: keep whatever is already scheduled.
  if (products == null || batches == null) return;

  final l10n = lookupAppLocalizations(locale);
  final plan = planReminders(
    now: ref.read(nowProvider)(),
    products: products,
    openBatches: batches,
    shopWarnDays: prefs.warnDays,
  );
  unawaited(
    service.replaceAll([
      for (final p in plan)
        ScheduledReminder(
          id: p.id,
          at: p.at,
          title: l10n.reminder_title,
          body: reminderBody(
            [for (final a in p.alerts) expiryAlertText(l10n, a)],
            (more) => l10n.reminder_more(more.toString()),
          ),
        ),
    ], channelName: l10n.reminder_channelName),
  );
});

/// Opens the alerts screen when a reminder is tapped -- while running, or
/// once after a launch from a tap. Signed out, the router's guard sends the
/// shopkeeper to login first.
final reminderTapRouterProvider = Provider<void>((ref) {
  final service = ref.watch(reminderServiceProvider);
  final router = ref.watch(goRouterProvider);
  void open() => router.push(AppRoutes.alerts);

  final sub = service.taps.listen((_) => open());
  ref.onDispose(sub.cancel);
  if (service.consumeLaunchTap()) {
    WidgetsBinding.instance.addPostFrameCallback((_) => open());
  }
});
```

- [ ] **Step 9: Run the tests to verify they pass**

Run: `flutter test test/reminder_plan_test.dart test/reminder_sync_test.dart`
Expected: all pass.

- [ ] **Step 10: Ask for permission once, the first time a date is saved**

In `expiry_prefs.dart`, import `'../data/reminder_service.dart'` and add to `ExpiryPrefsController`:

```dart
  /// Requests notification permission the first time an expiry date is saved
  /// (spec §6). Marked asked BEFORE requesting so a crash cannot loop it. A
  /// failure here must never break the save that triggered it.
  Future<void> askPermissionOnce() async {
    if (state.permissionAsked) return;
    try {
      await markPermissionAsked();
      await ref.read(reminderServiceProvider).requestPermission();
    } catch (_) {}
  }
```

Call it in three places (each file imports `expiry_prefs.dart` and `dart:async` if not already):

`transaction_controller.dart`, inside `onSuccess`:

```dart
        if (expiryDate != null) {
          ref.invalidate(batchesStreamProvider);
          unawaited(ref.read(expiryPrefsProvider.notifier).askPermissionOnce());
        }
```

(replacing the single-line `if (expiryDate != null) ref.invalidate(batchesStreamProvider);`).

`inventory_controller.dart`, in the `if (batch.isSuccess) {` branch:

```dart
            ref.invalidate(batchesStreamProvider);
            unawaited(ref.read(expiryPrefsProvider.notifier).askPermissionOnce());
```

`batch_actions_controller.dart`, make `addBatch` async and ask after success:

```dart
  Future<bool> addBatch({
    required Product product,
    required double quantity,
    required DateTime expiryDate,
    required DateTime receivedOn,
  }) async {
    final ok = await _run(() async {
      final r = await _repo.addBatch(
        shopId: product.shopId,
        productId: product.id,
        quantity: quantity,
        buyingPrice: product.buyingPrice,
        receivedOn: receivedOn,
        expiryDate: expiryDate,
      );
      return r.when(
        success: (_) => const Result<void>.success(null),
        failure: (f) => Result<void>.failure(f),
      );
    });
    if (ok) unawaited(ref.read(expiryPrefsProvider.notifier).askPermissionOnce());
    return ok;
  }
```

In `test/restock_idempotency_test.dart` and `test/inventory_save_expiry_test.dart`, add at the top of `main()`:

```dart
  setUp(() => SharedPreferences.setMockInitialValues({}));
```

(with `import 'package:shared_preferences/shared_preferences.dart';`).

- [ ] **Step 11: Start the service and keep the sync alive**

In `lib/main.dart`, import `'features/expiry/data/reminder_service.dart'` and, after `final expiryPrefs = await loadExpiryPrefs();`:

```dart
  // The plugin can fail on an odd device or emulator; reminders are a nicety,
  // so fall back to no reminders rather than failing to start.
  ReminderService reminders = const NoopReminderService();
  try {
    final local = LocalReminderService();
    await local.init();
    reminders = local;
  } catch (_) {}
```

and add to the overrides:

```dart
        reminderServiceProvider.overrideWithValue(reminders),
```

In `lib/app.dart`, import `'features/expiry/presentation/reminder_sync.dart'` and below the reconcile `ref.listen`:

```dart
    ref.listen(reminderSyncProvider, (_, _) {});
    ref.listen(reminderTapRouterProvider, (_, _) {});
```

- [ ] **Step 12: Analyze, run the suite, build**

Run: `flutter analyze` — Expected: `No issues found!`
Run: `flutter test` — Expected: all pass.
Run: `flutter build apk --debug --dart-define-from-file=dart_defines.json`
Expected: `Built build/app/outputs/flutter-apk/app-debug.apk` (proves the Gradle/manifest changes compile; see `RUN.md` for the defines file).

- [ ] **Step 13: Commit**

```bash
git add pubspec.yaml pubspec.lock android/app/build.gradle.kts android/app/src/main/AndroidManifest.xml lib/ test/reminder_plan_test.dart test/reminder_sync_test.dart test/restock_idempotency_test.dart test/inventory_save_expiry_test.dart
git commit -m "feat(expiry): daily phone reminder at 9 AM, offline, inexact

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: Settings — warning time and the reminder switch

**Files:**
- Create: `lib/features/expiry/presentation/expiry_settings_tiles.dart`
- Modify: `lib/features/settings/presentation/settings_screen.dart`, `lib/l10n/app_en.arb`, `lib/l10n/app_bn.arb`
- Test: `test/widgets/expiry_settings_tiles_test.dart`

**Interfaces:**
- Consumes: `expiryPrefsProvider`, `ExpiryPrefs.warnDayChoices` (Task 5); `reminderServiceProvider` (Task 11).
- Produces: `ExpiryWarnDaysTile`, `ExpiryReminderTile`, `reminderPermissionProvider` (`FutureProvider.autoDispose<bool>`).

- [ ] **Step 1: Add the strings**

`app_en.arb`:

```json
  "settings_sectionExpiry": "Expiry",
  "settings_expiryWarnDays": "Warn me up to {days} days before",
  "@settings_expiryWarnDays": { "placeholders": { "days": { "type": "String" } } },
  "settings_expiryWarnDaysTitle": "Warning time",
  "settings_expiryDaysOption": "{days} days",
  "@settings_expiryDaysOption": { "placeholders": { "days": { "type": "String" } } },
  "settings_expiryReminder": "Daily expiry reminder",
  "settings_expiryReminderSub": "At 9 AM on days something needs attention",
  "settings_expiryReminderBlocked": "Blocked — turn on notifications in phone settings"
```

`app_bn.arb`:

```json
  "settings_sectionExpiry": "মেয়াদ",
  "settings_expiryWarnDays": "সর্বোচ্চ {days} দিন আগে জানাবে",
  "@settings_expiryWarnDays": { "placeholders": { "days": { "type": "String" } } },
  "settings_expiryWarnDaysTitle": "সতর্কতার সময়",
  "settings_expiryDaysOption": "{days} দিন",
  "@settings_expiryDaysOption": { "placeholders": { "days": { "type": "String" } } },
  "settings_expiryReminder": "প্রতিদিনের মেয়াদ রিমাইন্ডার",
  "settings_expiryReminderSub": "কিছু দেখার থাকলে সকাল ৯টায়",
  "settings_expiryReminderBlocked": "বন্ধ — ফোনের সেটিংসে নোটিফিকেশন চালু করুন"
```

Run: `flutter gen-l10n`

- [ ] **Step 2: Write the failing widget test**

`test/widgets/expiry_settings_tiles_test.dart`:

```dart
import 'package:ai_shopkeeper/features/expiry/data/reminder_service.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/expiry_prefs.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/expiry_settings_tiles.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:ai_shopkeeper/shared/providers/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Blocked extends NoopReminderService {
  const _Blocked();
  @override
  Future<bool> notificationsEnabled() async => false;
}

Widget _app(ProviderContainer c) => UncontrolledProviderScope(
  container: c,
  child: MaterialApp(
    locale: const Locale('en'),
    supportedLocales: supportedAppLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: const Scaffold(
      body: Column(children: [ExpiryWarnDaysTile(), ExpiryReminderTile()]),
    ),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('choosing 14 days stores it', (tester) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await tester.pumpWidget(_app(c));

    expect(find.text('Warn me up to 7 days before'), findsOneWidget);
    await tester.tap(find.text('Warn me up to 7 days before'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('14 days'));
    await tester.pumpAndSettle();

    expect(c.read(expiryPrefsProvider).warnDays, 14);
    expect(find.text('Warn me up to 14 days before'), findsOneWidget);
  });

  testWidgets('blocked notifications say so', (tester) async {
    final c = ProviderContainer(
      overrides: [reminderServiceProvider.overrideWithValue(const _Blocked())],
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(_app(c));
    await tester.pumpAndSettle();
    expect(find.text('Blocked — turn on notifications in phone settings'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `flutter test test/widgets/expiry_settings_tiles_test.dart`
Expected: compile error — `expiry_settings_tiles.dart` does not exist.

- [ ] **Step 4: Write `expiry_settings_tiles.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../shared/extensions/format.dart';
import '../data/reminder_service.dart';
import 'expiry_prefs.dart';

/// Whether the phone lets the app post notifications. Re-read each time the
/// Settings screen opens (autoDispose).
final reminderPermissionProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(reminderServiceProvider).notificationsEnabled(),
);

class ExpiryWarnDaysTile extends ConsumerWidget {
  const ExpiryWarnDaysTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final days = ref.watch(expiryPrefsProvider.select((p) => p.warnDays));
    return ListTile(
      leading: const Icon(Icons.event_note_outlined),
      title: Text(l10n.settings_expiryWarnDays(Qty.format(days))),
      onTap: () async {
        final picked = await showDialog<int>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: Text(l10n.settings_expiryWarnDaysTitle),
            children: [
              for (final d in ExpiryPrefs.warnDayChoices)
                SimpleDialogOption(
                  onPressed: () => Navigator.of(ctx).pop(d),
                  child: Row(
                    children: [
                      Expanded(child: Text(l10n.settings_expiryDaysOption(Qty.format(d)))),
                      if (d == days) const Icon(Icons.check, size: 18),
                    ],
                  ),
                ),
            ],
          ),
        );
        if (picked != null) {
          await ref.read(expiryPrefsProvider.notifier).setWarnDays(picked);
        }
      },
    );
  }
}

class ExpiryReminderTile extends ConsumerWidget {
  const ExpiryReminderTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final on = ref.watch(expiryPrefsProvider.select((p) => p.remindersOn));
    final allowed = ref.watch(reminderPermissionProvider).value ?? true;
    return SwitchListTile(
      secondary: const Icon(Icons.notifications_active_outlined),
      title: Text(l10n.settings_expiryReminder),
      subtitle: Text(
        on && !allowed ? l10n.settings_expiryReminderBlocked : l10n.settings_expiryReminderSub,
      ),
      value: on,
      onChanged: (v) => ref.read(expiryPrefsProvider.notifier).setRemindersOn(v),
    );
  }
}
```

- [ ] **Step 5: Add the section to Settings**

In `settings_screen.dart`, import `'../../expiry/presentation/expiry_settings_tiles.dart'` and add after the Inventory section's last `ListTile` (before the sign-out button):

```dart
          _SectionHeader(l10n.settings_sectionExpiry),
          const ExpiryWarnDaysTile(),
          const ExpiryReminderTile(),
```

- [ ] **Step 6: Run the tests**

Run: `flutter test test/widgets/expiry_settings_tiles_test.dart` — Expected: pass.
Run: `flutter analyze` — Expected: `No issues found!`
Run: `flutter test` — Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add lib/features/expiry/presentation/expiry_settings_tiles.dart lib/features/settings/presentation/settings_screen.dart lib/l10n/ test/widgets/expiry_settings_tiles_test.dart
git commit -m "feat(expiry): warning time and reminder switch in Settings

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 13: Docs, final checks, device verification

**Files:**
- Modify: `docs/superpowers/specs/2026-10-14-product-expiry-design.md` (status line), `docs/00-Map.md` (the Inventory entry only)

- [ ] **Step 1: Format only what this branch touched**

Run:

```bash
git diff --name-only main...HEAD -- '*.dart' | grep -v '\.g\.dart$' | grep -v '\.freezed\.dart$' | grep -v '^lib/l10n/' | xargs dart format
```

Expected: a list of formatted files; never `dart format .`.

- [ ] **Step 2: Full verification**

Run: `flutter analyze` — Expected: `No issues found!`
Run: `flutter test` — Expected: all pass; report the count.

- [ ] **Step 3: Update the docs**

In the spec, replace the status paragraph with:

```markdown
**Status:** built 2026-10-14 on `feat/product-expiry` (plan:
[[2026-10-14-product-expiry]]). Migration `0011` applied and probed before the
app work. Edge-case review in §11.
```

In `docs/00-Map.md`, change the Inventory entry's `(**planned, not built**)` to `(built 2026-10-14; migration 0011)`, and add one sentence at its end: `Reconcile reads deliveries BEFORE stock, because the two streams refresh independently and a restock's delivery arriving first would close the old delivery as sold out.` Stage only that hunk — the user has their own uncommitted lines in this file:

The Inventory section sits above the user's Reliability/Business lines, so its change is the FIRST hunk of the diff. Stage only that hunk:

```bash
git diff docs/00-Map.md | awk '/^@@/{n++} n<2{print}' > .git/map-inventory.patch
cat .git/map-inventory.patch   # must show only the Inventory line change
git apply --cached .git/map-inventory.patch
git add docs/superpowers/specs/2026-10-14-product-expiry-design.md docs/superpowers/plans/2026-10-14-product-expiry.md
git commit -m "docs: mark product expiry built

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 4: Device checklist (the user runs this on the S22)**

Confirm with the user that `0011` is live (Task 1 Step 3), then hand them the release build command from `RUN.md` and this checklist:

1. Add a product "Test Bread", quantity 10, expiry date = 4 days from today → the app asks for notification permission once.
2. Product page shows one delivery, *Good*, "About 10 pcs left".
3. Settings → Expiry → change warning to 3 days and back to 7.
4. Restock Test Bread 5 with expiry = yesterday → the app asks "This date has already passed" → Save anyway. Product page: that delivery shows *Expired*; Home shows "Expired: 5 Test Bread"; the bell has a badge.
5. Add 12 Test Bread to the cart → the line says "Only 10 good Test Bread left (5 expired)" and Checkout is disabled. Tap **They're not expired** → the notice clears. Restock again with yesterday's date and tap **Remove expired** instead → stock drops by 5, History shows no new sale.
6. Turn airplane mode on, try a checkout → "No internet" (not an expiry message), and no sale is recorded.
7. Change the phone language setting in the app to বাংলা → Home card and alerts are Bengali with Bengali digits.
8. Sign out → no reminder arrives the next morning.

Report anything that differs; fix before merging.

- [ ] **Step 5: Finish the branch**

Use superpowers:finishing-a-development-branch to choose merge / PR / keep.

