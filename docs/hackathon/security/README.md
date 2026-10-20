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
node ../evidence/cleanup.mjs
```

Before migration `0021`, `extra_probe.mjs` left one sale row and one ledger row
in test shop B that named shop A's product and customer (finding L1); those had
to be deleted as shop B before `cleanup.mjs`. Since `0021` both rows are
refused, so nothing is left behind.

`test_0021_pglite.mjs` runs migration `0021` on PGlite (a real Postgres engine)
against a minimal copy of the schema: 22 checks on same-shop links, delete
behaviour, re-running, and refusing to start if a cross-shop row already exists.

```bash
npm i @electric-sql/pglite
node test_0021_pglite.mjs ../../../supabase/migrations/0021_same_shop_links.sql
```

```bash
node osv.mjs ../../../pubspec.lock
unzip -q EasySell.apk -d /tmp/apk && node apk_tokens.mjs /tmp/apk
node appscan.mjs ../../..
```
