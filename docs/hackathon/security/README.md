# Security self-assessment: scripts and results

These files back the "EasySell: Security Self-Assessment" report (20 October
2026). They add to the execution-evidence scripts in `../evidence/`.

| Script | What it checks | Result |
|---|---|---|
| `../evidence/security_probe.mjs` | The public key and another shop's owner against the live system (13 attacks) | `results/security_probe_20oct.json` |
| `../evidence/money_safety.mjs` | Races, retries, all-or-nothing carts, frozen prices (7 checks) | `results/money_safety_20oct.json` |
| `extra_probe.mjs` | 13 more attacks: taking over a shop, payments across shops, rows that name another shop's IDs, editing one's own history, negative quantities, forged tokens | `results/extra_probe.json` (after migration `0021`: both cross-shop rows refused); `results/extra_probe_before_0021.json` (the first run, which found L1) |
| `osv.mjs` | Every package in `pubspec.lock` against the OSV vulnerability database | `results/osv_scan.txt` |
| `apk_tokens.mjs` | Every token inside an unpacked APK (prints only its role) | `results/apk_tokens.txt` |
| `appscan.mjs` | App code: logging, plain-HTTP URLs, local storage, password rules | `results/app_scan.txt` |
| `new_account_probe.mjs` | Migration `0024`: signs up one throwaway account and expects it to be refused after 10 AI calls on its first day, then `parse-sale` to answer 429. Spends no Gemini quota | `results/new_account_probe.json` |
| `signin_rate_probe.mjs` | Failed sign-ins (no account created) until Auth answers 429. Shows the burst only: Auth always allows about 30 at once | `results/signin_rate_probe.json` |
| `signup_rate_probe.mjs` | The real sign-up rate: empties Auth's bucket, then one refused sign-up (too-short password, no account) every 5 s for 2 minutes. Expects about 6 through (15 per 5 minutes). Run it last, and a minute or two after changing the setting | `results/signup_rate_probe.json` |
| `ai_limit_probe.mjs` | The daily AI limit (migration `0023` + redeployed functions): counters hidden, test account B refused after 50 calls, then `parse-sale` and `money-tips` answer 429. Spends no Gemini quota | `results/ai_limit_probe.json` |

## Running them

The live scripts need the same setup as `../evidence/README.md` (Node 18+,
`dart_defines.json` at the repo root, `EV_CREDS` pointing at a file outside
the repo).

```bash
export EV_CREDS=/somewhere/outside/the/repo/creds.json
node ../evidence/setup.mjs
node ../evidence/money_safety.mjs
node ../evidence/security_probe.mjs
node extra_probe.mjs
node ai_limit_probe.mjs   # uses up test account B's 50 AI calls for today
node new_account_probe.mjs   # leaves one more throwaway login in Auth
node ../evidence/cleanup.mjs
node signin_rate_probe.mjs   # last: blocks sign-ins from this connection for a short while
node signup_rate_probe.mjs   # about 2.5 minutes; blocks sign-ups from this connection for a few minutes
```

Before migration `0021`, `extra_probe.mjs` left one sale row and one ledger row
in test shop B that named shop A's product and customer (finding L1); those had
to be deleted as shop B before `cleanup.mjs`. Since `0021` both rows are
refused, so nothing is left behind.

`test_0021_pglite.mjs` runs migration `0021` on PGlite (a real Postgres engine)
against a minimal copy of the schema: 22 checks on same-shop links, delete
behaviour, re-running, and refusing to start if a cross-shop row already exists.

`test_0022_pglite.mjs` builds the whole database from every migration on
PGlite (Supabase stubs in `fullschema.mjs`) and runs 28 checks on migration
`0022`: every app write path still works, and every direct change to a sale or
credit row is refused (finding M2). `test_0023_pglite.mjs` runs 21 checks on
the daily AI limit (finding M1), and `test_0024_pglite.mjs` 16 on the stricter
limit for accounts in their first 24 hours; `test_ai_limit_helper.mjs` checks the AI
functions' side of it against a fake database.

```bash
npm i @electric-sql/pglite
node test_0021_pglite.mjs ../../../supabase/migrations/0021_same_shop_links.sql
node test_0022_pglite.mjs ../../../supabase/migrations
node test_0023_pglite.mjs ../../../supabase/migrations
node test_0024_pglite.mjs ../../../supabase/migrations
node test_ai_limit_helper.mjs ../../../supabase/functions   # Node 23.6+
```

```bash
node osv.mjs ../../../pubspec.lock
unzip -q EasySell.apk -d /tmp/apk && node apk_tokens.mjs /tmp/apk
node appscan.mjs ../../..
```
