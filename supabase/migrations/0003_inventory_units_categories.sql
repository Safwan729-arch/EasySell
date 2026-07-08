-- =============================================================================
-- 0003_inventory_units_categories.sql — Adaptive units + reusable categories
--
-- Run AFTER 0001_init.sql and 0002_analytics.sql (Dashboard SQL Editor → paste
-- → Run, or `supabase db push`). Idempotent: safe to re-run.
--
-- What this migration does (CLAUDE.md §4 conventions kept throughout):
--   1. Products gain a unit model: unit_type (piece/weight/volume) + unit
--      (pcs/kg/g/litre/ml). quantity becomes decimal so it can hold 12 pcs OR
--      2.5 kg. buying_price/selling_price are now understood as PER-UNIT prices.
--   2. A shop-scoped `categories` table replaces the free-text product.category;
--      products gain category_id (ON DELETE SET NULL — deleting a category
--      never deletes products, they just become uncategorized).
--   3. upsert_category(): normalized find-or-create, dedup enforced by a DB
--      unique constraint (not just the app).
--   4. record_sale / record_restock recreated to take a numeric quantity. The
--      atomic lock → check → decrement/increment → insert logic and price
--      freezing are UNCHANGED; only the numeric type widened.
--   5. New shops seeded with a starter category set (trigger); existing shops
--      backfilled once.
--   6. products + categories added to the supabase_realtime publication so the
--      app's live `.stream()` lists update the moment a row is inserted/changed.
--
-- DECISIONS THAT GO BEYOND THE LITERAL TASK LIST (flagged for review):
--   * transactions.quantity is widened to numeric(10,3) too — record_sale writes
--     the decimal quantity onto the transaction row, so an integer column would
--     reject a 2.5 kg sale. Required for correctness.
--   * products.reorder_threshold is widened to numeric(10,3) — the threshold is
--     expressed in the same unit as stock, which is decimal for weight/volume.
--   * The old products.category (free text) column is KEPT but deprecated. Its
--     data is migrated into `categories` and linked via category_id below. Drop
--     it in a later migration once you've verified nothing reads it.
--   * get_dashboard_summary is left untouched. Its units_sold still casts the
--     summed quantity to bigint (it will round decimals). "Units sold" already
--     mixes unit types (pcs + kg) and is a known analytics limitation to revisit
--     separately — out of scope here.
-- =============================================================================

-- =============================================================================
-- 1. PRODUCTS — unit model + decimal quantities
-- =============================================================================

-- Adaptive unit model. Defaults keep every existing row valid as 'piece'/'pcs'.
alter table products
  add column if not exists unit_type text not null default 'piece';
alter table products
  add column if not exists unit text not null default 'pcs';

-- Constrain the new columns (added separately so re-runs don't choke on a dup).
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'products_unit_type_check'
  ) then
    alter table products add constraint products_unit_type_check
      check (unit_type in ('piece', 'weight', 'volume'));
  end if;
  if not exists (
    select 1 from pg_constraint where conname = 'products_unit_check'
  ) then
    alter table products add constraint products_unit_check
      check (unit in ('pcs', 'kg', 'g', 'litre', 'ml'));
  end if;
end $$;

-- quantity: integer → numeric(10,3) so it holds both 12 (pcs) and 2.500 (kg).
-- The >= 0 check is preserved (it's a column check that survives the type change).
alter table products
  alter column quantity type numeric(10, 3) using quantity::numeric(10, 3);
alter table products
  alter column quantity set default 0;

-- reorder_threshold: same unit as stock, so it must allow decimals too.
alter table products
  alter column reorder_threshold type numeric(10, 3)
    using reorder_threshold::numeric(10, 3);
alter table products
  alter column reorder_threshold set default 0;

-- brand / variant are already nullable in 0001_init.sql (no NOT NULL). Confirmed;
-- nothing to change. They only apply to 'piece' items at the UI layer.

-- =============================================================================
-- 2. CATEGORIES — shop-scoped, reusable, dedup-enforced
--    NOTE: table MUST exist before products.category_id references it.
-- =============================================================================

create table if not exists categories (
  id              uuid primary key default gen_random_uuid(),
  shop_id         uuid not null references shops(id) on delete cascade,
  name            text not null,
  name_normalized text not null,
  created_at      timestamptz not null default now(),
  unique (shop_id, name_normalized)
);

create index if not exists idx_categories_shop on categories (shop_id);

-- Deleting a category leaves its products in place, just uncategorized.
alter table products
  add column if not exists category_id uuid references categories(id) on delete set null;

create index if not exists idx_products_category on products (category_id);

-- =============================================================================
-- 3. ROW LEVEL SECURITY (categories) — same shop-scoped pattern as 0001.
-- =============================================================================

alter table categories enable row level security;

drop policy if exists "shop members read/write own categories" on categories;
create policy "shop members read/write own categories"
  on categories for all
  using (shop_id in (select id from shops where owner_id = auth.uid()))
  with check (shop_id in (select id from shops where owner_id = auth.uid()));

-- =============================================================================
-- 4. upsert_category — normalized find-or-create (race-safe, no duplicates)
--
-- Normalize: trim, collapse internal whitespace, lowercase. The unique
-- constraint on (shop_id, name_normalized) is the real guard; ON CONFLICT makes
-- the call return the existing row instead of erroring. The existing display
-- name is preserved (DO UPDATE is a no-op that just enables RETURNING).
-- =============================================================================

create or replace function upsert_category(
  p_shop_id uuid,
  p_name text
) returns categories
language plpgsql
as $$
declare
  v_display text;
  v_norm    text;
  v_cat     categories;
begin
  -- Collapse runs of whitespace to a single space, then trim.
  v_display := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
  v_norm    := lower(v_display);

  if v_norm = '' then
    raise exception 'Category name cannot be empty';
  end if;

  insert into categories (shop_id, name, name_normalized)
  values (p_shop_id, v_display, v_norm)
  on conflict (shop_id, name_normalized)
    do update set name = categories.name  -- no-op; keeps existing row + name
  returning * into v_cat;

  return v_cat;
end;
$$;

-- =============================================================================
-- 5. record_sale / record_restock — recreated for numeric quantity
--
-- A signature change (integer → numeric) can't be done with CREATE OR REPLACE
-- (it would create a second overload), so the old definitions are dropped first.
-- The atomic lock/check/decrement/insert logic and price freezing are identical
-- to 0001_init.sql — only p_quantity's type widened. Stock still can't go
-- negative: the < check works for decimals just as it did for integers.
-- =============================================================================

drop function if exists record_sale(uuid, uuid, integer, text);
drop function if exists record_restock(uuid, uuid, integer, text);

create or replace function record_sale(
  p_shop_id uuid,
  p_product_id uuid,
  p_quantity numeric,
  p_source text default 'manual'
) returns transactions
language plpgsql
as $$
declare
  v_product products;
  v_txn transactions;
begin
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'Quantity must be greater than zero';
  end if;

  -- Lock the row to prevent concurrent oversell.
  select * into v_product from products
    where id = p_product_id and shop_id = p_shop_id
    for update;

  if v_product is null then
    raise exception 'Product not found';
  end if;

  if v_product.quantity < p_quantity then
    raise exception 'Insufficient stock: have %, need %', v_product.quantity, p_quantity;
  end if;

  update products set quantity = quantity - p_quantity, updated_at = now()
    where id = p_product_id;

  insert into transactions(shop_id, product_id, type, quantity, buying_price, selling_price, source)
  values (p_shop_id, p_product_id, 'sale', p_quantity,
          v_product.buying_price, v_product.selling_price, p_source)
  returning * into v_txn;

  return v_txn;
end;
$$;

create or replace function record_restock(
  p_shop_id uuid,
  p_product_id uuid,
  p_quantity numeric,
  p_source text default 'manual'
) returns transactions
language plpgsql
as $$
declare
  v_product products;
  v_txn transactions;
begin
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

  insert into transactions(shop_id, product_id, type, quantity, buying_price, selling_price, source)
  values (p_shop_id, p_product_id, 'restock', p_quantity,
          v_product.buying_price, v_product.selling_price, p_source)
  returning * into v_txn;

  return v_txn;
end;
$$;

-- transactions.quantity widened to match (record_sale writes decimals onto it).
alter table transactions
  alter column quantity type numeric(10, 3) using quantity::numeric(10, 3);

-- =============================================================================
-- 6. SEED DEFAULT CATEGORIES
--
-- New shops: a trigger seeds a starter set (SECURITY DEFINER so it writes past
-- RLS during shop creation, matching the handle_new_user pattern in 0001).
-- These are ordinary rows — the shopkeeper can rename or delete them.
-- =============================================================================

create or replace function seed_default_categories()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into categories (shop_id, name, name_normalized)
  select new.id, c.name, lower(c.name)
  from (values
    ('Rice & grains'),
    ('Cooking oil'),
    ('Pulses/lentils'),
    ('Vegetables'),
    ('Spices'),
    ('Cleaning & detergent'),
    ('Personal care'),
    ('Beverages'),
    ('Snacks'),
    ('Dairy')
  ) as c(name)
  on conflict (shop_id, name_normalized) do nothing;
  return new;
end;
$$;

drop trigger if exists trg_shops_seed_categories on shops;
create trigger trg_shops_seed_categories
  after insert on shops
  for each row execute function seed_default_categories();

-- Backfill: give every EXISTING shop the same starter set (idempotent).
insert into categories (shop_id, name, name_normalized)
select s.id, c.name, lower(c.name)
from shops s
cross join (values
  ('Rice & grains'),
  ('Cooking oil'),
  ('Pulses/lentils'),
  ('Vegetables'),
  ('Spices'),
  ('Cleaning & detergent'),
  ('Personal care'),
  ('Beverages'),
  ('Snacks'),
  ('Dairy')
) as c(name)
on conflict (shop_id, name_normalized) do nothing;

-- =============================================================================
-- 7. MIGRATE EXISTING FREE-TEXT CATEGORIES → categories + category_id
--    (The old products.category column is kept but deprecated; see header.)
-- =============================================================================

-- 7a. Create a category row for each distinct existing free-text value.
insert into categories (shop_id, name, name_normalized)
select distinct
  p.shop_id,
  btrim(regexp_replace(p.category, '\s+', ' ', 'g')),
  lower(btrim(regexp_replace(p.category, '\s+', ' ', 'g')))
from products p
where p.category is not null
  and btrim(p.category) <> ''
on conflict (shop_id, name_normalized) do nothing;

-- 7b. Link products to the matching category row.
update products p
set category_id = c.id
from categories c
where c.shop_id = p.shop_id
  and c.name_normalized = lower(btrim(regexp_replace(p.category, '\s+', ' ', 'g')))
  and p.category is not null
  and btrim(p.category) <> ''
  and p.category_id is null;

-- =============================================================================
-- 8. REALTIME — deliver live inserts/updates/deletes to the app's `.stream()`
--
-- The Flutter inventory list (and the M4 category picker) subscribe via Supabase
-- Realtime. A table only emits change events once it's in the `supabase_realtime`
-- publication; without this, `.stream()` returns the initial snapshot but never
-- pushes later inserts — so a product created while the list is open won't show
-- until the screen re-subscribes. (RLS still applies to realtime, so each shop
-- only receives its own rows.)
-- =============================================================================
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'products'
  ) then
    alter publication supabase_realtime add table products;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'categories'
  ) then
    alter publication supabase_realtime add table categories;
  end if;
end $$;
