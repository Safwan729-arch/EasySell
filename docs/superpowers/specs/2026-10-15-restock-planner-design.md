# Restock planner — design

Status: built 2026-10-15 (migration 0017). Plan: [[2026-10-15-restock-planner|Plan]].

## 1. Problem

A shopkeeper we interviewed restocks by looking at **last week's best seller**.
Weekly demand moves around, so this costs him money in two ways:

- **He overbuys the product that just peaked.** One strong week is taken as the
  new normal. The next week it sells less, and the extra stock sits on the
  shelf, which is cash tied up and, for dated goods, a risk of expiry.
- **He underbuys the product that is picking up.** It wasn't last week's top
  seller, so he restocks it lightly, and it runs out mid-week. Those are lost
  sales.

**Goal:** the app tells him **what to restock and how much**, from the sales it
already records, with no extra typing.

**Success:** after one restock cycle, the products that run out are the ones
the list warned about, and the suggested amounts are not inflated by one spike
week.

## 2. Approach (and what was ruled out)

**Chosen:** a rule-based planner.
- It works out a smoothed sales speed per product from the last four weeks.
- From that it shows days of stock left and a buy suggestion.
- Postgres does the aggregation (CLAUDE.md §5 and §10). The arithmetic on top is
  pure Dart, so it can be tested.

**Ruled out:**
- **Gemini forecasting.** It's a black box. A shopkeeper trusts "you sell about
  6 a day, you have 8" because he can check it. It also costs money per call,
  and the AI layer belongs to Member B. An AI "explain this" note may sit on top
  later.
- **Low-stock alerts only** (the existing reorder threshold). A threshold says
  "you are low" but not how many to buy, so it can't stop the overbuying half of
  the problem. It stays as it is, beside the planner.
- **Per-supplier schedules** (Pepsi comes Tuesday, Unilever Friday). This is
  more accurate, but it needs setup per product that few shopkeepers would do.
  It's deferred.

## 3. The rule

All dates are the **phone's local days**. The phone sends today's date and its
UTC offset. The server's `current_date` is UTC, which in Bangladesh is still
"yesterday" until 6 AM. That is the same trap 0011 avoided for `received_on`.

### 3.1 Window

- The window is the **28 full days ending yesterday**. Today is left out
  because it's partial: at 9 AM it would drag every speed down.
- **Week 0** is the 7 days ending yesterday, **week 1** the 7 before, and so on
  to **week 3**.

### 3.2 In-stock days

A day counts only if the product **could be sold** that day: its stock at the
start of the day was above zero, **or** it sold something that day.

- **Why this matters most:** if Pepsi sold out on Wednesday, Thursday to
  Saturday show zero sales because the shelf was empty, not because nobody
  wanted it. Counting those days makes the product look slow, which is exactly
  the mistake the shopkeeper makes today.
- **Start-of-day stock is rebuilt backwards** from current stock:
  `stock_at_start(d) = products.quantity − Σ net change of transactions at or
  after the start of d`.
  - Net change is `restock +q`, `sale −q` and `adjustment −q`. Every
    `adjustment` is a removal (0011, 0013, 0014, 0015), and its quantity is
    positive.
- **Days before the product's `created_at` never count.** A product created
  with opening stock has no restock row for it, so the rebuild would show that
  stock as present before the product existed.
- **Gotcha:** before commit 310bd5d, stock could be edited by hand with no
  transaction row. For products edited that way, the rebuilt history is off by
  the edit. The rebuild is clamped at zero, and the error fades out of the
  28-day window over time. This is accepted.

### 3.3 Speed

- For each week `w`, the rate is `rate_w = units sold in w ÷ in-stock days in
  w`. A week with no in-stock days has no rate.
- **Speed** is the weighted average of the weeks that have a rate:

  | week 0 | week 1 | week 2 | week 3 |
  |---|---|---|---|
  | 0.4 | 0.3 | 0.2 | 0.1 |

  The weights are renormalised over the weeks present, so a two-week-old
  product uses weeks 0 and 1 at 0.4/0.7 and 0.3/0.7.
- Units are `quantity` on `sale` rows only.
- **No sales in the 28 days means speed 0**, and the product is not planned
  (§3.5).

### 3.4 Per product

- **Good stock** is the product's stock minus its expired units. It comes from
  the existing estimate (`goodStockOf`), so expired units never count as
  sellable.
- **Days left** = `good stock ÷ speed`.
- **Trend arrow:**
  - **↑** if `rate_0 > 1.2 × speed`.
  - **↓** if `rate_0 < 0.8 × speed`.
  - **None** otherwise, or when week 0 has no rate.
- **Suggestion** = `speed × (restock days + 2) − good stock`, **rounded up** to
  a whole unit.
  - Restock days is the setting in §4.3. **2 is the buffer**, which covers a
    late restock trip.
  - The suggestion is at most 0 when there's enough stock, and then it shows as
    nothing to buy.

### 3.5 Lists

- **Buy now:** products whose suggestion is 1 or more, ordered by days left
  (soonest first). Ties are broken by name.
- **Enough for now:** every other product with speed above 0, also ordered by
  days left.
- **Left out:**
  - archived products,
  - products with speed 0, because with no sales in 4 weeks there's nothing to
    plan from. A "slow sellers" section is deferred.

### 3.6 Worked example (restocks every 7 days)

- **Pepsi** sold 70 two weeks ago and 20 last week, and was in stock every day.
  - Its rates are 2.9/day (week 0) and 10/day (week 1), plus weeks 2 and 3
    (say 4/day each).
  - Its speed is about 0.4×2.9 + 0.3×10 + 0.2×4 + 0.1×4 ≈ 5.4/day.
  - With 15 in stock: buy `ceil(5.4 × 9 − 15)` = **34**, not 70. Arrow ↓.
- **Mojo** sold 8/day last week, with a speed of 5/day and 10 in stock.
  - Days left: 2. Buy `ceil(5 × 9 − 10)` = **35**. Arrow ↑. It sits at the top
    of the list in red.

## 4. Screens

### 4.1 Home card: "Restock soon"

- It shows only when **Buy now** is not empty.
- It reads "3 items to restock" and names the top two with days left
  ("Mojo · 2 days, Pepsi · 3 days").
- Tapping it opens the Restock list.

### 4.2 Restock list

It is reachable from the Home card and from Inventory (an app-bar action).

**Each row shows:**
- the name and the trend arrow,
- "Runs out in N days", in red at 2 days or less and amber otherwise. Under
  1 day it reads "Runs out today".
- "Buy about N {unit}",
- "{stock} in stock".

**Layout and behaviour:**
- **Buy now** comes first. **Enough for now** is a collapsed section below it,
  without the buy line.
- Tapping a Buy-now row opens the **existing restock sheet**
  (`transaction_confirmation_sheet`, `initialQuantity`) with the suggestion
  filled in. The restock itself is unchanged: `record_restock`, with an expiry
  date if he gives one.
- **Empty state:** "Nothing to restock yet. Suggestions appear after a few days
  of sales."

### 4.3 Setting: "I restock every __ days"

- The range is 1–30 and the default is 7.
- It's phone-local in SharedPreferences, like `ExpiryPrefs`, and sits in
  Settings next to the expiry warning.
- **Why one number:** it fits a weekly market trip and still serves someone who
  restocks every 3–4 days.

### 4.4 Language

All new strings get Bengali and English entries, as the ARB files require.

## 5. Architecture

### 5.1 Database: migration `0017_restock_speeds.sql`

```
get_restock_speeds(p_shop_id uuid, p_today date, p_utc_offset_minutes int)
  returns table(product_id uuid, speed numeric, week0_rate numeric)
```

- It's read-only. RLS applies, because the function is not `security definer`.
- It returns only products with speed above 0, excluding archived products.
- The local day of a row is
  `(created_at + make_interval(mins => p_utc_offset_minutes))::date`.
- **Overload note** (the 0006/0009/0010 trap): it drops any earlier signature
  first.

### 5.2 App (feature `restock`, following `data/domain/presentation`)

- **`data/restock_repository.dart`** calls the RPC and maps rows to
  `RestockSpeed`, returning `Result<T>` as usual.
- **`domain/restock_plan.dart`** holds the pure functions:
  - `planRestock(products, speeds, goodStock, restockDays)` returns
    `RestockPlan(buyNow, enough)`.
  - It covers days left, the arrow, the suggestion (rounded up), ordering and
    filtering.
  - All of §3.4 and §3.5 lives here and is unit-tested.
- **`presentation/`** holds:
  - `restockPlanProvider`. It watches the speeds, `productsStreamProvider`,
    `goodStockProvider` and the setting, and refetches on `dataRefreshProvider`.
  - The Home card, the list screen, the route and the setting row.

**The split:** speed needs the transaction history, so it's computed in
Postgres. Days left and the suggestion need good stock, which is the app's own
estimate, so they're computed in Dart.

## 6. Edge cases

| Case | Behaviour |
|---|---|
| Product created 3 days ago | Week 0 has 3 in-stock days. Only week 0 counts (weight renormalised to 1). |
| Sold out on day 2 of week 0, still empty | Days 3–7 don't count, so the speed stays high and the product sits at the top with "Runs out today". |
| Good stock 0 | Days left 0, "Runs out today", and the suggestion covers the full period. |
| All stock expired | Good stock is 0, so the same as above. Expired units are never planned as sellable. |
| Decimal units (kg) | Days left uses decimals. The suggestion is rounded up to a whole kg. |
| Restock or sale made, list open | It refreshes through `dataRefreshProvider`, the same as the dashboard. |
| Offline / RPC fails | The list shows the shared error state with retry, and the Home card hides. |
| 0017 not yet run | The RPC is missing, so the card is hidden and the list shows the error state. Nothing else breaks. |

## 7. Out of scope (deferred)

- Sharing the buy list on WhatsApp.
- A slow-sellers section.
- Per-supplier visit days.
- Seasonality and festivals (Eid).
- AI explanations.
- Using `analytics_daily`.

## 8. Testing

- **Dart unit tests for `planRestock`:**
  - the suggestion formula and rounding,
  - the arrow thresholds,
  - days left with zero good stock,
  - ordering and ties,
  - exclusion of speed 0,
  - the Buy-now / Enough split at a suggestion of exactly 1,
  - decimal units.
- **Widget tests:**
  - the Home card hides when Buy now is empty,
  - the row text,
  - tapping a row opens the restock sheet with the suggestion.
- **The SQL rule has no automated test**, because the repo has no Postgres
  harness. A verification query, with a hand-built expected answer for one
  product, goes with the migration so the speed can be checked against real
  data.

## 9. Build notes (2026-10-15)

### Decisions made during the build

- **Restock-days picker:** it offers the presets 1, 2, 3, 5, 7, 10, 14 and
  30, the same style as the expiry warn-days picker, rather than any number
  from 1 to 30. `set()` clamps any value to 1–30.
- **0017 has no automated test,** because the repo has no Postgres harness.
  It's checked by the hand query at the end of the migration. The final
  reviewer traced it on paper:
  - sold-out days are skipped,
  - days before `created_at` are dropped,
  - 23:30 Bangladesh time stays on the same local day.
- **Fixed after the final review:**
  - **No automatic retry on the speeds provider.** Riverpod's default retried
    for about 40 s and reported "loading" meanwhile, so a missing 0017 or no
    internet showed a spinner instead of the error.
  - **The plan keeps the last speeds while new ones load.** `whenData` dropped
    the previous value on reload, so every restock blanked the list and the
    Home card.
  - **0017 rebuilds start-of-day stock as a running sum** (`sum(...) over
    (partition by product order by day desc)`) and reads only transactions
    from the last 30 days. The first version ran a correlated subquery per
    product per day. The reviewer estimated that at seconds for a shop with
    hundreds of products, re-run after every sale. This fix has no test, for
    the same reason as above.

### Known limitations (left as they are, for now)

- **Expired units count as in-stock days.** The SQL works from raw stock, so
  a shelf holding only expired units that haven't been removed counts as an
  in-stock day with no sales. That slightly lowers the speed.
- **A product's creation day counts as a full in-stock day,** even if it was
  added in the evening.
- **The red colour and the text can disagree.** Red uses `daysLeft ≤ 2`, but
  the text rounds down, so 2.5 days reads "2 days" in amber.
- **English singulars are missing** ("1 days", "1 items"). Bengali is
  unaffected.
- **While the product list is loading or has failed,** the Restock list says
  "Nothing to restock yet" instead of a spinner or the error.
- **Any change to the shop record refetches the speeds,** including an auth
  token refresh, because the provider watches the whole shop value.
- **Retry gives no immediate feedback.** Nothing changes on screen until the
  result arrives.
- **The 0017 verify query has two problems.** Its product-name filter isn't
  limited to one shop, and it uses the server's UTC `current_date`.
