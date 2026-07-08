-- =============================================================================
-- 0002_analytics.sql — time-series for dashboard/analytics charts.
-- Run AFTER 0001_init.sql (Dashboard SQL Editor → paste → Run). Idempotent.
--
-- Keeps aggregation in the database (CLAUDE.md §5): Flutter only renders the
-- returned rows. Aggregates SALES only, live from `transactions`.
-- =============================================================================

-- get_sales_series ------------------------------------------------------------
-- Returns the last p_points buckets (zero-filled) of revenue + profit for a
-- shop. p_bucket: 'day' | 'week' | 'month'.
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
           sum(selling_price * quantity) as revenue,
           sum((selling_price - buying_price) * quantity) as profit
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
