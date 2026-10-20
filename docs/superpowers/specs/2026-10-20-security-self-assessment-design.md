# Security self-assessment for the hackathon (2026-10-20)

The optional "Security self-assessment report" deliverable. It lives as a Claude
Doc ("EasySell: Security Self-Assessment"); its scripts and raw results are in
`docs/hackathon/security/`.

## Why it was built this way

- **Fresh live attacks, not a summary of the 19 Oct review.** The evidence
  probe (13 attacks) and money-safety checks (7) were re-run, plus 13 new
  attacks in `extra_probe.mjs`, all from throwaway test shops that
  `cleanup.mjs` then deleted. No admin key, so results reflect a real attacker.
- **Severity follows the OWASP rating idea**, stated in plain words in the
  report: High = an outsider reads or changes another shop's data or spends our
  money.
- **Every count was re-added before publishing.** The first draft said "33 of
  35"; the real split is 26 attacks = 23 blocked + 2 that found L1 + 1 that
  confirmed M2 (an owner editing their own sale).

## Findings worth remembering

- **New: L1, cross-shop references.** RLS checks only `shop_id`, and
  `transactions.product_id` / `customer_ledger.customer_id` are plain foreign
  keys, so shop B can save a row in its own shop naming shop A's product or
  customer (the FK check bypasses RLS). A's data is untouched, but the link
  **blocks deleting A's product, and so A's whole shop** (`transactions.product_id`
  has no `on delete` rule). `product_batches` already uses the safe composite key
  `(product_id, shop_id)`; copy that, or make these tables write-only through RPCs
  (the M2 fix closes both).
- **L1 fixed in migration `0021_same_shop_links.sql`.** Five links now
  reference `(id, shop_id)`: transactions → products and → product_batches,
  customer_ledger → customers, notifications → products, products →
  categories. Decisions:
  - **Delete behaviour kept exactly.** `on delete set null (column)` (Postgres
    15+) clears only the link column; plain `set null` on a composite key would
    also null `shop_id` and fail its not-null.
  - **Old constraints found by column, not name**, so a database whose
    auto-generated names differ still migrates.
  - **A pre-check raises a readable error** if any cross-shop row already
    exists, inside `begin … commit`, so a bad database is left unchanged.
  - **Rejected: making the tables write-only through RPCs now.** That is the
    M2 fix and also closes L1, but it touches every write path the app has;
    the composite keys close L1 with no app change.
  - Verified on PGlite, 22 checks (`docs/hackathon/security/test_0021_pglite.mjs`),
    then live after the owner ran 0021: both cross-shop writes now get 409
    from `transactions_product_same_shop` / `customer_ledger_customer_same_shop`;
    the re-run blocked 25 of 26 (the 26th is M2, by design of the check).
  - **Gotcha:** the M2 check first edited the L1 probe row, so once L1 was
    fixed shop B had no sale to edit. The probe now gives B its own product
    and a real checkout sale before the edit.
- **Gotcha (before 0021): clean the L1 probe rows before `cleanup.mjs`**, or
  deleting test shop A fails on the product link.
- **Gemini data terms** (checked at ai.google.dev/gemini-api/terms): paid
  traffic is not used to improve products; the free tier may be read by human
  reviewers. The key must be on a billing-enabled project before launch.
- **OSV scan:** 198 pub packages, 0 known vulnerabilities. `pubspec.lock` has
  CRLF line endings; parse after normalising them or nothing matches.
- **The release APK holds exactly one token, role `anon`**, is not debuggable,
  and is signed with the Android debug key (L2).
