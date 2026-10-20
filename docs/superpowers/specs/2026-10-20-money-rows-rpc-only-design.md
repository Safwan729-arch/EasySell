# Sales and credit rows change only through the app's functions (2026-10-20)

Fixes security finding M2: RLS (`for all`) let an owner insert, update and
delete their own `transactions` and `customer_ledger` rows directly, so a shop
could rewrite its sales history (live test: one request changed a past sale's
price). Lenders must be able to trust that history. Migration
`0022_money_rows_rpc_only.sql`.

## Decisions

- **A guard trigger plus a flag, not revoked privileges.** The 8 writer
  functions (`record_sale_cart`, `record_restock`, `record_payment`,
  `remove_batch_stock`, `remove_undated_stock`, `remove_expired_stock`,
  `delete_customer`, and the unused `record_sale`) are *security invoker*, so
  RLS scopes them to the caller's shop. Revoking INSERT/UPDATE/DELETE would
  break them too, unless they became *security definer* with hand-written
  shop-ownership checks in every one, which is riskier. Instead each sets a
  transaction-local GUC `easysell.via_rpc = on` as its first statement, and a
  BEFORE trigger on both tables refuses writes by `authenticated`/`anon`
  without it. PostgREST runs one statement per request and does not expose
  `set_config`, so an API user cannot set the flag.
- **Rejected: `ALTER FUNCTION … SET easysell.via_rpc = 'on'`.** It needs no
  body change, but a non-superuser may not set a placeholder parameter that
  way ("permission denied to set parameter"; checked on PGlite as a
  non-superuser owner). Supabase's `postgres` role is not a superuser.
- **The flag line is injected into the live definitions** with
  `pg_get_functiondef` + a regex after the body's first `BEGIN`, so the
  migration works whatever the deployed text is. **Gotcha for every later
  migration:** a `create or replace` of one of these 8 functions must keep
  `perform set_config('easysell.via_rpc', 'on', true);` as its first
  statement, or its writes are refused (loudly, with a 403).
- **Admin and cascades are not blocked.** The guard checks `current_user`:
  the SQL editor (`postgres`) and the service role pass, so
  `supabase/seed/demo_data.sql` still works. Foreign-key cascades run as the
  table owner, so deleting a whole shop, or a delivery (set-null on
  `transactions.batch_id`), still works.
- **Customers needed their own guard.** Because cascades run as the owner,
  a direct `delete from customers` would have erased that customer's ledger
  past the trigger. Direct customer deletes are now refused when the customer
  has ledger rows; `delete_customer` (balance must be 0) still works.
- **Reads unchanged.** The app reads both tables directly and writes them
  only through the functions, so no app change and no new APK.

## Side effect

`scratchpad` scripts that seeded the judges' shop over the REST API as the
judges' user (direct inserts) no longer work. Re-seeding must be done as SQL
in the SQL editor.

## Verification

`docs/hackathon/security/test_0022_pglite.mjs` builds the whole database from
all 22 migrations on PGlite (with Supabase stubs in `fullschema.mjs`) and runs
28 checks: every app write path still works (checkout with credit and a
discount, retry, restock, payment, three removals, delete customer); every
direct insert/update/delete of a sale or credit row, and a direct delete of a
customer with history, is refused with 42501; reads, admin inserts, delivery
and shop deletion still work; re-running adds nothing.
