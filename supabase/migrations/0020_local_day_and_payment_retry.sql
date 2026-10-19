-- =============================================================================
-- 0020: local days on the dashboard and chart; retry-safe khata payments
-- (spec docs/superpowers/specs/2026-10-19-codebase-review-fixes-design.md)
-- =============================================================================
-- 1. get_dashboard_summary and get_sales_series cut days at UTC midnight
--    (date_trunc on now() and created_at, in the server's UTC). Sales History
--    and the Reports best sellers cut at the PHONE's midnight, so the same
--    screen could disagree with itself: in Bangladesh a sale at 3 AM counted
--    for yesterday on the chart, and in a UTC-6 market every sale after 6 PM
--    counted for tomorrow. Both now take p_utc_offset_minutes, the phone's
--    offset, the way get_restock_speeds (0017) and get_finance_health (0019)
--    already do. Default 0 keeps the old UTC behaviour for an old app build.
--
-- 2. record_payment was not retry-safe: a lost reply and a second tap
--    recorded the payment twice and wiped debt the customer still owed. The
--    phone now mints p_payment_id and re-sends it on a retry; the ledger row
--    is inserted with that id, so a repeat returns it and changes nothing
--    (the record_restock method from 0011). The amount is also rounded to
--    the ledger's 2 decimals BEFORE the > 0 check, so 0.004 is refused with a
--    readable message instead of tripping the column's check constraint.
--
-- New parameters are new signatures: every old one is dropped first so
-- PostgREST never sees two overloads (the trap noted in 0006/0009/0010).
-- The app build that sends these parameters needs this migration. Run after
-- 0019. Safe to re-run.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- get_dashboard_summary
-- ---------------------------------------------------------------------------
drop function if exists get_dashboard_summary(uuid, text);
drop function if exists get_dashboard_summary(uuid, text, date);
drop function if exists get_dashboard_summary(uuid, text, date, integer);

create function get_dashboard_summary(
  p_shop_id            uuid,
  p_period             text default 'all',
  p_day                date default null,
  p_utc_offset_minutes integer default 0
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
  v_offset interval := make_interval(mins => coalesce(p_utc_offset_minutes, 0));
  -- The phone's wall clock. Truncated as a plain timestamp, then shifted
  -- back to the UTC instant it stands for.
  v_local  timestamp := (now() at time zone 'UTC') + v_offset;
  v_start  timestamptz;
  v_end    timestamptz;
begin
  if p_day is not null then
    v_start := (p_day::timestamp - v_offset) at time zone 'UTC';
    v_end   := ((p_day + 1)::timestamp - v_offset) at time zone 'UTC';
  else
    v_start := case lower(coalesce(p_period, 'all'))
      when 'today' then (date_trunc('day', v_local) - v_offset) at time zone 'UTC'
      when 'week'  then (date_trunc('week', v_local) - v_offset) at time zone 'UTC'
      when 'month' then (date_trunc('month', v_local) - v_offset) at time zone 'UTC'
      when 'year'  then (date_trunc('year', v_local) - v_offset) at time zone 'UTC'
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

-- ---------------------------------------------------------------------------
-- get_sales_series
-- ---------------------------------------------------------------------------
-- Buckets are local days/weeks/months. Each bucket is returned as the UTC
-- instant of its local start, so the app's toLocal() lands on local midnight
-- of the right date.
drop function if exists get_sales_series(uuid, text, integer);
drop function if exists get_sales_series(uuid, text, integer, integer);

create function get_sales_series(
  p_shop_id            uuid,
  p_bucket             text default 'day',
  p_points             integer default 7,
  p_utc_offset_minutes integer default 0
) returns table (
  bucket   timestamptz,
  revenue  numeric,
  profit   numeric
)
language plpgsql
stable
as $$
declare
  v_offset   interval := make_interval(mins => coalesce(p_utc_offset_minutes, 0));
  v_local    timestamp := (now() at time zone 'UTC') + v_offset;
  v_trunc    text;
  v_interval interval;
  v_start    timestamp;  -- local
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
  v_start := date_trunc(v_trunc, v_local) - (v_interval * (greatest(p_points, 1) - 1));

  return query
  with series as (
    select generate_series(v_start, date_trunc(v_trunc, v_local), v_interval) as b
  ),
  sales as (
    select date_trunc(v_trunc, (t.created_at at time zone 'UTC') + v_offset) as b,
           sum(t.selling_price * t.quantity - t.discount_amount) as revenue,
           sum((t.selling_price - t.buying_price) * t.quantity - t.discount_amount) as profit
    from transactions t
    where t.shop_id = p_shop_id
      and t.type = 'sale'
      and t.created_at >= (v_start - v_offset) at time zone 'UTC'
    group by 1
  )
  select ((s.b - v_offset) at time zone 'UTC') as bucket,
         coalesce(sa.revenue, 0)::numeric as revenue,
         coalesce(sa.profit, 0)::numeric as profit
  from series s
  left join sales sa on sa.b = s.b
  order by s.b;
end;
$$;

-- ---------------------------------------------------------------------------
-- record_payment
-- ---------------------------------------------------------------------------
drop function if exists record_payment(uuid, uuid, numeric, text);
drop function if exists record_payment(uuid, uuid, numeric, text, uuid);

create function record_payment(
  p_shop_id     uuid,
  p_customer_id uuid,
  p_amount      numeric,
  p_note        text default null,
  p_payment_id  uuid default null  -- minted by the phone; null => fresh id
) returns customer_ledger
language plpgsql
as $$
declare
  v_id      uuid := coalesce(p_payment_id, gen_random_uuid());
  v_amount  numeric(12, 2) := round(p_amount, 2);
  v_balance numeric(12, 2);
  v_row     customer_ledger;
begin
  -- Serialise calls with the same id so two overlapping retries cannot both
  -- miss the row below and both insert.
  perform pg_advisory_xact_lock(hashtextextended(v_id::text, 0));

  select * into v_row from customer_ledger
    where id = v_id and shop_id = p_shop_id;
  if found then
    return v_row;
  end if;

  if v_amount is null or v_amount <= 0 then
    raise exception 'Payment must be greater than zero';
  end if;

  -- Lock the customer row so two different payments can't both pass the
  -- overpayment check against a stale balance.
  perform 1 from customers
    where id = p_customer_id and shop_id = p_shop_id
    for update;
  if not found then
    raise exception 'Customer not found';
  end if;

  select coalesce(sum(case when entry_type = 'credit_sale' then amount
                           else -amount end), 0)
    into v_balance
    from customer_ledger
    where customer_id = p_customer_id and shop_id = p_shop_id;

  if v_amount > v_balance then
    raise exception 'Payment exceeds balance: owes %', v_balance;
  end if;

  insert into customer_ledger(id, shop_id, customer_id, entry_type, amount, note)
  values (v_id, p_shop_id, p_customer_id, 'payment', v_amount, p_note)
  returning * into v_row;

  return v_row;
end;
$$;
