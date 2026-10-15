-- =============================================================================
-- 0017: restock planner speeds (spec 2026-10-15-restock-planner-design.md §3)
-- =============================================================================
-- Per product: a units-per-day speed over the 28 full LOCAL days ending
-- yesterday, weeks weighted 0.4/0.3/0.2/0.1, counting only days the product
-- could be sold (start-of-day stock > 0, or a sale that day). Days when the
-- shelf was empty are skipped: counting them made a product that sold out look
-- slow, which is the exact mistake the planner exists to stop.
--
-- Start-of-day stock is rebuilt BACKWARDS from products.quantity:
--   stock_at_start(d) = quantity - sum(net change of every row on day >= d)
-- with restock +q, sale -q, adjustment -q (every adjustment is a removal:
-- 0011/0013/0014/0015). Stock edited by hand before commit 310bd5d left no row,
-- so such products' early history is off by the edit; accepted, it ages out.
-- Days before the product's created_at never count: opening stock has no
-- restock row, so the rebuild would show it on shelves before it existed.
--
-- p_today and p_utc_offset_minutes come from the phone: the server's
-- current_date is UTC, still "yesterday" in Bangladesh until 6 AM.
--
-- Read-only, not security definer: RLS on products/transactions applies.
-- Run after 0016. Safe to re-run.
-- =============================================================================

drop function if exists get_restock_speeds(uuid, date, integer);

create function get_restock_speeds(
  p_shop_id            uuid,
  p_today              date,
  p_utc_offset_minutes integer default 0
) returns table (product_id uuid, speed numeric, week0_rate numeric)
language sql
stable
as $$
  with
  days as (
    select generate_series((p_today - 28)::timestamp,
                           (p_today - 1)::timestamp,
                           interval '1 day')::date as d
  ),
  prod as (
    select p.id, p.quantity,
           ((p.created_at at time zone 'UTC')
              + make_interval(mins => p_utc_offset_minutes))::date as created_day
    from products p
    where p.shop_id = p_shop_id
      and not coalesce(p.is_archived, false)
  ),
  txn as (
    select x.product_id, x.d,
           sum(x.net)  as net,
           sum(x.sold) as sold
    from (
      select t.product_id,
             ((t.created_at at time zone 'UTC')
                + make_interval(mins => p_utc_offset_minutes))::date as d,
             case t.type when 'restock' then t.quantity else -t.quantity end
               as net,
             case t.type when 'sale' then t.quantity else 0 end as sold
      from transactions t
      where t.shop_id = p_shop_id
    ) x
    where x.d >= p_today - 28
    group by x.product_id, x.d
  ),
  grid as (
    select p.id as product_id,
           dy.d,
           p.created_day,
           coalesce(tx.sold, 0) as sold,
           p.quantity - coalesce((
             select sum(t2.net) from txn t2
             where t2.product_id = p.id and t2.d >= dy.d
           ), 0) as start_stock
    from prod p
    cross join days dy
    left join txn tx on tx.product_id = p.id and tx.d = dy.d
  ),
  weekly as (
    select g.product_id,
           (p_today - 1 - g.d) / 7 as w,
           sum(g.sold) as units,
           count(*) filter (
             where g.d >= g.created_day
               and (g.start_stock > 0 or g.sold > 0)
           ) as in_days
    from grid g
    group by g.product_id, (p_today - 1 - g.d) / 7
  ),
  rates as (
    select wk.product_id, wk.w,
           wk.units::numeric / wk.in_days as rate,
           case wk.w when 0 then 0.4 when 1 then 0.3 when 2 then 0.2 else 0.1
           end as wt
    from weekly wk
    where wk.in_days > 0
  )
  select r.product_id,
         sum(r.rate * r.wt) / sum(r.wt)        as speed,
         max(r.rate) filter (where r.w = 0)    as week0_rate
  from rates r
  group by r.product_id
  having sum(r.rate * r.wt) > 0;
$$;
-- -----------------------------------------------------------------------------
-- VERIFY (run by hand; replace the email and product name):
--
-- select * from get_restock_speeds(
--   (select s.id from shops s join auth.users u on u.id = s.owner_id
--     where u.email = 'safwansaka55555@gmail.com'),
--   current_date, 360);
--
-- Hand check for one product -- each day's sold units and start-of-day stock:
-- with p as (select id, quantity from products where name = 'Pepsi'),
-- t as (select ((created_at at time zone 'UTC') + interval '360 minutes')::date d,
--              case type when 'restock' then quantity else -quantity end net,
--              case type when 'sale' then quantity else 0 end sold
--       from transactions where product_id = (select id from p))
-- select g.d,
--        coalesce((select sum(sold) from t where t.d = g.d), 0) as sold,
--        (select quantity from p)
--          - coalesce((select sum(net) from t where t.d >= g.d), 0) as start_stock
-- from generate_series(current_date - 28, current_date - 1, interval '1 day') g(d)
-- order by g.d;
-- -----------------------------------------------------------------------------
