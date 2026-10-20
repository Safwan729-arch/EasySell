-- =============================================================================
-- 0021: links between rows must stay inside one shop
-- (spec docs/superpowers/specs/2026-10-20-security-self-assessment-design.md, L1)
-- =============================================================================
-- RLS checks only the shop_id on the row being written. Five foreign keys
-- pointed at a bare id, and a foreign-key check ignores RLS, so a signed-in
-- owner could save a row in THEIR shop that names ANOTHER shop's product,
-- customer, delivery or category. The other shop's data did not change, but
-- the link was kept: a sale row naming shop A's product stopped A from ever
-- deleting that product, or its whole shop (transactions.product_id has no
-- delete rule). Found by a live attack on 2026-10-20.
--
-- Each link now references (id, shop_id), the way product_batches has done
-- since 0011, so the database refuses a row whose target is in another shop.
-- Delete behaviour is unchanged:
--   transactions.product_id     -> products         no action (sold items are archived)
--   transactions.batch_id       -> product_batches  set null (batch_id only)
--   customer_ledger.customer_id -> customers        cascade
--   notifications.product_id    -> products         set null (product_id only)
--   products.category_id        -> categories       set null (category_id only)
-- "set null (column)" needs Postgres 15 or newer (Supabase runs 15+).
--
-- Safe to re-run. Runs as one transaction: if any existing row already links
-- across shops, it stops with a message naming the table and changes nothing.
-- =============================================================================

begin;

-- 1. Composite-key targets. id is each table's primary key, so these cannot
--    fail. products_id_shop_unique already exists (0011).
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'customers_id_shop_unique') then
    alter table customers add constraint customers_id_shop_unique unique (id, shop_id);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'categories_id_shop_unique') then
    alter table categories add constraint categories_id_shop_unique unique (id, shop_id);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'product_batches_id_shop_unique') then
    alter table product_batches add constraint product_batches_id_shop_unique unique (id, shop_id);
  end if;
end $$;

-- 2. Refuse to go on if a cross-shop link already exists, with a readable
--    message instead of a bare foreign-key error.
do $$
declare
  v_bad bigint;
begin
  select count(*) into v_bad from transactions t
    join products p on p.id = t.product_id where p.shop_id <> t.shop_id;
  if v_bad > 0 then
    raise exception '0021: % transactions rows name another shop''s product', v_bad;
  end if;
  select count(*) into v_bad from transactions t
    join product_batches b on b.id = t.batch_id where b.shop_id <> t.shop_id;
  if v_bad > 0 then
    raise exception '0021: % transactions rows name another shop''s delivery', v_bad;
  end if;
  select count(*) into v_bad from customer_ledger l
    join customers c on c.id = l.customer_id where c.shop_id <> l.shop_id;
  if v_bad > 0 then
    raise exception '0021: % customer_ledger rows name another shop''s customer', v_bad;
  end if;
  select count(*) into v_bad from notifications n
    join products p on p.id = n.product_id where p.shop_id <> n.shop_id;
  if v_bad > 0 then
    raise exception '0021: % notifications rows name another shop''s product', v_bad;
  end if;
  select count(*) into v_bad from products p
    join categories c on c.id = p.category_id where c.shop_id <> p.shop_id;
  if v_bad > 0 then
    raise exception '0021: % products rows name another shop''s category', v_bad;
  end if;
end $$;

-- 3. Swap each single-column foreign key for the same-shop one. The old
--    constraint is found by its column, not its name, so a database whose
--    constraint names differ is handled too.
create or replace function pg_temp.drop_single_fk(p_table regclass, p_column text)
returns void
language plpgsql
as $$
declare
  v_name text;
begin
  for v_name in
    select c.conname
    from pg_constraint c
    join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
    where c.conrelid = p_table
      and c.contype = 'f'
      and array_length(c.conkey, 1) = 1
      and a.attname = p_column
  loop
    execute format('alter table %s drop constraint %I', p_table, v_name);
  end loop;
end;
$$;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'transactions_product_same_shop') then
    perform pg_temp.drop_single_fk('transactions', 'product_id');
    alter table transactions add constraint transactions_product_same_shop
      foreign key (product_id, shop_id) references products (id, shop_id);
  end if;

  if not exists (select 1 from pg_constraint where conname = 'transactions_batch_same_shop') then
    perform pg_temp.drop_single_fk('transactions', 'batch_id');
    alter table transactions add constraint transactions_batch_same_shop
      foreign key (batch_id, shop_id) references product_batches (id, shop_id)
      on delete set null (batch_id);
  end if;

  if not exists (select 1 from pg_constraint where conname = 'customer_ledger_customer_same_shop') then
    perform pg_temp.drop_single_fk('customer_ledger', 'customer_id');
    alter table customer_ledger add constraint customer_ledger_customer_same_shop
      foreign key (customer_id, shop_id) references customers (id, shop_id)
      on delete cascade;
  end if;

  if not exists (select 1 from pg_constraint where conname = 'notifications_product_same_shop') then
    perform pg_temp.drop_single_fk('notifications', 'product_id');
    alter table notifications add constraint notifications_product_same_shop
      foreign key (product_id, shop_id) references products (id, shop_id)
      on delete set null (product_id);
  end if;

  if not exists (select 1 from pg_constraint where conname = 'products_category_same_shop') then
    perform pg_temp.drop_single_fk('products', 'category_id');
    alter table products add constraint products_category_same_shop
      foreign key (category_id, shop_id) references categories (id, shop_id)
      on delete set null (category_id);
  end if;
end $$;

commit;
