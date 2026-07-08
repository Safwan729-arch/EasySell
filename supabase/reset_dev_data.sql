-- ============================================================
-- DEV DATA RESET — "Everything"
-- Run in: Supabase Dashboard → SQL Editor → New query → Run
-- ------------------------------------------------------------
-- DANGER: deletes ALL application data AND all login (auth)
-- records for this project. Intended for wiping a dev/test
-- database before repopulating with fresh data. After running,
-- you must sign up again and re-create the shop.
--
-- The cascade chain does all the work:
--   auth.users → public.users, shops
--   shops      → categories, products, transactions,
--                analytics_daily, notifications
--
-- NOTE: Supabase Storage objects (product images) are NOT
-- removed by this script — clean those up separately if needed.
-- ============================================================

begin;

-- One line clears everything via ON DELETE CASCADE.
delete from auth.users;

commit;

-- ---- Verification (should all return 0) --------------------
select
  (select count(*) from auth.users)       as auth_users,
  (select count(*) from public.users)     as users,
  (select count(*) from shops)            as shops,
  (select count(*) from categories)       as categories,
  (select count(*) from products)         as products,
  (select count(*) from transactions)     as transactions,
  (select count(*) from analytics_daily)  as analytics_daily,
  (select count(*) from notifications)    as notifications;
