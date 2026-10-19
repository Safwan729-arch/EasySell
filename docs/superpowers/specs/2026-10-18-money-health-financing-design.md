---
tags: [design, finance, hackathon]
---

# Money health (cash-flow alerts) + financing matching — design

Date: 2026-10-18. Built straight from the conversation (no separate plan).

## 1. Why

The app is entered in a hackathon under **Topic E: SME Finance Copilot**:
*"financing-option matching, cash-flow management with alerts, and business
financial analysis."* Analysis already existed (dashboard, analytics). The other
two did not. The user asked for both; the brainstorm was cut short ("self-review,
then build"), so the demo moment below is **my proposal**, which the user approved
as "matches the requirements" without changing it.

Demo moment: the owner opens Home and sees a **Money health** card with this
week's cash in / out / net and up to three plain warnings. Tapping it opens a
**Money health** screen with the full picture and a **Financing for your shop**
section that lists example loan types, each marked "fits you" or "not yet",
with a one-line reason drawn from the shop's own numbers.

Self-review against the topic text found one gap in my first pitch: alerts
alone are not "cash-flow *management*". The weekly in/out/net breakdown was
added for that.

## 2. Goals / non-goals / anti-goals

- Goal: both features run on data the app already records; no new data entry.
- Goal: every alert and every match says *why* in one sentence (explainable is
  what the judges reward, and it is what a shopkeeper trusts).
- Non-goal: real lenders, applications, or credit scores.
- Non-goal: phone push notifications (Member C owns them; the alerts are
  computed live, so a later push can read the same RPC).
- Anti-goal: anything that reads as a real loan offer. The catalogue uses
  generic loan *types*, no lender names, and the screen carries a disclaimer.
- Anti-goal: breaking Home for a shop whose database lacks migration 0019.
  The card hides on error, like Restock soon does for 0017.

## 3. Data — one read-only RPC, `get_finance_health` (migration 0019)

One row of plain sums; all decisions are made in Dart (same split as the
restock planner: aggregate in Postgres, judge in pure Dart so the rules are
unit-tested — there is no database in the test suite).

Local days come from the phone (`p_today`, `p_utc_offset_minutes`) — the
server's `current_date` is UTC, still yesterday in Bangladesh until 6 AM
(lesson from the expiry and restock work).

| Field | Meaning |
|---|---|
| `cash_sales_7d`, `digital_sales_7d`, `credit_sales_7d` | net sales (after discount) in the last 7 local days **including today**, split by how they were paid |
| `collected_7d` | khata payments received in the same 7 days |
| `restock_spend_7d` | restock rows × their frozen buying price |
| `sales_week`, `sales_prev_week` | net sales over the 7 **full** days ending yesterday, and the 7 before |
| `owed_now`, `owed_week_ago` | total khata balance now, and at the start of the 7-day window |
| `overdue_count`, `overdue_top_*` | debtors whose oldest unpaid credit is ≥ 30 days old; the biggest one by balance |
| `sales_90d`, `profit_90d`, `digital_sales_90d`, `restock_spend_90d` | the last 90 local days |
| `active_weeks_12` | how many of the last 12 weeks had at least one sale |
| `trading_days` | days since the shop's first transaction (not `shops.created_at`: seeded/back-dated demo data starts earlier than the shop row) |

Decisions inside the SQL:

- **Payment split.** `payment_method` only exists from 0018, and old rows were
  deliberately not backfilled. For cash flow a row is *credit* when it says so
  **or** its `sale_group_id` has a `credit_sale` ledger row; *digital* when it
  says so; otherwise *cash*. A pre-0018 non-credit sale did bring money in that
  day, so counting it as received is right for cash flow even though History
  still refuses to label it.
- **Cash out = restock spend only.** The app records no other expenses (rent,
  wages). Restocks may also be bought on supplier credit; we cannot tell. Both
  are accepted limits, stated on the screen as "Out (restocks)".
- **Overdue uses FIFO, not "last payment".** "Days since last payment" was
  rejected: a customer who settled fully 60 days ago and took new credit
  yesterday would look 60 days late. Instead payments are applied to the
  oldest credit first; the first credit sale not fully covered is the age of
  the debt. 30 days because khata is normally settled monthly.
- Not `security definer`: RLS on every table it reads still applies.

## 4. Cash-flow alerts (Dart, `cash_flow_alerts.dart`)

Shown most serious first, at most three on Home, all on the screen.

| Alert | Fires when | Why this threshold |
|---|---|---|
| Overdue customers | `overdue_count > 0` | money already late is the most concrete action ("call Rahim") |
| Cash out > in | `restock_spend_7d > cash_in_7d` and spend > 0, where cash in = cash + digital sales + collected | the drawer shrank this week; credit sales are excluded because no money arrived |
| Credit growing | owed rose this week by ≥ 20 % of last week's balance (any rise if it was 0) **and** by ≥ 5 % of the week's sales | 20 % is a clear trend, the 5 % floor stops a ৳20 rise on a tiny balance from alarming anyone. Relative thresholds only — shops use different currencies, so no fixed amounts |
| Sales dropping | `sales_prev_week > 0` and `sales_week ≤ 75 %` of it | a 25 % fall week-on-week is beyond normal day-to-day noise; full days only, so a quiet morning doesn't trigger it |

With no alerts the card says so in green — "nothing to worry about" is also
an answer. The card hides when the week has no money movement and nobody owes
anything (a brand-new shop), on error, and while loading.

## 5. Financing matching (Dart, `financing_match.dart`)

A fixed catalogue of four **example** loan types in code, not a table: it is
illustrative, bilingual through the ARB files like every other string, and has
no admin screen; a table would add a migration and RLS for nothing in the demo.

Every check is relative (months, percentages, weeks) — no currency amounts.
"Monthly sales" = `sales_90d` spread over the days actually traded (max 90) × 30.

| Option | Fits when | Shown amount ("up to about") |
|---|---|---|
| Supplier credit (stock now, pay in 30 days) | trading ≥ 3 months, restocked in the last 90 days, sold in ≥ 8 of 12 weeks | one month of restock spend |
| Mobile-wallet small loan | trading ≥ 3 months, digital ≥ 10 % of 90-day sales | one month of digital sales |
| Microfinance shop loan | trading ≥ 6 months, sold in ≥ 10 of 12 weeks | one month of sales |
| Bank SME loan | trading ≥ 12 months, profit margin ≥ 10 %, credit owed ≤ 50 % of monthly sales | three months of sales |

Ladder logic: easier, smaller options first; each step needs a longer record.
The wallet loan is the one that rewards the new Digital payment toggle.

Each option is **fits** (all checks pass, with the reason from its own
numbers) or **not yet** (the first failing check, phrased as what to do:
"Trade 4 more months", "Get 10 % of sales paid digitally"). Fits are listed
first. Amounts round down to two significant figures, so they never look
like a quote.

Gemini (Member B) could later reword the reasons; the seam is marked
`// MEMBER B` in `finance_text.dart`. Rules stay deterministic so the
explanation is always true.

## 6. UI

- Home: `MoneyHealthCard` right under the revenue hero, above Receivables.
  In / Out / Net row, up to three alerts, and a footer line "N financing
  options fit your shop".
- `/finance` screen: this week's breakdown (cash, digital, collected, credit
  given, restocks), all alerts (overdue taps through to Customers), then the
  financing list and the disclaimer.

## 7. Left to the builder / follow-ups

- Apply `supabase/migrations/0019_finance_health.sql` in the SQL editor before
  installing the build; without it the Home card stays hidden and the screen
  shows a retry message.
- Push notifications for alerts → Member C, from the same RPC.

## 9. Gemini advice on the card (added 2026-10-18)

Why: the topic says *copilot*, and the alerts and matches are plain rules.
The user asked for the smallest AI piece that answers that: a "Get advice
from EasySell AI" button on the Money health card. The bigger "Ask EasySell"
chat was **rejected for the deadline** (two days left; a chat that answers
one question wrong in a live demo costs more than no chat) and goes in the
deck as a next step.

- **Gemini never calculates.** The app sends `money-tips` the numbers it
  already shows, pre-formatted in the seller's language, plus the exact
  warning and financing sentences on screen (`money_tips_facts.dart`). The
  prompt says to copy amounts as written and never compute. So advice can't
  carry a figure the card doesn't, and can't contradict a warning.
- **Never "take this loan".** The prompt allows "could help, compare the
  lender's terms first" and forbids naming a real lender, matching §2's
  anti-goal.
- **Cost control:** Gemini is called only on a tap, never on opening Home.
  The answer is saved on the phone under a key of *day + language + every
  number sent*; the same key never calls again (survives restarts). A new
  sale changes the numbers, so the card offers to ask again instead of
  showing advice about old figures.
- Same Gemini-direct setup as scan (structured output, `thinkingLevel:
  minimal`, 800-token cap, 20 s server abort vs 30 s app timeout).
  `temperature: 0.4` for wording only, since the facts fix the content.
- **The warnings list is the only list of problems.** First on-device run:
  with no warnings, Gemini still called a 1 % week-on-week dip (৳12,754 →
  ৳12,619) "sales dropped" and suggested discounts, contradicting the card's
  "No money warnings". The prompt now says only the listed warnings are
  problems and a small change between weeks is normal; the 25 % rule (§4)
  decides, not the model.
- The tips carry a caveat line: "Based on the numbers above. Check them
  before you act."
- **Deploy:** paste `supabase/functions/money-tips/index.ts` as a new
  function `money-tips` in the Dashboard. It needs only the existing
  `GEMINI_API_KEY`. Until then the button shows "Couldn't get advice" +
  Retry; nothing else is affected.
- This is Member B's area (AI layer). Built here at the user's request;
  prompt tuning stays theirs.

## 8. Build notes (2026-10-18)

- Built in `lib/features/finance/` (domain / data / presentation), route
  `/finance`, Home card under the revenue hero. Tests: `cash_flow_alerts_test`,
  `financing_match_test`, `widgets/money_health_test` (incl. a 360 dp Bangla
  overflow check); full suite 700 green, analyzer clean.
- **The SQL has not been run against a database in this session** (the user
  applies migrations by pasting into the SQL editor). The Dart side is tested
  against hand-made rows only, so the first real check of 0019 is the device.
- Same day, on the S22 with 0019 applied: the RPC returns real numbers and both
  the card and the screen work. One fix came out of it: the card's In / Out /
  Net now use `Money.compact` (no paisa), because "৳14,870.00" ran into the
  next column. The demo shop is under 3 months old, so every financing option
  reads "Keep trading N more months"; a fitting option needs older history.

