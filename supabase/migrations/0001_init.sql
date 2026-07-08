-- =============================================================================
-- 0001_init.sql — AI Shopkeeper Assistant (Member A)
-- Schema + RLS + business-logic RPCs.
--
-- Run order matters: tables → indexes → triggers → RLS → functions.
-- Apply this whole file in the Supabase Dashboard SQL Editor (see supabase/README.md).
--
-- Conventions (CLAUDE.md §4):
--   * Every table is shop-scoped; RLS restricts rows to the authenticated
--     user's shop via shops.owner_id = auth.uid().
--   * Transaction prices are SNAPSHOTS frozen at sale/restock time. Never join a
--     historical transaction back to the current product price.
--   * Stock changes go ONLY through record_sale / record_restock (atomic, locked).
-- =============================================================================

create extension if not exists pgcrypto;  -- gen_random_uuid()

-- -----------------------------------------------------------------------------
-- Shared helper: keep updated_at fresh on UPDATE.
-- -----------------------------------------------------------------------------
create or replace function set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- =============================================================================
-- TABLES
-- =============================================================================

-- users -----------------------------------------------------------------------
-- Profile row mirroring auth.users (1:1). Populated by a trigger on signup.
create table if not exists users (
  id          uuid primary key references auth.users(id) on delete cascade,
  email       text,
  full_name   text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- shops -----------------------------------------------------------------------
-- The tenancy boundary. owner_id drives every RLS policy.
create table if not exists shops (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references auth.users(id) on delete cascade,
  name        text not null,
  address     text,
  phone       text,
  currency    text not null default 'USD',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- products --------------------------------------------------------------------
-- Exact columns from CLAUDE.md §4.
create table if not exists products (
  id                 uuid primary key default gen_random_uuid(),
  shop_id            uuid not null references shops(id) on delete cascade,
  name               text not null,
  brand              text,
  variant            text,
  category           text,
  quantity           integer not null default 0 check (quantity >= 0),
  buying_price       numeric(10, 2) not null default 0,
  selling_price      numeric(10, 2) not null default 0,
  reorder_threshold  integer not null default 0,
  image_urls         text[] default '{}',
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

-- transactions ----------------------------------------------------------------
-- Exact columns from CLAUDE.md §4. buying_price/selling_price are frozen snapshots.
create table if not exists transactions (
  id             uuid primary key default gen_random_uuid(),
  shop_id        uuid not null references shops(id) on delete cascade,
  product_id     uuid not null references products(id),
  type           text not null check (type in ('sale', 'restock', 'adjustment')),
  quantity       integer not null,
  buying_price   numeric(10, 2) not null,
  selling_price  numeric(10, 2) not null,
  source         text check (source in ('voice', 'image', 'manual')),
  created_at     timestamptz not null default now()
);

-- analytics_daily -------------------------------------------------------------
-- Future optimization rollup. KEPT IN SCHEMA but NOT used for the MVP demo —
-- analytics are computed live from transactions (CLAUDE.md §5).
create table if not exists analytics_daily (
  id          uuid primary key default gen_random_uuid(),
  shop_id     uuid not null references shops(id) on delete cascade,
  day         date not null,
  revenue     numeric(12, 2) not null default 0,
  cost        numeric(12, 2) not null default 0,
  profit      numeric(12, 2) not null default 0,
  units_sold  integer not null default 0,
  created_at  timestamptz not null default now(),
  unique (shop_id, day)
);

-- notifications ---------------------------------------------------------------
-- In-app alerts (e.g. reorder). Push delivery is Member C's concern; this table
-- backs only the in-app surface.
create table if not exists notifications (
  id          uuid primary key default gen_random_uuid(),
  shop_id     uuid not null references shops(id) on delete cascade,
  product_id  uuid references products(id) on delete set null,
  type        text not null default 'reorder',
  title       text not null,
  body        text,
  is_read     boolean not null default false,
  created_at  timestamptz not null default now()
);

-- =============================================================================
-- INDEXES (analytics + lookups)
-- =============================================================================
create index if not exists idx_shops_owner on shops (owner_id);
create index if not exists idx_products_shop on products (shop_id);
create index if not exists idx_transactions_shop_created on transactions (shop_id, created_at);
create index if not exists idx_transactions_product on transactions (product_id);
create index if not exists idx_notifications_shop on notifications (shop_id, is_read);

-- =============================================================================
-- TRIGGERS
-- =============================================================================

-- Keep updated_at current on the mutable tables.
drop trigger if exists trg_users_updated_at on users;
create trigger trg_users_updated_at before update on users
  for each row execute function set_updated_at();

drop trigger if exists trg_shops_updated_at on shops;
create trigger trg_shops_updated_at before update on shops
  for each row execute function set_updated_at();

drop trigger if exists trg_products_updated_at on products;
create trigger trg_products_updated_at before update on products
  for each row execute function set_updated_at();

-- Auto-create a public.users profile row when an auth user signs up.
-- SECURITY DEFINER so it can write past RLS during the auth flow.
create or replace function handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.users (id, email, full_name)
  values (new.id, new.email, new.raw_user_meta_data ->> 'full_name')
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- =============================================================================
-- ROW LEVEL SECURITY
-- Every table shop-scoped to the authenticated user via shops.owner_id.
-- =============================================================================

alter table users           enable row level security;
alter table shops           enable row level security;
alter table products        enable row level security;
alter table transactions    enable row level security;
alter table analytics_daily enable row level security;
alter table notifications   enable row level security;

-- users: a user sees/edits only their own profile row.
drop policy if exists "users manage own profile" on users;
create policy "users manage own profile"
  on users for all
  using (id = auth.uid())
  with check (id = auth.uid());

-- shops: a user sees/edits only shops they own.
drop policy if exists "owners manage own shops" on shops;
create policy "owners manage own shops"
  on shops for all
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

-- products: scoped to the owner's shop(s).
drop policy if exists "shop members read/write own products" on products;
create policy "shop members read/write own products"
  on products for all
  using (shop_id in (select id from shops where owner_id = auth.uid()))
  with check (shop_id in (select id from shops where owner_id = auth.uid()));

-- transactions: scoped to the owner's shop(s).
drop policy if exists "shop members read/write own transactions" on transactions;
create policy "shop members read/write own transactions"
  on transactions for all
  using (shop_id in (select id from shops where owner_id = auth.uid()))
  with check (shop_id in (select id from shops where owner_id = auth.uid()));

-- analytics_daily: scoped to the owner's shop(s).
drop policy if exists "shop members read/write own analytics" on analytics_daily;
create policy "shop members read/write own analytics"
  on analytics_daily for all
  using (shop_id in (select id from shops where owner_id = auth.uid()))
  with check (shop_id in (select id from shops where owner_id = auth.uid()));

-- notifications: scoped to the owner's shop(s).
drop policy if exists "shop members read/write own notifications" on notifications;
create policy "shop members read/write own notifications"
  on notifications for all
  using (shop_id in (select id from shops where owner_id = auth.uid()))
  with check (shop_id in (select id from shops where owner_id = auth.uid()));

-- =============================================================================
-- BUSINESS-LOGIC RPCs
-- =============================================================================

-- record_sale -----------------------------------------------------------------
-- THE critical artifact. Atomic: row lock → stock check → decrement → insert.
-- A sale can never record without decrementing stock, and stock can never go
-- negative. Prices are frozen onto the transaction row at sale time.
-- (Matches CLAUDE.md §4 verbatim; adds only a positive-quantity guard.)
create or replace function record_sale(
  p_shop_id uuid,
  p_product_id uuid,
  p_quantity integer,
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

-- record_restock --------------------------------------------------------------
-- Mirror of record_sale for inventory increases. Atomic increment + 'restock'
-- transaction, prices frozen at restock time.
create or replace function record_restock(
  p_shop_id uuid,
  p_product_id uuid,
  p_quantity integer,
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

-- get_dashboard_summary -------------------------------------------------------
-- Live aggregation from transactions (CLAUDE.md §5) — does NOT read
-- analytics_daily. p_period: 'today' | 'week' | 'month' | 'year' | 'all'.
-- Revenue/cost/profit/units come from SALES in the period; inventory_value is
-- current stock (period-independent).
create or replace function get_dashboard_summary(
  p_shop_id uuid,
  p_period text default 'all'
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
begin
  v_start := case lower(coalesce(p_period, 'all'))
    when 'today' then date_trunc('day', now())
    when 'week'  then date_trunc('week', now())
    when 'month' then date_trunc('month', now())
    when 'year'  then date_trunc('year', now())
    else '-infinity'::timestamptz
  end;

  return query
  select
    coalesce(sum(t.selling_price * t.quantity), 0)::numeric as revenue,
    coalesce(sum(t.buying_price * t.quantity), 0)::numeric as cost,
    coalesce(sum((t.selling_price - t.buying_price) * t.quantity), 0)::numeric as profit,
    coalesce(sum(t.quantity), 0)::bigint as units_sold,
    (
      select coalesce(sum(p.buying_price * p.quantity), 0)::numeric
      from products p
      where p.shop_id = p_shop_id
    ) as inventory_value
  from transactions t
  where t.shop_id = p_shop_id
    and t.type = 'sale'
    and t.created_at >= v_start;
end;
$$;
