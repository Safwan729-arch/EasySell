-- =============================================================================
-- 0006_dashboard_summary_day.sql — optional single-day window for the summary.
-- Run AFTER 0005_product_archive.sql (Dashboard SQL Editor → paste → Run).
-- Idempotent (safe to re-run).
--
-- Adds p_day: when non-null, get_dashboard_summary returns totals for that single
-- calendar day [p_day, p_day + 1 day) and IGNORES p_period. When p_day is null,
-- behaviour is unchanged from 0005. Aggregation stays in the database (CLAUDE.md
-- §5). inventory_value remains a current-stock figure (unchanged).
--
-- IMPORTANT (overload fix): 0005 defined get_dashboard_summary(uuid, text). Adding
-- p_day changes the argument list to (uuid, text, date), so `create or replace`
-- would NOT replace the old function — Postgres keys functions by name + argument
-- TYPES, so it would leave BOTH overloads in place. A 2-argument call (the Home
-- dashboard's Today/Week/Month path) then matches both and PostgREST can no longer
-- resolve which to run, breaking the dashboard summary. We therefore DROP every
-- prior overload first so exactly ONE get_dashboard_summary exists afterwards.
--
-- Timezone note: the day window is interpreted in the DB session timezone, the
-- same looseness the existing today/week/month truncation already has. Accepted
-- for the MVP.
-- =============================================================================

-- Remove any earlier signatures so re-running leaves a single, unambiguous fn.
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
    and t.created_at >= v_start
    and t.created_at < v_end;
end;
$$;
