-- =============================================================================
-- 0022: sales and credit rows change only through the app's database functions
-- (spec docs/superpowers/specs/2026-10-20-money-rows-rpc-only-design.md, finding M2)
-- =============================================================================
-- RLS lets an owner insert, update and delete their OWN shop's rows. For
-- `transactions` and `customer_ledger` that meant an owner could rewrite their
-- own sales history directly (live test, 2026-10-20: a past sale's price was
-- changed with one request), which a lender could not trust. The app never
-- does this: it reads these tables directly but writes them only through
-- record_sale_cart, record_restock, record_payment, the three remove_*
-- functions and delete_customer.
--
-- Now:
--   1. A guard trigger refuses any insert, update or delete of a sales or
--      credit row by a signed-in or anonymous API user...
--   2. ...unless one of the 8 writer functions is running. Each sets a
--      transaction-local flag (easysell.via_rpc) as its first step. PostgREST
--      runs one statement per request and exposes no way to set that flag, so
--      only these functions can.
--   3. Deleting a customer directly is refused once they have ledger history
--      (the cascade would erase it); delete_customer, which refuses unless the
--      balance is 0, still works.
-- Not affected: admin work in the SQL editor or with the service role (not an
-- API user), deleting a whole shop (the cascade runs as the table owner), and
-- deleting a delivery (its set-null on transactions.batch_id also runs as the
-- owner). Reads are unchanged.
--
-- The flag line is added to the LIVE definitions of the 8 functions, so this
-- works whatever their current text is. IMPORTANT for later migrations: any
-- `create or replace` of one of these functions must keep the line
--     perform set_config('easysell.via_rpc', 'on', true);
-- as the first statement, or that function's writes will be refused.
--
-- Safe to re-run. Runs as one transaction.
-- =============================================================================

begin;

-- 1. The guard. Not security definer: it must see the caller's role.
create or replace function guard_money_rows()
returns trigger
language plpgsql
as $$
begin
  if current_user not in ('authenticated', 'anon')
     or current_setting('easysell.via_rpc', true) = 'on' then
    return coalesce(new, old);
  end if;
  raise exception 'Sales and credit records can only be changed by the app''s checkout, restock, stock removal and payment steps'
    using errcode = '42501';
end;
$$;

drop trigger if exists trg_transactions_rpc_only on transactions;
create trigger trg_transactions_rpc_only
  before insert or update or delete on transactions
  for each row execute function guard_money_rows();

drop trigger if exists trg_customer_ledger_rpc_only on customer_ledger;
create trigger trg_customer_ledger_rpc_only
  before insert or update or delete on customer_ledger
  for each row execute function guard_money_rows();

-- 2. Customers: a direct delete would cascade into the ledger as the table
--    owner, past the guard above, so it is checked here instead.
create or replace function guard_customer_delete()
returns trigger
language plpgsql
as $$
begin
  if current_user in ('authenticated', 'anon')
     and coalesce(current_setting('easysell.via_rpc', true), '') <> 'on'
     and exists (select 1 from customer_ledger where customer_id = old.id) then
    raise exception 'A customer with credit history can only be removed with the app''s Delete customer step'
      using errcode = '42501';
  end if;
  return old;
end;
$$;

drop trigger if exists trg_customers_delete_guard on customers;
create trigger trg_customers_delete_guard
  before delete on customers
  for each row execute function guard_customer_delete();

-- 3. Give the 8 writer functions the flag, by rewriting their live
--    definitions: the line goes right after the body's first BEGIN.
do $$
declare
  v_fn regprocedure;
  v_def text;
  v_new text;
  v_done int := 0;
begin
  for v_fn in
    select p.oid::regprocedure
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('record_sale', 'record_sale_cart', 'record_restock',
                        'record_payment', 'delete_customer', 'remove_batch_stock',
                        'remove_undated_stock', 'remove_expired_stock')
  loop
    v_def := pg_get_functiondef(v_fn);
    if position('easysell.via_rpc' in v_def) > 0 then
      v_done := v_done + 1;
      continue;
    end if;
    v_new := regexp_replace(
      v_def,
      '(\$function\$.*?\mbegin\M)',
      E'\\1\n  perform set_config(''easysell.via_rpc'', ''on'', true);',
      'i');
    if v_new = v_def then
      raise exception '0022: could not find the body of %', v_fn;
    end if;
    execute v_new;
    v_done := v_done + 1;
  end loop;
  if v_done < 7 then
    raise exception '0022: expected the 7 functions the app uses (plus the old record_sale), found %', v_done;
  end if;
end $$;

commit;
