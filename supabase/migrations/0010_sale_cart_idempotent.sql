-- =============================================================================
-- 0010_sale_cart_idempotent.sql — a retried checkout cannot record a sale twice.
-- Run AFTER 0009_cart_discount.sql (Dashboard SQL Editor -> paste -> Run).
-- Idempotent (safe to re-run).
--
-- Before this, record_sale_cart minted the sale id itself. On weak signal the
-- sale could commit and the reply be lost; the app showed an error, kept the
-- cart, and the user's retry recorded the same sale again (stock decremented
-- twice, revenue and any khata debt doubled).
--
-- Now the phone sends the id (p_sale_group_id) and re-sends the same id on a
-- retry. A second call with an id that already has rows returns those rows and
-- changes nothing. The check runs BEFORE the stock check on purpose: the first
-- call already took the stock, so a replay that re-checked stock could fail
-- with "Insufficient stock" for a sale that actually went through.
--
-- p_sale_group_id defaults to null => a fresh id, the 0009 behaviour, so an
-- app build from before this migration keeps working unchanged.
--
-- OVERLOAD WARNING (same trap as 0006 and 0009): adding a parameter changes the
-- argument list, so every prior signature is dropped first or PostgREST could
-- no longer pick one -- silently breaking checkout.
-- =============================================================================

drop function if exists record_sale_cart(uuid, jsonb, text);
drop function if exists record_sale_cart(uuid, jsonb, text, uuid);
drop function if exists record_sale_cart(uuid, jsonb, text, uuid, numeric);
drop function if exists record_sale_cart(uuid, jsonb, text, uuid, numeric, uuid);

create function record_sale_cart(
  p_shop_id uuid,
  p_items jsonb,              -- [{"product_id": "...", "quantity": 2}, ...]
  p_source text default 'manual',
  p_customer_id uuid default null,
  p_discount numeric default 0,
  p_sale_group_id uuid default null  -- minted by the phone; null => fresh id
) returns setof transactions
language plpgsql
as $$
declare
  v_group    uuid := coalesce(p_sale_group_id, gen_random_uuid());
  v_item     record;
  v_product  products;
  v_subtotal numeric;
  v_max      numeric;
  v_share    numeric;
  v_assigned numeric := 0;
  v_left     numeric;
  v_row      transactions;
begin
  -- -------------------------------------------------------------------------
  -- Replay: this id was already recorded, so hand back what was recorded.
  -- -------------------------------------------------------------------------
  -- The lock makes two calls with the same id run one after the other. Without
  -- it, two overlapping calls could both see no rows and both insert. It is
  -- held until this transaction ends, so the second call waits for the first
  -- to commit and then finds its rows.
  perform pg_advisory_xact_lock(hashtextextended(v_group::text, 0));

  if exists (
    select 1 from transactions
      where shop_id = p_shop_id and sale_group_id = v_group
  ) then
    return query select * from transactions
      where shop_id = p_shop_id and sale_group_id = v_group;
    return;
  end if;

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
      -- Report v_max, NOT v_subtotal. The raw subtotal can carry five decimals
      -- (numeric(10,2) price x numeric(10,3) quantity) and can sit a fraction
      -- ABOVE the largest discount that is actually placeable, so quoting it
      -- produced messages like "bill is 225.09000, discount was 225.09" that
      -- read as self-contradictory. v_max is the number the comparison used.
      raise exception 'Discount exceeds total: most you can take off is %, asked for %',
        v_max, p_discount;
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
