# Cart Discount Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a shopkeeper take a flat amount off a cart before checkout, with the discount split across the sale's transaction rows so every revenue figure in the app stays correct.

**Architecture:** The discount is entered on the cart screen, held in its own small Riverpod `Notifier<double>`, and passed to `record_sale_cart` as `p_discount`. The **database** splits it across the lines into a new `transactions.discount_amount` column; Dart never allocates. Revenue everywhere becomes `selling_price × quantity − discount_amount`; cost is untouched.

**Tech Stack:** Flutter, Riverpod 3 (`Notifier`), freezed + json_serializable, Supabase Postgres RPC, Flutter l10n (`gen-l10n`).

**Design doc:** [2026-08-06-cart-discount-design.md](../specs/2026-08-06-cart-discount-design.md)

## Global Constraints

- **Never run `dart format .` repo-wide.** Format only the paths you touched, and only if that file was already formatted at HEAD (check by extracting the HEAD copy to a file inside the project and running `dart format --set-exit-if-changed` on it — checking via stdin gives the wrong answer, it misses the package language version).
- **Never hardcode Supabase keys.** Nothing in this plan needs them.
- **The SQL is not yours to run.** Task 1 writes the migration file only. The user applies it via the Supabase Dashboard SQL editor.
- **All sales go through `record_sale_cart`.** Do not add stock maths on the client, and do not touch `record_sale` / `record_restock`.
- **Every user-facing string is localised** in both `lib/l10n/app_en.arb` and `lib/l10n/app_bn.arb`.
- `field_rename: snake` is configured in `build.yaml`, so a Dart field `discountAmount` maps to the column `discount_amount` with no `@JsonKey`.
- After editing any `.arb`, run `flutter gen-l10n`. After editing any `@freezed` model, run `dart run build_runner build --delete-conflicting-outputs`.
- Verification commands: `flutter analyze` (must print "No issues found!") and `flutter test` (all must pass). The suite is at **322 tests** before this plan.

## Shared test harness — build this first

Every test from Task 4 onward uses it. Create `test/support/cart_harness.dart`
**before starting Task 4**; it is not a task of its own because it has no
deliverable a reviewer could accept or reject on its own.

**In two parts, and the order is forced.** Everything down to `cartApp` goes in
before Task 4. `CapturingTransactionRepository` goes in **during Task 5, Step 1
— not before**: it overrides `recordSaleCart` with a `discount` parameter that
does not exist until Task 5 Step 3, so adding it early makes the whole test
tree fail to compile with an override-signature error that looks like a bug in
the harness rather than a sequencing mistake.

```dart
import 'package:ai_shopkeeper/core/config/theme.dart';
import 'package:ai_shopkeeper/core/error/result.dart';
import 'package:ai_shopkeeper/features/auth/data/auth_repository.dart';
import 'package:ai_shopkeeper/features/auth/domain/shop.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/transactions/data/transaction_repository.dart';
import 'package:ai_shopkeeper/features/transactions/domain/transaction.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:ai_shopkeeper/shared/providers/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 850 sell / 700 buy => 150 profit on one unit. Chosen so a 162 discount
/// lands 12 below cost, which is the below-cost warning's test case.
const kOil = Product(
  id: 'p2',
  shopId: 's1',
  name: 'Oil',
  sellingPrice: 850,
  buyingPrice: 700,
  quantity: 100,
);

const kPepsi = Product(
  id: 'p1',
  shopId: 's1',
  name: 'Pepsi',
  sellingPrice: 45,
  buyingPrice: 30,
  quantity: 100,
);

/// A container with a resolved shop.
///
/// AWAITING THE SHOP IS NOT OPTIONAL. `CartController.build` watches
/// `myShopProvider` to key its lifecycle to the signed-in shop, so the cart is
/// reset when that provider resolves. Stage a cart before the shop settles and
/// the lines vanish underneath the test, which reads as a broken feature
/// rather than a broken harness.
Future<ProviderContainer> cartContainer({TransactionRepository? repo}) async {
  final container = ProviderContainer(
    overrides: [
      myShopProvider.overrideWith(
        (ref) async =>
            const Shop(id: 's1', ownerId: 'o1', name: 'Shop', currency: 'BDT'),
      ),
      if (repo != null) transactionRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  await container.read(myShopProvider.future);
  return container;
}

Widget cartApp(ProviderContainer container, Widget home) =>
    UncontrolledProviderScope(
      container: container,
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
        home: home,
      ),
    );

// ---------------------------------------------------------------------------
// ADD THIS DURING TASK 5 STEP 1, NOT EARLIER. See the note above.
// ---------------------------------------------------------------------------

/// Records what checkout sent. `TransactionRepository` is a concrete class, so
/// this implements its five public methods explicitly -- there is no mock
/// framework in this project.
class CapturingTransactionRepository implements TransactionRepository {
  double? sentDiscount;
  String? sentCustomerId;
  int calls = 0;

  @override
  Future<Result<List<Transaction>>> recordSaleCart({
    required String shopId,
    required List<Map<String, dynamic>> items,
    String source = 'manual',
    String? customerId,
    double discount = 0,
  }) async {
    calls++;
    sentDiscount = discount;
    sentCustomerId = customerId;
    return const Result.success(<Transaction>[]);
  }

  @override
  Future<Result<Transaction>> recordRestock({
    required String shopId,
    required String productId,
    required double quantity,
    String source = 'manual',
  }) async => throw UnimplementedError();

  @override
  Future<Result<List<Transaction>>> recentSales({
    required String shopId,
    int limit = 100,
    DateTime? since,
  }) async => const Result.success(<Transaction>[]);

  @override
  Future<Result<List<Transaction>>> salesForDay({
    required String shopId,
    required DateTime day,
  }) async => const Result.success(<Transaction>[]);

  @override
  Future<Result<DateTime?>> earliestSaleDate({required String shopId}) async =>
      const Result.success(null);
}
```

If `salesForDay`'s parameters differ, copy the real signature from
`lib/features/transactions/data/transaction_repository.dart:94` verbatim — the
analyzer will name any mismatch.

---

### Task 1: The migration file

**Files:**
- Create: `supabase/migrations/0009_cart_discount.sql`

**Interfaces:**
- Consumes: nothing.
- Produces: the `record_sale_cart(uuid, jsonb, text, uuid, numeric)` signature that Task 5 calls with `p_discount`, and the `transactions.discount_amount` column that Task 2 reads.

This task ships a file, not a database change. There is no local Postgres, so nothing here is testable by `flutter test` — the verification is the checklist in Step 2, which the user runs.

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/0009_cart_discount.sql`:

```sql
-- =============================================================================
-- 0009_cart_discount.sql — flat-amount discount on a cart checkout.
-- Run AFTER 0008_customer_credit.sql (Dashboard SQL Editor -> paste -> Run).
-- Idempotent (safe to re-run).
--
-- A "receipt" is several transactions rows sharing sale_group_id; there is no
-- header table, so a cart-level discount is SPLIT across the rows into
-- discount_amount. Revenue everywhere becomes
--   selling_price * quantity - discount_amount
-- which keeps every aggregate a flat row-sum (no join, so a multi-line receipt
-- cannot double-subtract its own discount).
--
-- cost is deliberately unchanged: a discount comes out of margin, not out of
-- what was paid to the supplier.
--
-- OVERLOAD WARNING (same trap as 0006): adding p_discount changes the argument
-- list, so `create or replace` would leave the OLD record_sale_cart in place
-- beside the new one and PostgREST could no longer resolve which to call --
-- silently breaking checkout. Every prior signature is dropped first.
-- =============================================================================

alter table transactions
  add column if not exists discount_amount numeric(10,2) not null default 0;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'transactions_discount_non_negative'
  ) then
    alter table transactions
      add constraint transactions_discount_non_negative
      check (discount_amount >= 0);
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'transactions_discount_within_line'
  ) then
    alter table transactions
      add constraint transactions_discount_within_line
      check (discount_amount <= selling_price * quantity);
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- record_sale_cart — gains p_discount. p_discount = 0 => 0008 behaviour.
-- ---------------------------------------------------------------------------
drop function if exists record_sale_cart(uuid, jsonb, text);
drop function if exists record_sale_cart(uuid, jsonb, text, uuid);
drop function if exists record_sale_cart(uuid, jsonb, text, uuid, numeric);

create function record_sale_cart(
  p_shop_id uuid,
  p_items jsonb,              -- [{"product_id": "...", "quantity": 2}, ...]
  p_source text default 'manual',
  p_customer_id uuid default null,
  p_discount numeric default 0
) returns setof transactions
language plpgsql
as $$
declare
  v_group    uuid := gen_random_uuid();
  v_item     record;
  v_product  products;
  v_subtotal numeric(12,2);
  v_share    numeric(12,2);
  v_assigned numeric(12,2) := 0;
  v_left     numeric(12,2);
  v_row      transactions;
begin
  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'Cart is empty';
  end if;

  if p_customer_id is not null then
    perform 1 from customers
      where id = p_customer_id and shop_id = p_shop_id;
    if not found then
      raise exception 'Customer not found';
    end if;
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

  -- -------------------------------------------------------------------------
  -- Allocate the discount across the rows just inserted.
  -- -------------------------------------------------------------------------
  if p_discount is not null and p_discount > 0 then
    select coalesce(sum(selling_price * quantity), 0) into v_subtotal
      from transactions where sale_group_id = v_group;

    if p_discount > v_subtotal then
      raise exception 'Discount exceeds total: bill is %, discount was %',
        v_subtotal, p_discount;
    end if;

    -- FLOOR, never round. quantity is numeric(10,3), so a line subtotal can
    -- carry three decimals (45.00 * 2.501 = 112.545). Rounding a full-discount
    -- share UP to 112.55 would exceed the line's own value and trip
    -- transactions_discount_within_line, failing a perfectly legal sale.
    -- Flooring can never overshoot, so the constraint and the allocation
    -- cannot contradict each other.
    for v_row in
      select * from transactions where sale_group_id = v_group
    loop
      v_share := floor(
        (p_discount * (v_row.selling_price * v_row.quantity) / v_subtotal) * 100
      ) / 100;
      update transactions set discount_amount = v_share where id = v_row.id;
      v_assigned := v_assigned + v_share;
    end loop;

    -- Flooring leaves a positive remainder under one paisa per line. Hand it
    -- out largest-line-first, skipping any line already at its own value (the
    -- only case that can happen is a discount equal to the whole bill).
    v_left := p_discount - v_assigned;
    for v_row in
      select * from transactions
        where sale_group_id = v_group
        order by selling_price * quantity desc, id
    loop
      exit when v_left <= 0;
      v_share := least(v_left,
                       v_row.selling_price * v_row.quantity - v_row.discount_amount);
      if v_share > 0 then
        update transactions
          set discount_amount = discount_amount + v_share
          where id = v_row.id;
        v_left := v_left - v_share;
      end if;
    end loop;
  end if;

  -- On credit: the debt is the DISCOUNTED total, recorded in the same
  -- transaction so stock, sale, and debt can never disagree.
  if p_customer_id is not null then
    select coalesce(sum(selling_price * quantity - discount_amount), 0)
      into v_subtotal
      from transactions where sale_group_id = v_group;

    insert into customer_ledger(shop_id, customer_id, entry_type, amount, sale_group_id)
    values (p_shop_id, p_customer_id, 'credit_sale', v_subtotal, v_group);
  end if;

  return query select * from transactions where sale_group_id = v_group;
end;
$$;

-- ---------------------------------------------------------------------------
-- Analytics: one term each. cost is untouched on purpose.
-- ---------------------------------------------------------------------------
drop function if exists get_dashboard_summary(uuid, text);
drop function if exists get_dashboard_summary(uuid, text, date);

create function get_dashboard_summary(
  p_shop_id uuid,
  p_period text default 'all',
  p_day date default null
) returns table (
  revenue          numeric,
  cost             numeric,
  profit           numeric,
  units_sold       bigint,
  inventory_value  numeric
)
language plpgsql
as $$
declare
  v_start timestamptz;
  v_end   timestamptz;
begin
  if p_day is not null then
    v_start := p_day::timestamptz;
    v_end   := (p_day + 1)::timestamptz;
  else
    v_start := case lower(coalesce(p_period, 'all'))
      when 'today' then date_trunc('day', now())
      when 'week'  then date_trunc('week', now())
      when 'month' then date_trunc('month', now())
      when 'year'  then date_trunc('year', now())
      else '-infinity'::timestamptz
    end;
    v_end := 'infinity'::timestamptz;
  end if;

  return query
  select
    coalesce(sum(t.selling_price * t.quantity - t.discount_amount), 0)::numeric as revenue,
    coalesce(sum(t.buying_price * t.quantity), 0)::numeric as cost,
    coalesce(sum((t.selling_price - t.buying_price) * t.quantity - t.discount_amount), 0)::numeric as profit,
    coalesce(sum(t.quantity), 0)::bigint as units_sold,
    (
      select coalesce(sum(p.buying_price * p.quantity), 0)::numeric
      from products p
      where p.shop_id = p_shop_id
        and not p.is_archived
    ) as inventory_value
  from transactions t
  where t.shop_id = p_shop_id
    and t.type = 'sale'
    and t.created_at >= v_start
    and t.created_at < v_end;
end;
$$;

create or replace function get_sales_series(
  p_shop_id uuid,
  p_bucket text default 'day',
  p_points integer default 7
) returns table (
  bucket   timestamptz,
  revenue  numeric,
  profit   numeric
)
language plpgsql
stable
as $$
declare
  v_trunc text;
  v_interval interval;
  v_start timestamptz;
begin
  v_trunc := case lower(coalesce(p_bucket, 'day'))
    when 'week' then 'week'
    when 'month' then 'month'
    else 'day'
  end;
  v_interval := case v_trunc
    when 'week' then interval '1 week'
    when 'month' then interval '1 month'
    else interval '1 day'
  end;
  v_start := date_trunc(v_trunc, now()) - (v_interval * (greatest(p_points, 1) - 1));

  return query
  with series as (
    select generate_series(v_start, date_trunc(v_trunc, now()), v_interval) as bucket
  ),
  sales as (
    select date_trunc(v_trunc, created_at) as bucket,
           sum(selling_price * quantity - discount_amount) as revenue,
           sum((selling_price - buying_price) * quantity - discount_amount) as profit
    from transactions
    where shop_id = p_shop_id
      and type = 'sale'
      and created_at >= v_start
    group by 1
  )
  select s.bucket,
         coalesce(sa.revenue, 0)::numeric as revenue,
         coalesce(sa.profit, 0)::numeric as profit
  from series s
  left join sales sa on sa.bucket = s.bucket
  order by s.bucket;
end;
$$;
```

- [ ] **Step 2: Write the probe checklist**

Append to `supabase/README.md`, under a new `## 0009 — cart discount` heading:

```markdown
## 0009 — cart discount

Apply `migrations/0009_cart_discount.sql` in the Dashboard SQL editor, then run
these in the same editor. `record_sale_cart` MUST be applied before the app
build that sends `p_discount` — a new build against the old function fails
EVERY sale, not just discounted ones.

1. Exactly one function, five arguments:
   `select pg_get_function_identity_arguments(oid) from pg_proc where proname = 'record_sale_cart';`
   Expect ONE row ending `, p_discount numeric`.

2. Old sales unaffected:
   `select count(*) from transactions where discount_amount <> 0;`
   Expect 0 before any discounted sale is made.

3. **The paisa case.** In the app, cart three items whose line totals do not
   divide evenly (e.g. 100 / 100 / 100) and discount 7. Then:
   `select sum(discount_amount) from transactions where sale_group_id = '<id>';`
   Expect exactly **7.00**, not 6.99.

4. Over-discount is rejected: discount more than the bill in the app.
   Expect the error `Discount exceeds total`, and no stock movement.

5. Credit sale: check out on credit with a discount, then
   `select amount from customer_ledger where sale_group_id = '<id>';`
   Expect the DISCOUNTED total.

6. Dashboard revenue drops by the discount, and `cost` does NOT change.
```

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/0009_cart_discount.sql supabase/README.md
git commit -m "feat(db): add discount_amount and p_discount to record_sale_cart"
```

---

### Task 2: `Transaction.discountAmount`

**Files:**
- Modify: `lib/features/transactions/domain/transaction.dart`
- Test: `test/transaction_discount_test.dart` (create)

**Interfaces:**
- Consumes: the `discount_amount` column from Task 1.
- Produces: `Transaction.discountAmount` (`double`, defaults to 0) and a `revenue` getter net of it. Task 9 and `SaleReceipt.totalRevenue` in `history_screen.dart` both read these.

- [ ] **Step 1: Write the failing test**

Create `test/transaction_discount_test.dart`:

```dart
import 'package:ai_shopkeeper/features/transactions/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

/// A discount comes out of MARGIN, not out of what was paid to the supplier.
/// So `revenue` and `profit` fall by it and `cost` does not move -- the same
/// split the SQL in 0009 makes, restated here so the Dart and the database
/// cannot drift apart.
void main() {
  const line = Transaction(
    id: 't1',
    shopId: 's1',
    productId: 'p1',
    type: 'sale',
    quantity: 2,
    buyingPrice: 30,
    sellingPrice: 45,
    discountAmount: 10,
  );

  test('revenue is net of the discount', () {
    expect(line.revenue, 80); // 45 * 2 - 10
  });

  test('cost ignores the discount', () {
    expect(line.cost, 60); // 30 * 2
  });

  test('profit absorbs the discount', () {
    expect(line.profit, 20); // 80 - 60
  });

  test('an undiscounted line is unchanged', () {
    const plain = Transaction(
      id: 't2',
      shopId: 's1',
      productId: 'p1',
      type: 'sale',
      quantity: 2,
      buyingPrice: 30,
      sellingPrice: 45,
    );
    expect(plain.discountAmount, 0);
    expect(plain.revenue, 90);
  });

  test('discount_amount is read from the row', () {
    final t = Transaction.fromJson(const {
      'id': 't3',
      'shop_id': 's1',
      'product_id': 'p1',
      'type': 'sale',
      'quantity': 2,
      'buying_price': 30,
      'selling_price': 45,
      'discount_amount': 10,
    });
    expect(t.discountAmount, 10);
    expect(t.revenue, 80);
  });
}
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `flutter test test/transaction_discount_test.dart`
Expected: FAIL — `No named parameter with the name 'discountAmount'`.

- [ ] **Step 3: Add the field**

In `lib/features/transactions/domain/transaction.dart`, add after `sellingPrice` (line 20) and change `revenue`:

```dart
    @Default(0) double sellingPrice,
    /// This line's share of a cart-level discount, allocated by
    /// `record_sale_cart`. Summing it over a `saleGroupId` reproduces the
    /// discount the shopkeeper typed, exactly -- the split floors and then
    /// hands the remainder out a paisa at a time, so nothing is lost to
    /// rounding and the receipt total never needs storing separately.
    @Default(0) double discountAmount,
    String? source, // 'voice' | 'image' | 'manual'
```

and:

```dart
  double get revenue => sellingPrice * quantity - discountAmount;
```

- [ ] **Step 4: Regenerate and run**

```bash
dart run build_runner build --delete-conflicting-outputs
flutter test test/transaction_discount_test.dart
```
Expected: PASS.

- [ ] **Step 5: Run the whole suite**

Run: `flutter test`
Expected: all pass. `SaleReceipt.totalRevenue` in `history_screen.dart` now returns discounted totals automatically — no change needed there.

- [ ] **Step 6: Commit**

```bash
git add lib/features/transactions/domain/ test/transaction_discount_test.dart
git commit -m "feat(transactions): carry each line's share of a cart discount"
```

---

### Task 3: Discount maths

**Files:**
- Create: `lib/features/cart/domain/discount_math.dart`
- Test: `test/discount_math_test.dart` (create)

**Interfaces:**
- Consumes: `CartLine` from `lib/features/cart/domain/cart_line.dart` (`product`, `quantity`, `subtotal`).
- Produces:
  - `double clampDiscount({required double entered, required double subtotal})`
  - `double cartCost(List<CartLine> lines)`
  - `double lossFromDiscount({required double subtotal, required double cost, required double discount})`

  Task 4 uses `clampDiscount`; Task 7 uses all three.

**Note:** the *split* is not here. It runs in `record_sale_cart` (Task 1) and is verified by the probe checklist — putting the same money logic in two languages would be worse than the problem it solves.

- [ ] **Step 1: Write the failing test**

Create `test/discount_math_test.dart`:

```dart
import 'package:ai_shopkeeper/features/cart/domain/cart_line.dart';
import 'package:ai_shopkeeper/features/cart/domain/discount_math.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:flutter_test/flutter_test.dart';

CartLine _line({
  required double selling,
  required double buying,
  required double qty,
}) => CartLine(
  product: Product(
    id: 'p${selling.toInt()}',
    shopId: 's1',
    name: 'x',
    sellingPrice: selling,
    buyingPrice: buying,
    quantity: 100,
  ),
  quantity: qty,
);

void main() {
  group('clampDiscount', () {
    test('passes a discount that fits', () {
      expect(clampDiscount(entered: 60, subtotal: 1360), 60);
    });

    test('never exceeds the bill', () {
      // The reason this exists: the cart can SHRINK after a discount is set.
      expect(clampDiscount(entered: 60, subtotal: 50), 50);
    });

    test('a discount equal to the bill is allowed', () {
      expect(clampDiscount(entered: 50, subtotal: 50), 50);
    });

    test('negatives collapse to zero', () {
      expect(clampDiscount(entered: -5, subtotal: 100), 0);
    });

    test('an empty cart takes no discount', () {
      expect(clampDiscount(entered: 60, subtotal: 0), 0);
    });
  });

  group('cartCost', () {
    test('sums buying price times quantity', () {
      final lines = [
        _line(selling: 45, buying: 30, qty: 2), // 60
        _line(selling: 850, buying: 700, qty: 1), // 700
      ];
      expect(cartCost(lines), 760);
    });

    test('an empty cart costs nothing', () {
      expect(cartCost(const []), 0);
    });
  });

  group('lossFromDiscount', () {
    test('is zero while the sale still profits', () {
      // 1000 bill, 800 cost => 200 profit. 150 off still profits.
      expect(lossFromDiscount(subtotal: 1000, cost: 800, discount: 150), 0);
    });

    test('is zero exactly at break-even', () {
      expect(lossFromDiscount(subtotal: 1000, cost: 800, discount: 200), 0);
    });

    test('reports how much is lost past break-even', () {
      expect(lossFromDiscount(subtotal: 1000, cost: 800, discount: 212), 12);
    });
  });
}
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `flutter test test/discount_math_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'discount_math.dart'`.

- [ ] **Step 3: Write the implementation**

Create `lib/features/cart/domain/discount_math.dart`:

```dart
import 'cart_line.dart';

/// The discount actually chargeable against a bill of [subtotal].
///
/// Clamping is not cosmetic: a discount is entered against one cart and the
/// shopkeeper can then remove lines from it. Rather than remember the larger
/// entered figure and display a smaller one, the controller stores the clamped
/// value -- a gap between the number on screen and the number sent to the
/// database is where money bugs live.
double clampDiscount({required double entered, required double subtotal}) {
  if (entered <= 0 || subtotal <= 0) return 0;
  return entered > subtotal ? subtotal : entered;
}

/// What the staged cart cost the shop -- buying price x quantity, summed.
/// Buying prices are already on the [CartLine]'s product, so this needs no
/// network call and the below-cost warning can be live as the field is typed.
double cartCost(List<CartLine> lines) => lines.fold<double>(
  0,
  (sum, l) => sum + l.product.buyingPrice * l.quantity,
);

/// How much money the shop loses if [discount] is applied -- 0 while the sale
/// still breaks even or profits.
///
/// Drives a warning, never a block: clearing near-expiry stock below cost is a
/// deliberate, normal thing to do, and the app is not the shopkeeper's boss.
double lossFromDiscount({
  required double subtotal,
  required double cost,
  required double discount,
}) {
  final net = subtotal - discount;
  return net >= cost ? 0 : cost - net;
}
```

- [ ] **Step 4: Run the test**

Run: `flutter test test/discount_math_test.dart`
Expected: PASS (13 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/cart/domain/discount_math.dart test/discount_math_test.dart
git commit -m "feat(cart): add discount clamping and below-cost maths"
```

---

### Task 4: `CartDiscountController`

**Files:**
- Create: `lib/features/cart/presentation/cart_discount_controller.dart`
- Test: `test/cart_discount_controller_test.dart` (create)

**Interfaces:**
- Consumes: `clampDiscount` (Task 3), `cartControllerProvider` and `cartTotal` (existing).
- Produces:
  - `class CartDiscountController extends Notifier<double>` with `void setAmount(double amount)` and `void clear()`
  - `final cartDiscountControllerProvider = NotifierProvider<CartDiscountController, double>(CartDiscountController.new)`

  Tasks 5, 7 and 8 all read this provider.

- [ ] **Step 1: Write the failing test**

Create `test/cart_discount_controller_test.dart`:

```dart
import 'package:ai_shopkeeper/features/cart/presentation/cart_controller.dart';
import 'package:ai_shopkeeper/features/cart/presentation/cart_discount_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/cart_harness.dart';

void main() {
  test('starts at zero', () async {
    final c = await cartContainer();
    expect(c.read(cartDiscountControllerProvider), 0);
  });

  test('holds a discount that fits the cart', () async {
    final c = await cartContainer();
    c.read(cartControllerProvider.notifier).addOrIncrement(kOil, 1); // 850
    c.read(cartDiscountControllerProvider.notifier).setAmount(60);
    expect(c.read(cartDiscountControllerProvider), 60);
  });

  test('clamps down when the cart shrinks below the discount', () async {
    // The case that makes this controller necessary: the discount is entered
    // against one cart and the shopkeeper then empties most of it.
    final c = await cartContainer();
    c.read(cartControllerProvider.notifier).addOrIncrement(kOil, 1); // 850
    c.read(cartControllerProvider.notifier).addOrIncrement(kPepsi, 1); // 45
    c.read(cartDiscountControllerProvider.notifier).setAmount(300);
    expect(c.read(cartDiscountControllerProvider), 300);

    c.read(cartControllerProvider.notifier).remove('p2'); // 45 left
    expect(
      c.read(cartDiscountControllerProvider),
      45,
      reason: 'the stored value must never exceed the bill it is charged to',
    );
  });

  test('emptying the cart clears the discount', () async {
    final c = await cartContainer();
    c.read(cartControllerProvider.notifier).addOrIncrement(kOil, 1);
    c.read(cartDiscountControllerProvider.notifier).setAmount(60);
    c.read(cartControllerProvider.notifier).clear();
    expect(c.read(cartDiscountControllerProvider), 0);
  });

  test('clear() drops it', () async {
    final c = await cartContainer();
    c.read(cartControllerProvider.notifier).addOrIncrement(kOil, 1);
    c.read(cartDiscountControllerProvider.notifier).setAmount(60);
    c.read(cartDiscountControllerProvider.notifier).clear();
    expect(c.read(cartDiscountControllerProvider), 0);
  });

  test('a negative entry is refused', () async {
    final c = await cartContainer();
    c.read(cartControllerProvider.notifier).addOrIncrement(kOil, 1);
    c.read(cartDiscountControllerProvider.notifier).setAmount(-10);
    expect(c.read(cartDiscountControllerProvider), 0);
  });
}
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `flutter test test/cart_discount_controller_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'cart_discount_controller.dart'`.

- [ ] **Step 3: Write the controller**

Create `lib/features/cart/presentation/cart_discount_controller.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/cart_math.dart';
import '../domain/discount_math.dart';
import 'cart_controller.dart';

/// A flat amount off the whole cart, held beside the cart rather than inside
/// it -- the same shape as [PaymentMethodController], which is also a small
/// per-checkout decision rather than part of the basket itself.
///
/// `build` WATCHES the cart, so the discount is re-clamped every time a line
/// is added, changed or removed. That is the whole reason this is a Notifier
/// and not a plain field: a discount is entered against one basket, and the
/// shopkeeper can then take things out of it. Storing the clamped value (as
/// opposed to remembering the larger entered figure and displaying a smaller
/// one) keeps the number on screen and the number sent to `record_sale_cart`
/// identical -- there is no second, hidden truth to disagree with.
class CartDiscountController extends Notifier<double> {
  double _entered = 0;

  @override
  double build() {
    final subtotal = cartTotal(ref.watch(cartControllerProvider));
    final clamped = clampDiscount(entered: _entered, subtotal: subtotal);
    _entered = clamped;
    return clamped;
  }

  void setAmount(double amount) {
    final subtotal = cartTotal(ref.read(cartControllerProvider));
    _entered = clampDiscount(entered: amount, subtotal: subtotal);
    state = _entered;
  }

  void clear() {
    _entered = 0;
    state = 0;
  }
}

final cartDiscountControllerProvider =
    NotifierProvider<CartDiscountController, double>(
      CartDiscountController.new,
    );
```

- [ ] **Step 4: Run the test**

Run: `flutter test test/cart_discount_controller_test.dart`
Expected: PASS (6 tests).

If the clamp-on-shrink test fails because `build()` did not re-run, the cause is
that `_entered` is instance state on a notifier Riverpod rebuilt — verify by
printing inside `build()`. The fix is to keep `_entered` but ensure the provider
is not `autoDispose`, which it is not above.

- [ ] **Step 5: Commit**

```bash
git add lib/features/cart/presentation/cart_discount_controller.dart test/cart_discount_controller_test.dart
git commit -m "feat(cart): hold a cart discount that re-clamps as the cart changes"
```

---

### Task 5: Send the discount to the RPC

**Files:**
- Modify: `lib/features/transactions/data/transaction_repository.dart:33-57`
- Modify: `lib/features/cart/presentation/cart_checkout_controller.dart:41-89`
- Test: `test/cart_checkout_discount_test.dart` (create)

**Interfaces:**
- Consumes: `cartDiscountControllerProvider` (Task 4).
- Produces: `recordSaleCart(..., double discount = 0)` sending `p_discount`; checkout clears the discount on success.

- [ ] **Step 1: Write the failing test**

First add `CapturingTransactionRepository` to `test/support/cart_harness.dart`
(the second half of the harness listing above — it could not go in earlier
because it overrides a parameter Step 3 introduces). Then create
`test/cart_checkout_discount_test.dart`:

```dart
import 'package:ai_shopkeeper/features/cart/presentation/cart_checkout_controller.dart';
import 'package:ai_shopkeeper/features/cart/presentation/cart_controller.dart';
import 'package:ai_shopkeeper/features/cart/presentation/cart_discount_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/cart_harness.dart';

void main() {
  test('checkout sends the staged discount', () async {
    final repo = CapturingTransactionRepository();
    final c = await cartContainer(repo: repo);
    c.read(cartControllerProvider.notifier).addOrIncrement(kOil, 1); // 850
    c.read(cartDiscountControllerProvider.notifier).setAmount(60);

    final ok = await c.read(cartCheckoutControllerProvider.notifier).checkout();

    expect(ok, isTrue);
    expect(repo.sentDiscount, 60);
  });

  test('an undiscounted checkout sends zero', () async {
    final repo = CapturingTransactionRepository();
    final c = await cartContainer(repo: repo);
    c.read(cartControllerProvider.notifier).addOrIncrement(kOil, 1);

    await c.read(cartCheckoutControllerProvider.notifier).checkout();

    expect(repo.sentDiscount, 0);
  });

  test('a successful checkout clears the discount', () async {
    // The cart is already cleared on success; a discount that survived would
    // silently apply itself to the NEXT customer's sale.
    final repo = CapturingTransactionRepository();
    final c = await cartContainer(repo: repo);
    c.read(cartControllerProvider.notifier).addOrIncrement(kOil, 1);
    c.read(cartDiscountControllerProvider.notifier).setAmount(60);

    await c.read(cartCheckoutControllerProvider.notifier).checkout();

    expect(c.read(cartDiscountControllerProvider), 0);
    expect(c.read(cartControllerProvider), isEmpty);
  });
}
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `flutter test test/cart_checkout_discount_test.dart`
Expected: FAIL — no `discount` parameter on `recordSaleCart`.

- [ ] **Step 3: Add the parameter to the repository**

In `lib/features/transactions/data/transaction_repository.dart`, extend
`recordSaleCart`:

```dart
  Future<Result<List<Transaction>>> recordSaleCart({
    required String shopId,
    required List<Map<String, dynamic>> items,
    String source = 'manual',
    String? customerId,
    double discount = 0,
  }) async {
    try {
      final result = await _client.rpc(
        'record_sale_cart',
        params: {
          'p_shop_id': shopId,
          'p_items': items,
          'p_source': source,
          'p_customer_id': ?customerId,
          'p_discount': discount,
        },
      );
```

Leave the rest of the method unchanged.

- [ ] **Step 4: Send it from the checkout controller**

In `lib/features/cart/presentation/cart_checkout_controller.dart`, read the
discount beside the lines (after line 45) and pass it:

```dart
    final lines = ref.read(cartControllerProvider);
    final discount = ref.read(cartDiscountControllerProvider);
```

```dart
          .recordSaleCart(
            shopId: shopId,
            items: cartItemsPayload(lines),
            source: source,
            customerId: customerId,
            discount: discount,
          );
```

and clear it in the success branch, next to the existing `clear()`:

```dart
      success: (_) {
        ref.read(cartControllerProvider.notifier).clear();
        ref.read(cartDiscountControllerProvider.notifier).clear();
```

Add the import:

```dart
import 'cart_discount_controller.dart';
```

- [ ] **Step 5: Run the tests**

Run: `flutter test test/cart_checkout_discount_test.dart && flutter test`
Expected: both PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/transactions/data/transaction_repository.dart lib/features/cart/presentation/cart_checkout_controller.dart test/cart_checkout_discount_test.dart
git commit -m "feat(cart): send the cart discount to record_sale_cart"
```

---

### Task 6: Strings

**Files:**
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_bn.arb`

**Interfaces:**
- Produces: `l10n.cart_addDiscount`, `l10n.cart_discount`, `l10n.cart_discountTitle`, `l10n.cart_discountAmount`, `l10n.cart_discountRemove`, `l10n.cart_discountBelowCost`, `l10n.cart_apply`. Tasks 7, 8 and 9 use these.

`common_subtotal` already exists in both files — reuse it, do not add a second key.

- [ ] **Step 1: Add the English strings**

In `lib/l10n/app_en.arb`, after `"cart_checkoutFailed"`:

```json
  "cart_addDiscount": "Add discount",
  "cart_discount": "Discount",
  "cart_discountTitle": "Discount",
  "cart_discountAmount": "Amount off",
  "cart_discountRemove": "Remove discount",
  "cart_discountBelowCost": "You'd lose {amount} on this sale",
  "@cart_discountBelowCost": { "placeholders": { "amount": { "type": "String" } } },
  "cart_apply": "Apply",
```

- [ ] **Step 2: Add the Bengali strings**

In `lib/l10n/app_bn.arb`, at the matching position:

```json
  "cart_addDiscount": "ছাড় দিন",
  "cart_discount": "ছাড়",
  "cart_discountTitle": "ছাড়",
  "cart_discountAmount": "ছাড়ের পরিমাণ",
  "cart_discountRemove": "ছাড় সরান",
  "cart_discountBelowCost": "এই বিক্রিতে {amount} লোকসান হবে",
  "@cart_discountBelowCost": { "placeholders": { "amount": { "type": "String" } } },
  "cart_apply": "প্রয়োগ করুন",
```

- [ ] **Step 3: Regenerate and verify**

```bash
flutter gen-l10n
flutter analyze
```
Expected: "No issues found!" and no untranslated-message warnings for the new keys.

- [ ] **Step 4: Commit**

```bash
git add lib/l10n/
git commit -m "feat(l10n): strings for the cart discount"
```

---

### Task 7: The discount sheet

**Files:**
- Create: `lib/features/cart/presentation/discount_sheet.dart`
- Test: `test/widgets/discount_sheet_test.dart` (create)

**Interfaces:**
- Consumes: `clampDiscount`, `cartCost`, `lossFromDiscount` (Task 3); `cartDiscountControllerProvider` (Task 4); the Task 6 strings.
- Produces: `Future<void> showDiscountSheet(BuildContext context)`. Task 8 calls it.

Follow `showAddToCartSheet` in `lib/features/cart/presentation/add_to_cart_sheet.dart:15-27` exactly for the sheet wrapper (`isScrollControlled`, `showDragHandle`, `backgroundColor` from the scheme).

- [ ] **Step 1: Write the failing test**

Create `test/widgets/discount_sheet_test.dart`:

```dart
import 'package:ai_shopkeeper/features/cart/presentation/cart_controller.dart';
import 'package:ai_shopkeeper/features/cart/presentation/cart_discount_controller.dart';
import 'package:ai_shopkeeper/features/cart/presentation/discount_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import '../support/cart_harness.dart';

/// Opens the sheet over a cart holding one 850-sell / 700-buy line, so the
/// sale carries exactly 150 profit and a 162 discount lands 12 below cost.
Future<ProviderContainer> _openSheet(WidgetTester tester) async {
  final c = await cartContainer();
  c.read(cartControllerProvider.notifier).addOrIncrement(kOil, 1);
  await tester.pumpWidget(
    cartApp(
      c,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDiscountSheet(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return c;
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('applying an amount stages it on the controller', (tester) async {
    final c = await _openSheet(tester);
    await tester.enterText(find.byType(TextField), '60');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(c.read(cartDiscountControllerProvider), 60);
  });

  testWidgets('an amount over the bill is clamped, not rejected', (
    tester,
  ) async {
    final c = await _openSheet(tester);
    await tester.enterText(find.byType(TextField), '9000');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(c.read(cartDiscountControllerProvider), 850);
  });

  testWidgets('warns when the sale would go below cost', (tester) async {
    await _openSheet(tester);
    await tester.enterText(find.byType(TextField), '162');
    await tester.pump();
    expect(find.textContaining('lose'), findsOneWidget);
  });

  testWidgets('the below-cost warning does not disable Apply', (tester) async {
    await _openSheet(tester);
    await tester.enterText(find.byType(TextField), '162');
    await tester.pump();
    final apply = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(
      apply.onPressed,
      isNotNull,
      reason: 'clearing stock at a loss is deliberate, not a mistake',
    );
  });

  testWidgets('no warning while the sale still profits', (tester) async {
    await _openSheet(tester);
    await tester.enterText(find.byType(TextField), '100');
    await tester.pump();
    expect(find.textContaining('lose'), findsNothing);
  });
}
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `flutter test test/widgets/discount_sheet_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'discount_sheet.dart'`.

- [ ] **Step 3: Write the sheet**

Create `lib/features/cart/presentation/discount_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../shared/extensions/format.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/cart_math.dart';
import '../domain/discount_math.dart';
import 'cart_controller.dart';
import 'cart_discount_controller.dart';

/// Enters a flat amount off the whole cart. Mirrors `showAddToCartSheet`'s
/// wrapper so the discount step feels like the rest of the cart flow.
Future<void> showDiscountSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (_) => const _DiscountSheet(),
  );
}

class _DiscountSheet extends ConsumerStatefulWidget {
  const _DiscountSheet();

  @override
  ConsumerState<_DiscountSheet> createState() => _DiscountSheetState();
}

class _DiscountSheetState extends ConsumerState<_DiscountSheet> {
  late final TextEditingController _field;

  @override
  void initState() {
    super.initState();
    final current = ref.read(cartDiscountControllerProvider);
    _field = TextEditingController(text: current > 0 ? '$current' : '');
    _field.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  double get _typed => double.tryParse(_field.text.trim()) ?? 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    final currency = ref.watch(myShopProvider).value?.currency ?? 'USD';
    final lines = ref.watch(cartControllerProvider);
    final subtotal = cartTotal(lines);

    // Live as the field is typed: buying prices are already on the staged
    // products, so this costs no network call.
    final loss = lossFromDiscount(
      subtotal: subtotal,
      cost: cartCost(lines),
      discount: clampDiscount(entered: _typed, subtotal: subtotal),
    );

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.cart_discountTitle,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: Text(l10n.common_subtotal)),
              Text(
                Money.format(subtotal, currencyCode: currency),
                style: theme.textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _field,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: InputDecoration(
              labelText: l10n.cart_discountAmount,
              border: const OutlineInputBorder(),
            ),
          ),
          if (loss > 0) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 18, color: scheme.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.cart_discountBelowCost(
                      Money.format(loss, currencyCode: currency),
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.common_cancel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  // Never disabled by the warning above: selling below cost to
                  // clear stock is a deliberate act, not a mistake.
                  onPressed: () {
                    ref
                        .read(cartDiscountControllerProvider.notifier)
                        .setAmount(_typed);
                    Navigator.of(context).pop();
                  },
                  child: Text(l10n.cart_apply),
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

If `l10n.common_cancel` does not exist, check the actual key with
`grep -n '"common_cancel"' lib/l10n/app_en.arb` and use whatever the codebase
already has for a cancel button.

- [ ] **Step 4: Run the tests**

Run: `flutter test test/widgets/discount_sheet_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Format and commit**

```bash
dart format lib/features/cart/presentation/discount_sheet.dart test/widgets/discount_sheet_test.dart
git add lib/features/cart/presentation/discount_sheet.dart test/widgets/discount_sheet_test.dart
git commit -m "feat(cart): discount entry sheet with a below-cost warning"
```

---

### Task 8: The checkout bar rows

**Files:**
- Modify: `lib/features/cart/presentation/cart_screen.dart:450-552`
- Test: `test/widgets/cart_discount_bar_test.dart` (create)

**Interfaces:**
- Consumes: `showDiscountSheet` (Task 7), `cartDiscountControllerProvider` (Task 4), Task 6 strings.
- Produces: nothing other tasks depend on.

The bar currently renders one Total row (`cart_screen.dart:530-551`). It gains a
tappable "＋ Add discount" row, and — **only when a discount is set** — Subtotal
and Discount rows above the Total. With no discount the bar must look exactly as
it does today.

- [ ] **Step 1: Write the failing test**

Create `test/widgets/cart_discount_bar_test.dart`:

```dart
import 'package:ai_shopkeeper/features/cart/presentation/cart_controller.dart';
import 'package:ai_shopkeeper/features/cart/presentation/cart_discount_controller.dart';
import 'package:ai_shopkeeper/features/cart/presentation/cart_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import '../support/cart_harness.dart';

Future<ProviderContainer> _cartScreen(WidgetTester tester) async {
  final c = await cartContainer();
  c.read(cartControllerProvider.notifier).addOrIncrement(kOil, 1); // 850
  await tester.pumpWidget(cartApp(c, const CartScreen()));
  await tester.pumpAndSettle();
  return c;
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('with no discount the bar shows only the total', (tester) async {
    await _cartScreen(tester);
    expect(find.text('Add discount'), findsOneWidget);
    expect(find.text('Discount'), findsNothing);
    expect(
      find.text('Subtotal'),
      findsNothing,
      reason: 'the no-discount sale is the common case and must not gain rows',
    );
  });

  testWidgets('a staged discount adds the subtotal and discount rows', (
    tester,
  ) async {
    final c = await _cartScreen(tester);
    c.read(cartDiscountControllerProvider.notifier).setAmount(60);
    await tester.pumpAndSettle();
    expect(find.text('Subtotal'), findsOneWidget);
    expect(find.text('Discount'), findsOneWidget);
    expect(find.text('Add discount'), findsNothing);
  });

  testWidgets('the remove button clears the discount', (tester) async {
    final c = await _cartScreen(tester);
    c.read(cartDiscountControllerProvider.notifier).setAmount(60);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Remove discount'));
    await tester.pumpAndSettle();

    expect(c.read(cartDiscountControllerProvider), 0);
    expect(find.text('Discount'), findsNothing);
  });
}
```

If `CartScreen` requires router context that `cartApp` does not supply, pump
`_CheckoutBar`'s parent `Scaffold` directly instead — the three assertions are
what matter, not the wrapper.

- [ ] **Step 2: Run it and confirm it fails**

Run: `flutter test test/widgets/cart_discount_bar_test.dart`
Expected: FAIL — "Add discount" not found.

- [ ] **Step 3: Add the rows**

In `_CheckoutBar.build`, read the discount next to the existing `selection`:

```dart
    final discount = ref.watch(cartDiscountControllerProvider);
```

Then replace the single Total row (`cart_screen.dart:530-551`) with:

```dart
              if (discount > 0) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.common_subtotal,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Text(
                      Money.format(total + discount, currencyCode: currency),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.cart_discount,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Text(
                      '−${Money.format(discount, currencyCode: currency)}',
                      style: theme.textTheme.bodyMedium,
                    ),
                    IconButton(
                      onPressed: isLoading
                          ? null
                          : () => ref
                              .read(cartDiscountControllerProvider.notifier)
                              .clear(),
                      icon: const Icon(Icons.close_rounded, size: 16),
                      visualDensity: VisualDensity.compact,
                      tooltip: l10n.cart_discountRemove,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
              ] else ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: isLoading
                        ? null
                        : () => showDiscountSheet(context),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(l10n.cart_addDiscount),
                  ),
                ),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      l10n.cart_totalItems(itemCount),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    Money.format(total, currencyCode: currency),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
```

Note `total` is the **net** figure the caller already passes; the Subtotal row
adds the discount back rather than plumbing a second value through. Update the
call site at `cart_screen.dart:165-170` so `total:` is
`cartTotal(lines) - ref.watch(cartDiscountControllerProvider)`.

Add the import:

```dart
import 'discount_sheet.dart';
```

- [ ] **Step 4: Run the tests**

Run: `flutter test test/widgets/cart_discount_bar_test.dart && flutter test`
Expected: both PASS.

- [ ] **Step 5: Format and commit**

Check first whether `cart_screen.dart` was formatted at HEAD (see Global
Constraints); only format it if it was.

```bash
git add lib/features/cart/presentation/cart_screen.dart test/widgets/cart_discount_bar_test.dart
git commit -m "feat(cart): show and clear a discount in the checkout bar"
```

---

### Task 9: Show the discount on a past sale

**Files:**
- Modify: `lib/features/transactions/presentation/sale_detail_screen.dart:96-109`
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_bn.arb`
- Test: `test/widgets/sale_detail_discount_test.dart` (create)

**Interfaces:**
- Consumes: `Transaction.discountAmount` (Task 2).
- Produces: nothing.

Without this the screen shows visibly broken arithmetic: "Price each ৳45",
"Quantity 2", "Total ৳80". The discount row is what makes those three numbers
agree.

The grouped receipt list in `history_screen.dart` needs **no change** —
`SaleReceipt.totalRevenue` sums `t.revenue`, which Task 2 already made net.

- [ ] **Step 1: Add the two strings**

`lib/l10n/app_en.arb`: `"saleDetail_discount": "Discount",`
`lib/l10n/app_bn.arb`: `"saleDetail_discount": "ছাড়",`

Then `flutter gen-l10n`.

- [ ] **Step 2: Write the failing test**

Create `test/widgets/sale_detail_discount_test.dart`:

```dart
import 'package:ai_shopkeeper/features/transactions/domain/transaction.dart';
import 'package:ai_shopkeeper/features/transactions/presentation/sale_detail_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import '../support/cart_harness.dart';

const _discounted = Transaction(
  id: 't1',
  shopId: 's1',
  productId: 'p1',
  type: 'sale',
  quantity: 2,
  buyingPrice: 30,
  sellingPrice: 45,
  discountAmount: 10,
);

const _plain = Transaction(
  id: 't2',
  shopId: 's1',
  productId: 'p1',
  type: 'sale',
  quantity: 2,
  buyingPrice: 30,
  sellingPrice: 45,
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('a discounted line shows subtotal, discount and total', (
    tester,
  ) async {
    final c = await cartContainer();
    await tester.pumpWidget(
      cartApp(c, const SaleDetailScreen(sale: _discounted)),
    );
    await tester.pumpAndSettle();

    // Without these rows the screen reads as broken arithmetic: "45 each",
    // "quantity 2", "total 80".
    expect(find.text('Subtotal'), findsOneWidget);
    expect(find.text('Discount'), findsOneWidget);
  });

  testWidgets('an undiscounted line is unchanged', (tester) async {
    final c = await cartContainer();
    await tester.pumpWidget(cartApp(c, const SaleDetailScreen(sale: _plain)));
    await tester.pumpAndSettle();

    expect(find.text('Discount'), findsNothing);
    expect(find.text('Subtotal'), findsNothing);
  });
}
```

- [ ] **Step 3: Run it and confirm it fails**

Run: `flutter test test/widgets/sale_detail_discount_test.dart`
Expected: FAIL — "Subtotal" not found.

- [ ] **Step 4: Add the rows**

In `sale_detail_screen.dart`, replace the single total row (lines 98-102) with:

```dart
          if (t.discountAmount > 0) ...[
            _DetailRow(
              label: l10n.common_subtotal,
              value: money(t.sellingPrice * t.quantity),
            ),
            _DetailRow(
              label: l10n.saleDetail_discount,
              value: '−${money(t.discountAmount)}',
            ),
          ],
          _DetailRow(
            label: l10n.saleDetail_total,
            value: money(t.revenue),
            emphasize: true,
          ),
```

- [ ] **Step 5: Run the tests**

Run: `flutter test`
Expected: all pass.

- [ ] **Step 6: Format and commit**

```bash
git add lib/features/transactions/presentation/sale_detail_screen.dart lib/l10n/ test/widgets/sale_detail_discount_test.dart
git commit -m "feat(history): show the discount on a past sale's detail"
```

---

### Task 10: Close out

- [ ] **Step 1: Full verification**

```bash
flutter analyze
flutter test
```
Expected: "No issues found!" and every test passing. The suite should be around
**350** (322 + roughly 28 new).

- [ ] **Step 2: Mark the spec built**

In `docs/superpowers/specs/2026-08-06-cart-discount-design.md`, change
`**Status:** designed, not yet implemented` to `**Status:** shipped as <commit>`,
and record in a new `## 12. Built` section anything that turned out differently
from the design — especially any place the plan's code did not survive contact.

In `docs/00-Map.md`, drop "(designed, not yet built)" from the entry.

- [ ] **Step 3: Commit**

```bash
git add docs/
git commit -m "docs: mark the cart discount design as built"
```

- [ ] **Step 4: Tell the user what they must do**

The feature does nothing until the user applies
`supabase/migrations/0009_cart_discount.sql` in the Supabase Dashboard SQL
editor and works the probe checklist in `supabase/README.md`. **Say this
explicitly** — and say that the migration must be applied *before* the new build
is installed, because a new build against the old function fails every sale, not
only discounted ones.
