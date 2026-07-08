-- =============================================================================
-- 0004_category_management.sql — rename support for the Manage Categories screen
--
-- Run AFTER 0003 (Dashboard SQL Editor → paste → Run, or `supabase db push`).
-- Idempotent.
--
-- Renaming must update BOTH the display name and name_normalized, using the SAME
-- normalization as upsert_category (trim, collapse whitespace, lowercase) so the
-- dedup guarantee holds. A rename that would collide with another category in
-- the same shop is rejected with a friendly message (the unique constraint on
-- (shop_id, name_normalized) is the underlying guard).
--
-- DELETE needs no function: products.category_id is ON DELETE SET NULL (0003),
-- so deleting a category simply uncategorizes its products — it never deletes
-- them. The app deletes the row directly (RLS-scoped).
-- =============================================================================

create or replace function rename_category(
  p_id uuid,
  p_name text
) returns categories
language plpgsql
as $$
declare
  v_display text;
  v_norm    text;
  v_cat     categories;
begin
  v_display := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
  v_norm    := lower(v_display);

  if v_norm = '' then
    raise exception 'Category name cannot be empty';
  end if;

  update categories
    set name = v_display, name_normalized = v_norm
    where id = p_id
    returning * into v_cat;

  if not found then
    raise exception 'Category not found';
  end if;

  return v_cat;
exception
  when unique_violation then
    raise exception 'A category named "%" already exists', v_display;
end;
$$;
