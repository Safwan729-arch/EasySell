-- =============================================================================
-- 0014: remove PART of a delivery, retry-safe
-- =============================================================================
-- 0013 always removed everything left of a delivery and closed it. One broken
-- bottle out of a batch of 30 had no exact way out: lowering stock by hand
-- takes the unit from the OLDEST delivery (the estimate's FIFO), which may be
-- the wrong batch.
--
-- remove_batch_stock(shop, batch, quantity, close, removal_id):
--   * expired (locked): removes the locked count and closes, as before.
--   * not expired, p_close = true: removes p_quantity and closes (0013).
--   * not expired, p_close = false: removes p_quantity and KEEPS the delivery
--     open. The units are added to picked_qty (0012) -- they left THIS
--     delivery, exactly like a sale picked from it -- so the estimate takes
--     them off this batch and no other.
--
-- Retry safety: closing made 0013 safe to retry, but a partial removal leaves
-- the delivery open. The phone now mints p_removal_id and re-sends it on a
-- retry; the adjustment row is inserted with that id, so a repeat finds it and
-- changes nothing (the record_restock method from 0011). The check runs before
-- everything else: the first call already lowered stock and the cap.
--
-- OVERLOAD WARNING (same trap as 0006/0009/0010/0011): the argument list
-- changes, so 0013's signature is dropped first or PostgREST could no longer
-- pick one. The new parameters have defaults, so a call shaped like 0013's
-- still resolves.
-- =============================================================================

drop function if exists remove_batch_stock(uuid, uuid, numeric);
drop function if exists remove_batch_stock(uuid, uuid, numeric, boolean, uuid);

create function remove_batch_stock(
  p_shop_id    uuid,
  p_batch_id   uuid,
  p_quantity   numeric default null,
  p_close      boolean default true,
  p_removal_id uuid default null
) returns product_batches
language plpgsql
as $$
declare
  v_id      uuid := coalesce(p_removal_id, gen_random_uuid());
  v_batch   product_batches;
  v_product products;
  v_qty     numeric;
  v_close   boolean := coalesce(p_close, true);
begin
  -- Serialise calls with the same id so two overlapping retries cannot both
  -- miss the row below and both remove.
  perform pg_advisory_xact_lock(hashtextextended(v_id::text, 0));

  if exists (select 1 from transactions where id = v_id and shop_id = p_shop_id)
  then
    select * into v_batch from product_batches
      where id = p_batch_id and shop_id = p_shop_id;
    return v_batch;
  end if;

  select * into v_batch from product_batches
    where id = p_batch_id and shop_id = p_shop_id
    for update;
  if not found then
    raise exception 'Delivery not found';
  end if;

  -- Already closed: a second tap, or a retry of a full removal. Change
  -- nothing, so stock is never removed twice.
  if v_batch.closed_at is not null then
    return v_batch;
  end if;

  select * into v_product from products
    where id = v_batch.product_id and shop_id = p_shop_id
    for update;
  if not found then
    raise exception 'Product not found';
  end if;

  if v_batch.expired_qty is not null then
    v_qty := v_batch.expired_qty;
    v_close := true;
  elsif p_quantity is null then
    raise exception 'Delivery is not expired';
  elsif p_quantity <= 0 then
    raise exception 'Quantity must be greater than zero';
  else
    v_qty := least(p_quantity,
                   greatest(v_batch.quantity - v_batch.picked_qty, 0));
  end if;

  -- Stock may have been lowered by hand below the delivery's count.
  v_qty := least(v_qty, v_product.quantity);

  if v_qty > 0 then
    update products set quantity = quantity - v_qty, updated_at = now()
      where id = v_product.id;

    -- quantity is units REMOVED and must be positive:
    -- transactions_discount_within_line (0009) checks
    -- discount_amount <= selling_price * quantity, which a negative fails.
    -- Every report filters type = 'sale', so this row moves no money figure.
    insert into transactions(id, shop_id, product_id, type, quantity,
                             buying_price, selling_price, source, batch_id)
    values (v_id, p_shop_id, v_product.id, 'adjustment', v_qty,
            v_batch.buying_price, v_product.selling_price, 'manual',
            v_batch.id);
  end if;

  if v_close then
    update product_batches
      set closed_at = now(), closed_reason = 'removed'
      where id = p_batch_id
      returning * into v_batch;
  else
    update product_batches
      set picked_qty = picked_qty + v_qty
      where id = p_batch_id
      returning * into v_batch;
  end if;

  return v_batch;
end;
$$;
