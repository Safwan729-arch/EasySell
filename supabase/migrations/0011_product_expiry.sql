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
