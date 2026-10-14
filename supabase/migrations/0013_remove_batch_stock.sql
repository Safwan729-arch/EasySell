-- =============================================================================
-- 0013: remove any delivery's stock, not only an expired one
-- =============================================================================
-- 0011's remove_expired_stock only accepts a delivery locked as expired. A
-- shopkeeper who threw away (or returned) items the day BEFORE they expired
-- had no way to take them off stock, used "None left" instead -- which closes
-- the delivery without touching stock -- and the thrown-away units stayed
-- counted as good, sellable stock with no date. The app has dropped "None
-- left" (a sold-out delivery closes by itself) and offers "Remove from stock"
-- on every delivery.
--
-- remove_batch_stock(shop, batch, quantity):
--   * expired (locked): removes the locked count, exactly as before;
--     p_quantity is ignored.
--   * not expired: removes p_quantity -- the amount the app shows as left,
--     which only the app can estimate -- capped at stock and at what is left
--     of the delivery after picks (0012). Without p_quantity it refuses, as
--     before, so a stale app cannot remove an unlocked delivery by accident.
-- Either way: a positive 'adjustment' row records the loss, the delivery
-- closes as 'removed', and a closed delivery is left alone, so a retry after
-- a lost reply never removes stock twice.
--
-- remove_expired_stock (0011) stays for app builds from before this one.
-- =============================================================================

drop function if exists remove_batch_stock(uuid, uuid, numeric);

create function remove_batch_stock(
  p_shop_id  uuid,
  p_batch_id uuid,
  p_quantity numeric default null
) returns product_batches
language plpgsql
as $$
declare
  v_batch   product_batches;
  v_product products;
  v_qty     numeric;
begin
  select * into v_batch from product_batches
    where id = p_batch_id and shop_id = p_shop_id
    for update;
  if not found then
    raise exception 'Delivery not found';
  end if;

  -- Already closed: a second tap, or a retry after a lost reply. Change
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
  elsif p_quantity is null then
    raise exception 'Delivery is not expired';
  elsif p_quantity < 0 then
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
    insert into transactions(shop_id, product_id, type, quantity,
                             buying_price, selling_price, source, batch_id)
    values (p_shop_id, v_product.id, 'adjustment', v_qty,
            v_batch.buying_price, v_product.selling_price, 'manual',
            v_batch.id);
  end if;

  update product_batches
    set closed_at = now(), closed_reason = 'removed'
    where id = p_batch_id
    returning * into v_batch;

  return v_batch;
end;
$$;
