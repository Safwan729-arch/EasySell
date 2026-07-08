-- =============================================================================
-- 0005_product_archive.sql — soft-delete (archive) for products
--
-- Run AFTER 0004 (Dashboard SQL Editor → paste → Run, or `supabase db push`).
-- Idempotent.
--
-- Products can have transaction history (transactions.product_id references
-- products(id) with NO cascade — by design, so frozen sale-time prices and
-- historical profit/analytics are never destroyed). A hard DELETE therefore
-- fails with a foreign-key violation once a product has ever sold or restocked.
--
-- Instead of deleting, the app ARCHIVES: products.is_archived = true. Archived
-- products disappear from inventory, dashboard, analytics and pickers, but their
-- rows (and the transactions pointing at them) survive intact. Reversible.
-- =============================================================================

alter table products
  add column if not exists is_archived boolean not null default false;

-- Active-product lookups are the hot path; index only the live rows.
create index if not exists idx_products_active
  on products (shop_id) where not is_archived;

-- get_dashboard_summary: inventory_value must ignore archived products.
-- (Sales aggregates read transactions, which are unaffected by archiving.)
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
        and not p.is_archived
    ) as inventory_value
  from transactions t
  where t.shop_id = p_shop_id
    and t.type = 'sale'
    and t.created_at >= v_start;
end;
$$;
