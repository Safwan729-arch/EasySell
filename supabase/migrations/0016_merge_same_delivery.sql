-- =============================================================================
-- 0016: one delivery per (product, date added, expiry date, buying price)
-- =============================================================================
-- Two restocks of Pepsi on the same day with the same expiry date made two
-- deliveries that look identical (1 pc and 15 pcs). Since the seller must now
-- choose the batch at checkout when there are several (spec §17), every Pepsi
-- sale asked a pointless question.
--
-- A new delivery now JOINS an open delivery of the same product when all of
-- these match:
--   * expiry_date  -- what the seller chooses by;
--   * received_on  -- the estimate's order (newest received sells first);
--   * buying_price -- frozen per delivery; the "Thrown away" loss (§18) is
--                     valued at it, so two prices must stay apart.
-- A delivery with a locked expired count (expired_qty) is never joined: its
-- units are already reserved as expired.
--
-- Done as a BEFORE INSERT trigger, so record_restock (0011) and the app's
-- "Add expiry date" insert both merge with no change to either, and an app
-- build from before this migration keeps working. Joining means: add the
-- quantity to the existing row and skip the insert. Stock is unaffected --
-- the caller changes it, exactly as for a new delivery.
--
-- Run after 0015. Safe to re-run.
-- =============================================================================

create or replace function merge_same_delivery() returns trigger
language plpgsql
as $$
declare
  v_id uuid;
begin
  if new.closed_at is not null or new.expired_qty is not null then
    return new;
  end if;

  -- Two inserts for one product at once could both miss the row below and
  -- both insert. record_restock already holds this lock; it is re-entrant.
  perform 1 from products
    where id = new.product_id and shop_id = new.shop_id
    for update;

  select id into v_id from product_batches
    where shop_id = new.shop_id
      and product_id = new.product_id
      and closed_at is null
      and expired_qty is null
      and expiry_date = new.expiry_date
      and received_on = new.received_on
      and buying_price = new.buying_price
    order by created_at, id
    limit 1
    for update;

  if v_id is null then
    return new;
  end if;

  update product_batches
    set quantity = quantity + new.quantity
    where id = v_id;
  return null; -- joined: no new row
end;
$$;

drop trigger if exists product_batches_merge_same on product_batches;
create trigger product_batches_merge_same
  before insert on product_batches
  for each row execute function merge_same_delivery();

-- -----------------------------------------------------------------------------
-- One-time: merge the identical open deliveries that already exist. The oldest
-- row of each group is kept; sales and removals that named another row are
-- pointed at it first, then quantities and picks are summed into it.
-- -----------------------------------------------------------------------------
do $$
declare
  g record;
begin
  for g in
    select (array_agg(id order by created_at, id))[1] as keep_id,
           array_agg(id) as ids,
           sum(quantity)   as qty,
           sum(picked_qty) as picked
    from product_batches
    where closed_at is null and expired_qty is null
    group by shop_id, product_id, expiry_date, received_on, buying_price
    having count(*) > 1
  loop
    update transactions
      set batch_id = g.keep_id
      where batch_id = any (g.ids) and batch_id <> g.keep_id;
    delete from product_batches
      where id = any (g.ids) and id <> g.keep_id;
    update product_batches
      set quantity = g.qty, picked_qty = g.picked
      where id = g.keep_id;
  end loop;
end $$;
