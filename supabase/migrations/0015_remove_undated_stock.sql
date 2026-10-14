-- =============================================================================
-- 0015: remove stock that has no expiry date, retry-safe
-- =============================================================================
-- The product edit form no longer has a stock box: stock moves through sales,
-- restock and "Remove from stock" only. Deliveries got Remove in 0013/0014,
-- but stock in no delivery -- all of a product without dates, like soap -- had
-- no way off the shelf. This is that way.
--
-- Lowers the product's stock by p_quantity (capped at stock) and records the
-- loss as a positive 'adjustment' row with no batch. Which units are "undated"
-- is the app's estimate, so the app caps the amount; the server only caps at
-- stock. The estimate takes a stock drop from undated stock first, so no
-- delivery changes.
--
-- Retry safety: the phone mints p_removal_id and re-sends it on a retry; the
-- adjustment row is inserted with that id, so a repeat finds it and changes
-- nothing (the record_restock method from 0011).
-- =============================================================================

drop function if exists remove_undated_stock(uuid, uuid, numeric, uuid);

create function remove_undated_stock(
  p_shop_id    uuid,
  p_product_id uuid,
  p_quantity   numeric,
  p_removal_id uuid default null
) returns transactions
language plpgsql
as $$
declare
  v_id      uuid := coalesce(p_removal_id, gen_random_uuid());
  v_product products;
  v_qty     numeric;
  v_txn     transactions;
begin
  -- Serialise calls with the same id so two overlapping retries cannot both
  -- miss the row below and both remove.
  perform pg_advisory_xact_lock(hashtextextended(v_id::text, 0));

  select * into v_txn from transactions
    where id = v_id and shop_id = p_shop_id;
  if found then
    return v_txn;
  end if;

  if p_quantity is null or p_quantity <= 0 then
    raise exception 'Quantity must be greater than zero';
  end if;

  select * into v_product from products
    where id = p_product_id and shop_id = p_shop_id
    for update;
  if not found then
    raise exception 'Product not found';
  end if;

  v_qty := least(p_quantity, v_product.quantity);
  if v_qty <= 0 then
    raise exception 'Insufficient stock for %: have %, need %',
      v_product.name, v_product.quantity, p_quantity;
  end if;

  update products set quantity = quantity - v_qty, updated_at = now()
    where id = v_product.id;

  -- quantity is units REMOVED and must be positive:
  -- transactions_discount_within_line (0009) checks
  -- discount_amount <= selling_price * quantity, which a negative fails.
  -- Every report filters type = 'sale', so this row moves no money figure.
  insert into transactions(id, shop_id, product_id, type, quantity,
                           buying_price, selling_price, source)
  values (v_id, p_shop_id, v_product.id, 'adjustment', v_qty,
          v_product.buying_price, v_product.selling_price, 'manual')
  returning * into v_txn;

  return v_txn;
end;
$$;
