-- =============================================================================
-- 0008_customer_credit.sql — customer credit ("khata").
-- Run AFTER 0007_sale_cart.sql (Dashboard SQL Editor -> paste -> Run).
-- Idempotent (safe to re-run).
--
-- Adds a customer list and an APPEND-ONLY ledger. A customer's balance is
-- computed live as sum(credit_sale) - sum(payment); no balance is stored, so it
-- can never drift (same philosophy as live analytics, CLAUDE.md §5).
--
-- record_sale_cart gains an optional p_customer_id: null => today's cash-sale
-- behaviour, unchanged; non-null => the same atomic checkout PLUS one
-- 'credit_sale' ledger row for the receipt total, all in one transaction.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- TABLES
-- ---------------------------------------------------------------------------
create table if not exists customers (
  id          uuid primary key default gen_random_uuid(),
  shop_id     uuid not null references shops(id) on delete cascade,
  name        text not null,
  phone       text not null,
  note        text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table if not exists customer_ledger (
  id             uuid primary key default gen_random_uuid(),
  shop_id        uuid not null references shops(id) on delete cascade,
  customer_id    uuid not null references customers(id) on delete cascade,
  entry_type     text not null check (entry_type in ('credit_sale', 'payment')),
  amount         numeric(12, 2) not null check (amount > 0),
  sale_group_id  uuid,
  note           text,
  created_at     timestamptz not null default now()
);

create index if not exists idx_customers_shop on customers (shop_id);
create index if not exists idx_customer_ledger_customer on customer_ledger (customer_id, created_at desc);
create index if not exists idx_customer_ledger_shop on customer_ledger (shop_id);

-- keep updated_at fresh on customers
drop trigger if exists trg_customers_updated_at on customers;
create trigger trg_customers_updated_at before update on customers
  for each row execute function set_updated_at();

-- ---------------------------------------------------------------------------
-- ROW LEVEL SECURITY (shop-scoped, same shape as 0001)
-- ---------------------------------------------------------------------------
alter table customers        enable row level security;
alter table customer_ledger  enable row level security;

drop policy if exists "shop members read/write own customers" on customers;
create policy "shop members read/write own customers"
  on customers for all
  using (shop_id in (select id from shops where owner_id = auth.uid()))
  with check (shop_id in (select id from shops where owner_id = auth.uid()));

drop policy if exists "shop members read/write own customer_ledger" on customer_ledger;
create policy "shop members read/write own customer_ledger"
  on customer_ledger for all
  using (shop_id in (select id from shops where owner_id = auth.uid()))
  with check (shop_id in (select id from shops where owner_id = auth.uid()));

-- ---------------------------------------------------------------------------
-- record_sale_cart — extended with optional p_customer_id (credit sale).
-- p_customer_id null => identical to 0007 behaviour.
-- ---------------------------------------------------------------------------
drop function if exists record_sale_cart(uuid, jsonb, text);
drop function if exists record_sale_cart(uuid, jsonb, text, uuid);

create function record_sale_cart(
  p_shop_id uuid,
  p_items jsonb,              -- [{"product_id": "...", "quantity": 2}, ...]
  p_source text default 'manual',
  p_customer_id uuid default null
) returns setof transactions
language plpgsql
as $$
declare
  v_group uuid := gen_random_uuid();
  v_item record;
  v_product products;
  v_total numeric(12, 2);
begin
  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'Cart is empty';
  end if;

  -- A credit sale needs a valid customer in THIS shop before we touch stock.
  if p_customer_id is not null then
    perform 1 from customers
      where id = p_customer_id and shop_id = p_shop_id;
    if not found then
      raise exception 'Customer not found';
    end if;
  end if;

  for v_item in
    select * from jsonb_to_recordset(p_items) as x(product_id uuid, quantity numeric)
  loop
    if v_item.quantity is null or v_item.quantity <= 0 then
      raise exception 'Quantity must be greater than zero';
    end if;

    select * into v_product from products
      where id = v_item.product_id and shop_id = p_shop_id
      for update;

    if v_product is null then
      raise exception 'Product not found';
    end if;

    if v_product.quantity < v_item.quantity then
      raise exception 'Insufficient stock for %: have %, need %',
        v_product.name, v_product.quantity, v_item.quantity;
    end if;

    update products set quantity = quantity - v_item.quantity, updated_at = now()
      where id = v_item.product_id;

    insert into transactions(shop_id, product_id, type, quantity, buying_price,
                              selling_price, source, sale_group_id)
    values (p_shop_id, v_item.product_id, 'sale', v_item.quantity,
            v_product.buying_price, v_product.selling_price, p_source, v_group);
  end loop;

  -- On credit: record the debt for the receipt total in the same transaction,
  -- so stock and debt can never disagree.
  if p_customer_id is not null then
    select coalesce(sum(selling_price * quantity), 0) into v_total
      from transactions where sale_group_id = v_group;

    insert into customer_ledger(shop_id, customer_id, entry_type, amount, sale_group_id)
    values (p_shop_id, p_customer_id, 'credit_sale', v_total, v_group);
  end if;

  return query select * from transactions where sale_group_id = v_group;
end;
$$;

-- ---------------------------------------------------------------------------
-- record_payment — append a 'payment' ledger row. Rejects <=0 and overpayment.
-- ---------------------------------------------------------------------------
create or replace function record_payment(
  p_shop_id uuid,
  p_customer_id uuid,
  p_amount numeric,
  p_note text default null
) returns customer_ledger
language plpgsql
as $$
declare
  v_balance numeric(12, 2);
  v_row customer_ledger;
begin
  if p_amount is null or p_amount <= 0 then
    raise exception 'Payment must be greater than zero';
  end if;

  -- Lock the customer row so two concurrent payments can't both pass the
  -- overpayment check against a stale balance (mirrors record_sale's row lock).
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
    where customer_id = p_customer_id;

  if p_amount > v_balance then
    raise exception 'Payment exceeds balance: owes %', v_balance;
  end if;

  insert into customer_ledger(shop_id, customer_id, entry_type, amount, note)
  values (p_shop_id, p_customer_id, 'payment', p_amount, p_note)
  returning * into v_row;

  return v_row;
end;
$$;

-- ---------------------------------------------------------------------------
-- get_customer_balances — every customer + live balance + last activity.
-- ---------------------------------------------------------------------------
create or replace function get_customer_balances(p_shop_id uuid)
returns table (
  id uuid, name text, phone text, note text,
  balance numeric, last_activity_at timestamptz
)
language sql
as $$
  select c.id, c.name, c.phone, c.note,
    coalesce(sum(case when l.entry_type = 'credit_sale' then l.amount
                      else -l.amount end), 0)::numeric as balance,
    max(l.created_at) as last_activity_at
  from customers c
  left join customer_ledger l on l.customer_id = c.id
  where c.shop_id = p_shop_id
  group by c.id, c.name, c.phone, c.note
  order by balance desc, c.name asc;
$$;

-- ---------------------------------------------------------------------------
-- get_receivables_summary — total owed + debtor count (dashboard card).
-- ---------------------------------------------------------------------------
create or replace function get_receivables_summary(p_shop_id uuid)
returns table (total_owed numeric, debtor_count bigint)
language sql
as $$
  select
    coalesce(sum(b.balance), 0)::numeric as total_owed,
    count(*)::bigint as debtor_count
  from get_customer_balances(p_shop_id) b
  where b.balance > 0;
$$;

-- ---------------------------------------------------------------------------
-- delete_customer — only when settled (balance = 0). Ledger cascades.
-- ---------------------------------------------------------------------------
create or replace function delete_customer(p_shop_id uuid, p_customer_id uuid)
returns void
language plpgsql
as $$
declare
  v_balance numeric(12, 2);
begin
  select coalesce(sum(case when entry_type = 'credit_sale' then amount
                           else -amount end), 0)
    into v_balance
    from customer_ledger
    where customer_id = p_customer_id;

  if v_balance <> 0 then
    raise exception 'Cannot delete a customer who still owes money';
  end if;

  delete from customers where id = p_customer_id and shop_id = p_shop_id;
end;
$$;
