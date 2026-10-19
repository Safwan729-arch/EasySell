# Full codebase review: bugs and security fixes (2026-10-19)

A full review before the hackathon's technical documentation: every migration
(0001–0019) and its RLS, the three Edge Functions, auth and routing, and the
money paths in the app (checkout, khata payments, restock, removals, Money
health). Baseline before the fixes: `flutter analyze` clean, 707 tests passing.

## What was checked and found sound

- **RLS on every table** (users, shops, products, transactions,
  analytics_daily, notifications, categories, customers, customer_ledger,
  product_batches), all scoped through `shops.owner_id = auth.uid()`.
- **Only two `security definer` functions**, both signup triggers
  (`handle_new_user`, `seed_default_categories`), with `search_path` pinned and
  writing only rows for the row just created. Every RPC the app calls is
  security invoker, so RLS applies inside it and a shop id from another tenant
  finds nothing.
- **Money paths**: `record_sale_cart` (row locks, stock never negative,
  discount capped and split exactly, retry-safe since 0010), `record_restock`,
  `remove_batch_stock`, `remove_undated_stock` (all retry-safe with
  phone-minted ids).
- **No secrets in git**: `dart_defines.json` is ignored and was never
  committed; Gemini keys live only in Edge Function secrets.
- **AI output is never trusted**: the functions drop invented product ids, clamp
  confidences and cap output tokens; the seller confirms every voice and scan
  result before anything is saved.
- **Saved AI tips do not leak between accounts** on a shared phone: they only
  show when every number in the cache key matches the current shop's.
- Guest sign-in is debug-only; the Google button is hidden.

## Fixes

### 1. AI functions callable without an account (security)

Supabase's gateway verifies the token's signature, but the public anon key is
itself a valid token (role `anon`) and is compiled into every APK. Anyone who
unpacked the app could call `parse-sale`, `recognize-product` and
`money-tips` and spend the Gemini quota without signing in.

Each function now reads the (already signature-checked) token claims and
accepts only `role = authenticated` with `is_anonymous` not true, else **401**.
Guest sessions are refused because anyone can mint one with the anon key if
anonymous sign-in is ever turned on.

- **Rejected: `auth.getUser()` per call.** It verifies independently of the
  gateway but adds an Auth round trip to every voice sale, the path that was
  tuned hardest for latency. The claims check is sound as long as JWT
  verification stays on, so the README now says never to deploy with
  `--no-verify-jwt`.
- The helper is copied into each `index.ts` rather than shared, because
  `recognize-product` is deployed as a single file.
- **Request size caps** (413): candidates ≤ 5000, audio base64 ≤ 2 M chars,
  transcript ≤ 2000, image base64 ≤ 8 M, money-tips facts ≤ 8000 chars. Each is
  far above what the app sends (15 s of 32 kbps audio ≈ 80 KB base64; a
  medium-resolution JPEG is a few hundred KB), so they only stop requests that
  did not come from the app.
- **Still open:** email confirmation is off for the demo, so a throwaway
  account takes seconds. Before a real launch, turn confirmation back on and add
  a per-user daily cap on AI calls.

### 2. Dashboard, Reports and chart cut days at UTC midnight (bug)

`get_dashboard_summary` and `get_sales_series` used `date_trunc` on `now()` and
`created_at` in the server's UTC. Sales History and the Reports best sellers
and category split cut at the phone's midnight, so one screen could disagree
with itself. In Bangladesh a sale at 3 AM counted for yesterday on the chart.
In a UTC−6 market (Mexico is in the plan), every sale after 6 PM counted for
tomorrow, and "Today" at 7 PM showed only the last hour.

Migration 0020 adds `p_utc_offset_minutes` to both, the way 0017 and 0019
already do: truncate the phone's wall clock, then shift back to the UTC
instant. Each chart bucket is returned as the UTC instant of its local start,
so the app's `toLocal()` lands on local midnight of the right date. One offset
(today's) is used for the whole range, which is exact for every launch market
(none uses daylight saving).

### 3. Khata payments could be recorded twice (bug)

`record_payment` had no retry id. On weak signal the server could save the
payment and lose the reply. The sheet stayed open, a second tap saved it again,
and debt the customer still owed was wiped. Sales, restocks and removals were
made retry-safe in 0010–0015; payments were missed.

0020 adds `p_payment_id`, using the `record_restock` method: an advisory lock
on the id, return the existing ledger row if found, otherwise insert with that
id. The sheet mints one id per (amount, note) and re-sends it while the same
payment is retried; a changed amount or note is a new payment with a new id.
The amount is also rounded to 2 decimals before the `> 0` check, so 0.004 is
refused with a readable message instead of tripping the column's check
constraint.

### 4. A failed payment hid the ledger and its own error (bug)

`CustomerDetailController.recordPayment` set the controller's state to
`AsyncError` on failure. That replaced the customer's whole ledger with an
error message, and the error snackbar appeared behind the still-open sheet,
where the seller could not see it. The failure now goes back to the sheet,
which shows it in red under the amount; the ledger is untouched.

### 5. Android backup of the login session (hardening)

`allowBackup` defaulted to true, so cloud backup could copy the stored session
off the phone. Now `allowBackup="false"`, plus `dataExtractionRules`, which
excludes everything from cloud backup and phone-to-phone transfer (on Android
12+, `allowBackup` alone does not stop device transfer).

## Noted, not changed

- **Release APKs are signed with the debug key.** It needs a real keystore
  that only the team should hold. Do this before any store upload.
- **Owners can write their own `transactions` and `customer_ledger` rows
  directly** (RLS is `for all`). It is safe between shops, but a shop could edit
  its own history. That matters once lenders rely on these records: move those
  writes to RPC-only (revoke insert/update/delete, keep select) before real
  lender partnerships.
- **The top debtor's name goes to Gemini** in the money-tips facts. It is
  needed for a useful tip, and it is disclosed in the security notes.

## Verification

- 0020 was run in PGlite (Postgres 16) against a minimal copy of the schema,
  twice, to prove it is safe to re-run. It passed 18 checks: a 00:30 local sale
  counts as today at UTC+6 (and is missed at offset 0, reproducing the bug);
  `p_day` and the day, week and month series buckets; chart buckets returned as
  local midnight; a same-id retry recorded once; 0.004 and overpayment refused;
  old 3- and 4-argument calls still resolve.
- The sign-in check was tested against the real anon key (refused), a
  signed-in token (accepted), and guest, service-role, missing and junk tokens
  (all refused). All three functions were syntax-checked with esbuild.
- New widget tests: a failed payment shows its error in the sheet; an unchanged
  retry re-sends the same id; a changed amount sends a new one.

## Deploy order

1. Paste `0020_local_day_and_payment_retry.sql` into the SQL editor **before**
   installing the new app build. The app now sends `p_utc_offset_minutes` and
   `p_payment_id`, which an un-migrated database rejects, so the Home totals,
   chart and payments would fail.
2. Redeploy all three Edge Functions. An older installed app still works,
   because it already sends the signed-in user's token.
