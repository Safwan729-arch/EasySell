# Supabase — database setup (Member A)

We apply SQL through the **hosted Supabase project + Dashboard SQL Editor** (no local CLI/Docker).

## 1. Create the project (one-time)
1. Go to <https://supabase.com/dashboard> → **New project**.
2. Note the **Project URL** and the **anon / publishable** API key
   (Project Settings → API). These feed the app via `--dart-define`
   (`SUPABASE_URL`, `SUPABASE_ANON_KEY`). Never commit them.

## 2. Apply the migration
1. Dashboard → **SQL Editor** → **New query**.
2. Paste the entire contents of [`migrations/0001_init.sql`](migrations/0001_init.sql).
3. Click **Run**. It is idempotent (`if not exists` / `or replace`), so re-running is safe.

Apply migrations **in filename order** (`0001_…`, then `0002_…`, …) as new ones are added.

> **Analytics:** run [`migrations/0002_analytics.sql`](migrations/0002_analytics.sql) after `0001`.
> It adds `get_sales_series` (the revenue/profit time series the charts render).
> Without it, the dashboard/analytics charts will show a load error.
>
> **Inventory redesign:** run [`migrations/0003_inventory_units_categories.sql`](migrations/0003_inventory_units_categories.sql)
> after `0002`. It adds the unit model (`unit_type`/`unit`), makes quantities
> decimal, adds the shop-scoped `categories` table + `upsert_category` RPC,
> recreates `record_sale`/`record_restock` for decimal quantities, seeds
> default categories on shop creation, and enables Realtime on
> `products`/`categories`. Idempotent — safe to re-run.
>
> **Category management:** run [`migrations/0004_category_management.sql`](migrations/0004_category_management.sql)
> after `0003`. It adds the `rename_category` RPC (normalized rename with
> collision rejection) used by the Manage Categories screen. Idempotent.

## 3. Verify the critical `record_sale` RPC (oversell test)
Run this in a **new** SQL Editor query. It runs as the privileged editor (bypasses
RLS), so it sets up its own shop/product and proves the atomicity guarantees.

```sql
do $$
declare
  v_shop uuid;
  v_product uuid;
  v_qty integer;
  v_txn_count integer;
begin
  -- Arrange: a shop + a product with quantity 5.
  insert into shops (owner_id, name)
    values (gen_random_uuid(), 'TEST SHOP') returning id into v_shop;
  insert into products (shop_id, name, quantity, buying_price, selling_price)
    values (v_shop, 'Test Cola', 5, 10.00, 15.00) returning id into v_product;

  -- 1) OVERSELL must raise AND change nothing.
  begin
    perform record_sale(v_shop, v_product, 6, 'manual');
    raise exception 'FAIL: oversell did not raise';
  exception
    when others then
      if sqlerrm like 'FAIL:%' then raise; end if;
      raise notice 'OK: oversell raised -> %', sqlerrm;
  end;

  select quantity into v_qty from products where id = v_product;
  select count(*) into v_txn_count from transactions where product_id = v_product;
  if v_qty <> 5 then raise exception 'FAIL: stock changed on failed sale (%).', v_qty; end if;
  if v_txn_count <> 0 then raise exception 'FAIL: txn recorded on failed sale (%).', v_txn_count; end if;
  raise notice 'OK: after oversell, stock=5, txns=0';

  -- 2) VALID sale of 3 must decrement to 2 and record one txn with frozen prices.
  perform record_sale(v_shop, v_product, 3, 'manual');
  select quantity into v_qty from products where id = v_product;
  select count(*) into v_txn_count from transactions where product_id = v_product;
  if v_qty <> 2 then raise exception 'FAIL: expected stock 2, got %.', v_qty; end if;
  if v_txn_count <> 1 then raise exception 'FAIL: expected 1 txn, got %.', v_txn_count; end if;
  raise notice 'OK: valid sale -> stock=2, txns=1 (prices frozen at 10.00/15.00)';

  -- Cleanup.
  delete from shops where id = v_shop;  -- cascades to products + transactions
  raise notice 'ALL CHECKS PASSED';
end $$;
```

Expected output: a series of `OK:` notices ending with **`ALL CHECKS PASSED`**.
Any `FAIL:` means the RPC is not behaving and must be fixed before building on it.

## 4. Verify the inventory redesign (0003)

Run these in a **new** SQL Editor query (privileged, so they seed their own data).

### 4a. `upsert_category` deduplicates by normalized name

```sql
do $$
declare
  v_shop uuid;
  v_a categories;
  v_b categories;
  v_count integer;
begin
  insert into shops (owner_id, name)
    values (gen_random_uuid(), 'TEST CAT SHOP') returning id into v_shop;

  -- Same name, different casing + spacing → must return the SAME row.
  v_a := upsert_category(v_shop, 'Frozen items');
  v_b := upsert_category(v_shop, '  frozen   items ');

  if v_a.id <> v_b.id then
    raise exception 'FAIL: dedup produced two rows (% vs %)', v_a.id, v_b.id;
  end if;

  select count(*) into v_count
    from categories
    where shop_id = v_shop and name_normalized = 'frozen items';
  if v_count <> 1 then raise exception 'FAIL: expected 1 row, got %', v_count; end if;

  -- Empty / whitespace-only names must be rejected.
  begin
    perform upsert_category(v_shop, '   ');
    raise exception 'FAIL: empty name was accepted';
  exception
    when others then
      if sqlerrm like 'FAIL:%' then raise; end if;
      raise notice 'OK: empty name rejected -> %', sqlerrm;
  end;

  raise notice 'OK: dedup returned one row (%), display name kept as "%"',
    v_a.id, v_a.name;

  delete from shops where id = v_shop;  -- cascades to categories
  raise notice 'ALL CATEGORY CHECKS PASSED';
end $$;
```

### 4b. `record_sale` on DECIMAL quantities (oversell still blocked)

```sql
do $$
declare
  v_shop uuid;
  v_product uuid;
  v_qty numeric;
  v_txn_count integer;
begin
  insert into shops (owner_id, name)
    values (gen_random_uuid(), 'TEST WEIGHT SHOP') returning id into v_shop;
  -- 2 kg of loose rice, priced per kg.
  insert into products (shop_id, name, unit_type, unit, quantity, buying_price, selling_price)
    values (v_shop, 'Loose Rice', 'weight', 'kg', 2.000, 60.00, 80.00)
    returning id into v_product;

  -- 1) Sell 3 kg when only 2 kg in stock → must raise and change nothing.
  begin
    perform record_sale(v_shop, v_product, 3.0, 'manual');
    raise exception 'FAIL: decimal oversell did not raise';
  exception
    when others then
      if sqlerrm like 'FAIL:%' then raise; end if;
      raise notice 'OK: decimal oversell raised -> %', sqlerrm;
  end;

  select quantity into v_qty from products where id = v_product;
  select count(*) into v_txn_count from transactions where product_id = v_product;
  if v_qty <> 2.000 then raise exception 'FAIL: stock changed on failed sale (%)', v_qty; end if;
  if v_txn_count <> 0 then raise exception 'FAIL: txn recorded on failed sale (%)', v_txn_count; end if;

  -- 2) Sell 1.5 kg → stock 0.5, one txn with frozen per-unit prices.
  perform record_sale(v_shop, v_product, 1.5, 'manual');
  select quantity into v_qty from products where id = v_product;
  if v_qty <> 0.500 then raise exception 'FAIL: expected 0.5 kg, got %', v_qty; end if;
  raise notice 'OK: sold 1.5 kg -> stock=0.5 kg, prices frozen at 60.00/80.00 per kg';

  delete from shops where id = v_shop;  -- cascades to products + transactions
  raise notice 'ALL DECIMAL-SALE CHECKS PASSED';
end $$;
```

Both blocks should end with `ALL … CHECKS PASSED` and no `FAIL:` notices.

## 5. Verify `record_sale_cart` (atomic multi-item checkout)

Run this in a **new** SQL Editor query (privileged, seeds its own data).

```sql
do $$
declare
  v_shop uuid;
  v_a uuid;
  v_b uuid;
  v_qty_a numeric;
  v_qty_b numeric;
  v_txn_count integer;
begin
  insert into shops (owner_id, name)
    values (gen_random_uuid(), 'TEST CART SHOP') returning id into v_shop;
  insert into products (shop_id, name, quantity, buying_price, selling_price)
    values (v_shop, 'Cart Item A', 5, 10.00, 15.00) returning id into v_a;
  insert into products (shop_id, name, quantity, buying_price, selling_price)
    values (v_shop, 'Cart Item B', 2, 4.00, 6.00) returning id into v_b;

  -- 1) A checkout where one line oversells must raise AND change NOTHING --
  -- not even the line that would have succeeded on its own.
  begin
    perform record_sale_cart(
      v_shop,
      jsonb_build_array(
        jsonb_build_object('product_id', v_a, 'quantity', 1),
        jsonb_build_object('product_id', v_b, 'quantity', 5)
      ),
      'manual'
    );
    raise exception 'FAIL: oversold cart did not raise';
  exception
    when others then
      if sqlerrm like 'FAIL:%' then raise; end if;
      raise notice 'OK: oversold cart raised -> %', sqlerrm;
  end;

  select quantity into v_qty_a from products where id = v_a;
  select quantity into v_qty_b from products where id = v_b;
  select count(*) into v_txn_count from transactions where product_id in (v_a, v_b);
  if v_qty_a <> 5 or v_qty_b <> 2 then
    raise exception 'FAIL: stock changed on a failed checkout (a=%, b=%)', v_qty_a, v_qty_b;
  end if;
  if v_txn_count <> 0 then
    raise exception 'FAIL: txns recorded on a failed checkout (%)', v_txn_count;
  end if;
  raise notice 'OK: after the failed checkout, stock is unchanged and no txns exist';

  -- 2) A valid 2-item checkout must decrement both and tag both rows with the
  -- SAME sale_group_id.
  perform record_sale_cart(
    v_shop,
    jsonb_build_array(
      jsonb_build_object('product_id', v_a, 'quantity', 2),
      jsonb_build_object('product_id', v_b, 'quantity', 1)
    ),
    'manual'
  );
  select quantity into v_qty_a from products where id = v_a;
  select quantity into v_qty_b from products where id = v_b;
  if v_qty_a <> 3 or v_qty_b <> 1 then
    raise exception 'FAIL: expected stock a=3 b=1, got a=% b=%', v_qty_a, v_qty_b;
  end if;

  select count(distinct sale_group_id) into v_txn_count
    from transactions where product_id in (v_a, v_b) and type = 'sale';
  if v_txn_count <> 1 then
    raise exception 'FAIL: expected both lines under one sale_group_id, got % distinct', v_txn_count;
  end if;
  raise notice 'OK: valid checkout -> stock a=3 b=1, both lines share one sale_group_id';

  delete from shops where id = v_shop;  -- cascades to products + transactions
  raise notice 'ALL CART CHECKS PASSED';
end $$;
```

Expected output: `OK:` notices ending with **`ALL CART CHECKS PASSED`**. Any `FAIL:` means the RPC is not behaving and must be fixed before building on it.

## Notes
- **Realtime:** the inventory list and category picker use Supabase Realtime, which
  only fires for tables in the `supabase_realtime` publication. `0003` adds
  `products` and `categories` to it, so newly created items appear live. If you
  applied `0003` before this section existed, re-run it (idempotent) or toggle
  Realtime on for those tables under Database → Replication in the Dashboard.
- `analytics_daily` exists but is intentionally unused for the MVP; dashboards read
  `get_dashboard_summary`, which aggregates live from `transactions`.
- RLS is enforced for app traffic (anon/authenticated). The SQL Editor runs with
  elevated privileges, which is why the test above can seed its own data.
- `get_dashboard_summary.units_sold` still casts the summed quantity to `bigint`,
  so it rounds decimal (weight/volume) sales and mixes unit types. This is a known
  analytics limitation to revisit; it is intentionally out of scope for `0003`.

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

4. **Over-discount is rejected.** This one CANNOT be done from the app — the
   discount sheet clamps whatever is typed down to the legal maximum and sends
   a value the function accepts, so an "over-discount" attempt in the UI checks
   out successfully and proves nothing. Call the function directly instead.

   First get real ids to substitute (any shop with at least one in-stock
   product):

   ```sql
   select p.id as product_id, p.shop_id, p.name, p.selling_price, p.quantity
     from products p
     where p.quantity > 0
     limit 2;
   ```

   Then paste the two ids into the call below, keeping `p_discount` far larger
   than the bill. The uuids here are placeholders — replace both.

   ```sql
   select record_sale_cart(
     'a1b2c3d4-1111-4a1a-9c11-0123456789ab'::uuid,   -- p_shop_id
     jsonb_build_array(
       jsonb_build_object(
         'product_id', 'b2c3d4e5-2222-4b2b-9c22-0123456789ab'::uuid,
         'quantity', 1
       )
     ),                                              -- p_items
     'manual',                                       -- p_source
     null,                                           -- p_customer_id
     999999                                          -- p_discount
   );
   ```

   Expect it to FAIL with:
   `ERROR: Discount exceeds total: most you can take off is <max>, asked for 999999`
   — e.g. `most you can take off is 850.00, asked for 999999`. The quoted figure
   is the per-line-floored maximum the guard actually compared against, not the
   raw subtotal. Because the exception aborts
   the function, nothing it did survives: re-run the `select` above and the
   product's `quantity` must be unchanged, and
   `select count(*) from transactions where product_id = '<product-uuid>';`
   must not have grown.

5. Credit sale: check out on credit with a discount, then
   `select amount from customer_ledger where sale_group_id = '<id>';`
   Expect the DISCOUNTED total.

6. Dashboard revenue drops by the discount, and `cost` does NOT change.

7. **Credit sale discounted to zero.** In the app, check out on credit with a
   discount equal to the full bill (e.g. one line, 50.00 x 1, discount 50.00).
   Expect: the sale succeeds, stock decrements as normal, and
   `select * from customer_ledger where sale_group_id = '<id>';` returns
   **NO rows** — a fully discounted credit sale still happens, it just creates
   no debt. (It must NOT roll back the whole checkout: `customer_ledger.amount`
   has `check (amount > 0)`, so a naive unconditional insert of a zero total
   would fail and take the stock decrements down with it.)

8. **Fractional quantity discounted in full.** In the app, cart a line with a
   fractional (weight/volume) quantity that produces a 3-decimal line total —
   e.g. 2.501 kg at 45.00/kg = 112.545 — alongside a second, ordinary line
   (e.g. 1 unit at 10.00 = 10.00), for a subtotal of 122.545. Discount by
   122.54 (the bill floored to the nearest paisa — the true max, since
   `discount_amount` is `numeric(10,2)` and can't hold a third decimal).
   Expect: the checkout **succeeds**, `sum(discount_amount)` for the
   `sale_group_id` is exactly 122.54, and neither row's `discount_amount`
   exceeds its own `selling_price * quantity` (no
   `transactions_discount_within_line` violation).

   The maximum is the sum of the **per-line** subtotals each floored to whole
   paisa (112.545 → 112.54, plus 10.00, = 122.54), not the floor of the summed
   subtotal. ("Floored to paisa" throughout this section means
   `floor(v * 100) / 100`, never SQL's bare `floor()`, which would give 112.)
   The two agree here; they do not on a cart of two 112.545 lines, where
   floor-of-sum would permit 225.09 but only 225.08 can actually be placed.

   Then confirm the rejection — again NOT from the app, whose sheet clamps a
   too-large amount down to the legal one and checks out successfully. Call the
   function directly, substituting the real shop/product ids (uuids below are
   placeholders) and asking for one paisa past the maximum:

   ```sql
   select record_sale_cart(
     'a1b2c3d4-1111-4a1a-9c11-0123456789ab'::uuid,   -- p_shop_id
     jsonb_build_array(
       jsonb_build_object(
         'product_id', 'c3d4e5f6-3333-4c3c-9c33-0123456789ab'::uuid, -- 45.00/kg
         'quantity', 2.501
       ),
       jsonb_build_object(
         'product_id', 'd4e5f6a7-4444-4d4d-9c44-0123456789ab'::uuid, -- 10.00 ea
         'quantity', 1
       )
     ),
     'manual',
     null,
     122.545                                         -- one notch over the max
   );
   ```

   Expect it to FAIL with:
   `ERROR: Discount exceeds total: most you can take off is 122.54, asked for 122.545`
   (and the same for 122.55). The residual half-paisa can never be discounted,
   by design: `discount_amount` is `numeric(10,2)`. Stock must be unchanged
   afterwards — the exception rolls the whole call back.

9. **Credit sale on a fractional-quantity line, discounted to its floored
   maximum.** In the app, cart one fractional-quantity line whose subtotal
   carries more than two decimals (e.g. 45.99/kg x 2.501 kg = 115.02099), and
   discount it by its floored maximum (115.02). Check out **on credit**.
   Expect: the checkout **succeeds** — never a rollback — and either writes
   ONE rounded `customer_ledger` row (`select amount from customer_ledger
   where sale_group_id = '<id>';`) or none at all, if the discounted
   remainder rounds to 0.00. Stock must decrement in every case. (A raw
   remainder as small as 0.00499 previously passed the `> 0` guard but
   rounded to 0.00 on insert, tripping `customer_ledger`'s
   `check (amount > 0)` and rolling back the whole checkout.)
