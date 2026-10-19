# Data export as a file — Design (parked)

**Date:** 2026-10-19
**Status:** **Parked.** Suggested and agreed as a future plan; the user chose to
build it after the hackathon submission (deadline 20 Oct 2026, Beijing time).
Listed under "Future plans" in the hackathon technical documentation. Nothing
is built.
**Related:**
- [[2026-10-18-money-health-financing-design]] — the numbers the monthly report
  would reuse (`get_finance_health`)
- [[2026-10-19-codebase-review-fixes-design]] — "owners can edit their own
  transaction/ledger rows directly", which matters once a lender trusts the
  report

## Why

The owner has no way to get their records out of the app. The main reason it
matters is Topic E: a one-page monthly report is the first version of the
"shareable credit profile" in the tech doc's Next steps, something a shop owner
can hand to a lender.

## What was proposed

Settings → Export → pick the file and the period (this month, last month,
custom) → Android's share menu (WhatsApp, email, Drive, save to phone).

| File | Format | For |
|---|---|---|
| Sales list: date, items, quantity, price, payment type | CSV | Owner, accountant |
| Products and stock: stock, prices, value, expiry dates | CSV | Stock-taking, suppliers |
| Customer credit: balances and payments | CSV | Owner's records |
| Monthly business report: revenue, profit, money in/out, credit owed, best sellers | PDF, one page | Lender or bank |

## Decisions so far (Claude's calls, not yet reviewed by the user)

- **Packages:** `share_plus` (share menu) and `pdf` (report). `path_provider`
  is already a dependency.
- **Same numbers as the screens:** read through the existing RPCs
  (`get_dashboard_summary`, `get_finance_health`, history queries), never
  re-summed in Dart, so the file can't disagree with the app.
- **Made on the phone, nothing new on the server.** RLS already scopes every
  read to the shop.
- **Privacy:** files contain customer names, so show a short note before sharing.

## Gotchas found while suggesting it

- **Bangla in CSV:** write a UTF-8 BOM, or Excel opens Bangla as mojibake.
- **Bangla in PDF:** the `pdf` package's built-in fonts have no Bengali glyphs,
  so Bangla renders as empty boxes. Bundle a Bengali font (e.g. Noto Sans
  Bengali) and test conjuncts on the device.
- **CSV money columns:** plain numbers plus a separate currency column, no
  symbol, so spreadsheets can sum them.

## Rejected for now

- **Building it before the deadline.** Even the PDF-only slice was estimated at
  about half a day with tests and a device check, and the doc and screenshots
  would need redoing. The user chose to wait.

## Open questions (resume here)

1. Build the PDF report first, or all four files together?
2. Should the report say it was made by EasySell and can't be edited? A lender
   can't trust it until owners can no longer edit their own sale and ledger rows
   (see the review doc).
3. Should "Export" sit in Settings only, or also on the Money health and
   History screens?
