-- =============================================================================
-- 0007_sale_cart.sql — multi-item cart checkout.
-- Run AFTER 0006_dashboard_summary_day.sql (Dashboard SQL Editor -> paste -> Run).
-- Idempotent (safe to re-run).
--
-- Adds sale_group_id (nullable) to transactions: every line inserted by one
-- record_sale_cart call shares the same id, so Sales History can group them
-- into a single "receipt" row. Existing rows stay null and keep rendering as
-- their own single-line receipt -- no backfill needed.
--
-- record_sale_cart mirrors record_sale but commits a whole cart atomically:
-- the entire loop runs inside this one function call, which Postgres executes
-- as a single transaction, so any raise exception (stock ran out on one line,
-- bad product id) rolls back every row lock, stock decrement, and insert made
-- earlier in the same checkout. There is no partial checkout.
-- =============================================================================

alter table transactions add column if not exists sale_group_id uuid;
create index if not exists idx_transactions_sale_group on transactions (shop_id, sale_group_id);

drop function if exists record_sale_cart(uuid, jsonb, text);

create function record_sale_cart(
  p_shop_id uuid,
  p_items jsonb,              -- [{"product_id": "...", "quantity": 2}, ...]
  p_source text default 'manual'
) returns setof transactions
language plpgsql
as $$
declare
  v_group uuid := gen_random_uuid();
  v_item record;
  v_product products;
begin
  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'Cart is empty';
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

  return query select * from transactions where sale_group_id = v_group;
end;
$$;
