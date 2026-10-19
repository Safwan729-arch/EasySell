-- =============================================================================
-- 0019: money health + financing inputs
-- (spec docs/superpowers/specs/2026-10-18-money-health-financing-design.md §3)
-- =============================================================================
-- One read-only row of plain sums. Every decision (which alert fires, which
-- financing option fits) is made in Dart, where it is unit-tested.
--
-- Local days come from the phone (p_today, p_utc_offset_minutes): the
-- server's current_date is UTC, still "yesterday" in Bangladesh until 6 AM.
--
-- Payment split for cash flow: a sale is credit when payment_method says so OR
-- its sale group has a credit_sale ledger row (pre-0018 rows have no method);
-- digital when it says so; otherwise cash. A pre-0018 non-credit sale did
-- bring money in, so cash flow counts it even though History leaves it
-- unlabelled.
--
-- Overdue debt is aged FIFO: payments cover the oldest credit first, and the
-- first credit sale not fully covered is how old the debt is. "Days since last
-- payment" was rejected: a customer who settled 60 days ago and borrowed again
-- yesterday would look 60 days late.
--
-- Not security definer: RLS on transactions, customers and customer_ledger
-- applies. Needs 0018 (payment_method). Safe to re-run.
-- =============================================================================

drop function if exists get_finance_health(uuid, date, integer, integer);

create function get_finance_health(
  p_shop_id            uuid,
  p_today              date,
  p_utc_offset_minutes integer default 0,
  p_overdue_days       integer default 30
) returns table (
  cash_sales_7d       numeric,
  digital_sales_7d    numeric,
  credit_sales_7d     numeric,
  collected_7d        numeric,
  restock_spend_7d    numeric,
  sales_week          numeric,
  sales_prev_week     numeric,
  owed_now            numeric,
  owed_week_ago       numeric,
  overdue_count       integer,
  overdue_top_name    text,
  overdue_top_balance numeric,
  overdue_top_days    integer,
  sales_90d           numeric,
  profit_90d          numeric,
  digital_sales_90d   numeric,
  restock_spend_90d   numeric,
  active_weeks_12     integer,
  trading_days        integer
)
language sql
stable
as $$
  with
  -- Sales of the last ~90 local days (a day of margin for any UTC offset; the
  -- exact cut is on d below).
  sales as (
    select
      ((t.created_at at time zone 'UTC')
         + make_interval(mins => p_utc_offset_minutes))::date as d,
      t.selling_price * t.quantity - t.discount_amount as net,
      (t.selling_price - t.buying_price) * t.quantity - t.discount_amount
        as profit,
      case
        when t.payment_method = 'credit' then 'credit'
        when t.payment_method = 'digital' then 'digital'
        when t.payment_method is null and exists (
          select 1 from customer_ledger l
          where l.shop_id = p_shop_id
            and l.entry_type = 'credit_sale'
            and l.sale_group_id = t.sale_group_id
        ) then 'credit'
        else 'cash'
      end as method
    from transactions t
    where t.shop_id = p_shop_id
      and t.type = 'sale'
      and t.created_at >= (p_today - 91)::timestamptz
  ),
  restocks as (
    select
      ((t.created_at at time zone 'UTC')
         + make_interval(mins => p_utc_offset_minutes))::date as d,
      t.buying_price * t.quantity as spend
    from transactions t
    where t.shop_id = p_shop_id
      and t.type = 'restock'
      and t.created_at >= (p_today - 91)::timestamptz
  ),
  ledger as (
    select
      l.customer_id, l.entry_type, l.amount, l.created_at, l.id,
      ((l.created_at at time zone 'UTC')
         + make_interval(mins => p_utc_offset_minutes))::date as d
    from customer_ledger l
    where l.shop_id = p_shop_id
  ),
  balances as (
    select customer_id,
           sum(case when entry_type = 'credit_sale' then amount
                    else -amount end) as balance
    from ledger
    group by customer_id
  ),
  -- Running credit per customer, oldest first.
  credits as (
    select customer_id, d,
           sum(amount) over (partition by customer_id
                             order by created_at, id) as running
    from ledger
    where entry_type = 'credit_sale'
  ),
  paid as (
    select customer_id, sum(amount) as total
    from ledger
    where entry_type = 'payment'
    group by customer_id
  ),
  -- running only grows, so the rows not yet covered by payments are the
  -- newest ones and min(d) is the oldest unpaid credit.
  oldest_unpaid as (
    select c.customer_id, min(c.d) as since
    from credits c
    left join paid p on p.customer_id = c.customer_id
    where c.running > coalesce(p.total, 0)
    group by c.customer_id
  ),
  overdue as (
    select cu.name, b.balance, (p_today - o.since) as days
    from oldest_unpaid o
    join balances b on b.customer_id = o.customer_id
    join customers cu on cu.id = o.customer_id
    where b.balance > 0
      and p_today - o.since >= p_overdue_days
  ),
  top_overdue as (
    select name, balance, days
    from overdue
    order by balance desc, days desc
    limit 1
  )
  select
    (select coalesce(sum(net), 0) from sales
       where method = 'cash' and d between p_today - 6 and p_today)::numeric,
    (select coalesce(sum(net), 0) from sales
       where method = 'digital' and d between p_today - 6 and p_today)::numeric,
    (select coalesce(sum(net), 0) from sales
       where method = 'credit' and d between p_today - 6 and p_today)::numeric,
    (select coalesce(sum(amount), 0) from ledger
       where entry_type = 'payment'
         and d between p_today - 6 and p_today)::numeric,
    (select coalesce(sum(spend), 0) from restocks
       where d between p_today - 6 and p_today)::numeric,
    -- Full days only (ending yesterday): a quiet morning must not read as a
    -- falling week.
    (select coalesce(sum(net), 0) from sales
       where d between p_today - 7 and p_today - 1)::numeric,
    (select coalesce(sum(net), 0) from sales
       where d between p_today - 14 and p_today - 8)::numeric,
    (select coalesce(sum(balance), 0) from balances)::numeric,
    (select coalesce(sum(case when entry_type = 'credit_sale' then amount
                              else -amount end), 0)
       from ledger where d < p_today - 6)::numeric,
    (select count(*) from overdue)::integer,
    (select name from top_overdue),
    (select balance from top_overdue)::numeric,
    (select days from top_overdue)::integer,
    (select coalesce(sum(net), 0) from sales
       where d between p_today - 89 and p_today)::numeric,
    (select coalesce(sum(profit), 0) from sales
       where d between p_today - 89 and p_today)::numeric,
    (select coalesce(sum(net), 0) from sales
       where method = 'digital' and d between p_today - 89 and p_today)::numeric,
    (select coalesce(sum(spend), 0) from restocks
       where d between p_today - 89 and p_today)::numeric,
    (select count(distinct (p_today - d) / 7) from sales
       where d between p_today - 83 and p_today)::integer,
    -- From the first transaction, not shops.created_at: seeded or migrated
    -- history starts before the shop row. Counts today, so a first sale today
    -- is 1 day of trading.
    coalesce((
      select p_today - min(((t.created_at at time zone 'UTC')
                              + make_interval(mins => p_utc_offset_minutes))::date)
             + 1
      from transactions t
      where t.shop_id = p_shop_id
    ), 0)::integer;
$$;
