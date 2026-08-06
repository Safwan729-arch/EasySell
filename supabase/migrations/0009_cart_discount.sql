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
  v_subtotal numeric;
  v_max      numeric;
  v_share    numeric;
  v_assigned numeric := 0;
  v_left     numeric;
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
  if p_discount is not null and p_discount < 0 then
    raise exception 'Discount cannot be negative';
  end if;

  if p_discount is not null and p_discount > 0 then
    select coalesce(sum(selling_price * quantity), 0) into v_subtotal
      from transactions where sale_group_id = v_group;

    -- The ceiling is the sum of the PER-LINE floored subtotals, not the floor
    -- of the summed subtotal. Each line's share is floored (see below) and can
    -- never exceed that line's own value, so the sum of those floors is the
    -- most the split can actually place -- and capping there makes the maximum
    -- exactly allocatable by construction.
    --
    -- floor(sum) is strictly larger on some carts, and the difference is a
    -- paisa that goes missing: two lines of 45.00 * 2.501 = 112.545 sum to
    -- exactly 225.09, which floor(sum) permits, but each line floors to 112.54
    -- and neither has the headroom for the last paisa -- so the top-up loop
    -- skips both and sum(discount_amount) comes to 225.08, not the 225.09 that
    -- was asked for. The invariant "the stored shares sum to the entered
    -- discount" has to be true, not approximately true: it is the only thing
    -- that lets a receipt display one honest discount figure without storing
    -- it a second time.
    --
    -- Dart's `maxDiscount` (lib/features/cart/domain/discount_math.dart) is the
    -- same formula and must change with this one: a Dart cap above this offers
    -- a discount the database refuses, which fails an ordinary checkout.
    select coalesce(sum(floor(selling_price * quantity * 100) / 100), 0)
      into v_max
      from transactions where sale_group_id = v_group;

    if p_discount > v_max then
      raise exception 'Discount exceeds total: bill is %, discount was %',
        v_subtotal, p_discount;
    end if;

    -- FLOOR, never round. quantity is numeric(10,3), so a line subtotal can
    -- carry three decimals (45.00 * 2.501 = 112.545). Rounding a full-discount
    -- share UP to 112.55 would exceed the line's own value and trip
    -- transactions_discount_within_line, failing a perfectly legal sale.
    -- Flooring can never overshoot, so the constraint and the allocation
    -- cannot contradict each other. This also depends on v_subtotal, v_share,
    -- v_left, and v_assigned being declared as UNTYPED `numeric` above: a
    -- `numeric(12,2)` local rounds to two decimals on assignment (PL/pgSQL
    -- coerces to the declared typmod), which silently reintroduces the exact
    -- overshoot this comment says flooring prevents. The typmod is load-bearing
    -- — do not add one back.
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
        floor((v_row.selling_price * v_row.quantity - v_row.discount_amount) * 100) / 100);
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

    -- Round ONCE, here, and test/insert that same rounded value. selling_price
    -- numeric(10,2) * quantity numeric(10,3) can carry up to five decimals, so
    -- the exact remainder (e.g. 0.00499) can pass `> 0` and still round to
    -- 0.00 when customer_ledger.amount (numeric(12,2)) stores it -- tripping
    -- amount's `check (amount > 0)` on a value the guard never actually
    -- tested. Rounding before the comparison keeps the guard and the stored
    -- value the same number, so they can never disagree.
    v_subtotal := round(v_subtotal, 2);

    -- A discount equal to the whole bill is legal, which can drive the
    -- discounted total to exactly 0. customer_ledger.amount requires > 0
    -- (0008), so a zero-total ledger insert must be skipped rather than
    -- attempted -- otherwise it would fail and roll back the whole sale,
    -- including the stock decrements already applied above. A fully
    -- discounted credit sale still happens; it just creates no debt.
    if v_subtotal > 0 then
      insert into customer_ledger(shop_id, customer_id, entry_type, amount, sale_group_id)
      values (p_shop_id, p_customer_id, 'credit_sale', v_subtotal, v_group);
    end if;
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
