# Dashboard day drill-down — design

**Date:** 2026-07-02
**Feature area:** Home dashboard (`lib/features/dashboard`) + analytics data layer + Supabase RPC
**Status:** Approved design, ready for implementation plan

---

## 1. Problem & goal

The home dashboard has three period pills — **Today / Week / Month** — that each show a
*cumulative period ending now* (revenue, profit, margin, items sold) via the
`get_dashboard_summary` RPC.

The shopkeeper wants to inspect the numbers for **one specific past day** (e.g. "how did
July 2 do?"), which the current period model can't express.

**Goal:** Add a calendar affordance to the dashboard that lets the user pick a single past
day and see that day's figures in place, **without removing** the existing running-period
views. Today / Week / Month stay exactly as they are.

## 2. Scope

**In scope**
- A calendar icon beside the period pills that opens a date picker.
- Picking a day swaps the revenue hero into "day-mode" showing that day's Revenue /
  Profit / Margin / Items sold, labelled with the date, with a way to clear back to the
  period view.
- A Postgres change so the day's totals are computed **server-side** (Approach B), returning
  only the finished numbers regardless of how many transactions the day has.

**Out of scope (YAGNI)**
- Arbitrary week/month picking or a start–end date-range picker (single day only).
- Changing the weekly sales bars, Top performer, or Low-stock cards — they continue to
  reflect live/recent data, not the picked day. Only the hero swaps.
- Any change to Week / Month / Today semantics.

## 3. Chosen approach: server-side day summary (Approach B)

The day's revenue/cost/profit/units are all derivable from that day's **sale transactions**
(which carry frozen prices per CLAUDE.md §4). We compute them **in Postgres** by extending
the existing `get_dashboard_summary` RPC, so:

- The payload is a handful of numbers whether the day had 5 sales or 50,000 — no large
  download, no client-side row cap (the repo's 1,000-row `recentSales` cap would otherwise
  silently under-count a very busy day).
- Aggregation stays in the database, matching CLAUDE.md §5.

### 3.1 RPC change

Extend `get_dashboard_summary` (current signature in
`supabase/migrations/0005_product_archive.sql`) with an optional day parameter:

```sql
create or replace function get_dashboard_summary(
  p_shop_id uuid,
  p_period text default 'all',
  p_day date default null            -- NEW: when set, overrides p_period with a single-day window
) returns table (
  revenue          numeric,
  cost             numeric,
  profit           numeric,
  units_sold       bigint,
  inventory_value  numeric
)
```

Behaviour:
- When `p_day IS NULL` → unchanged (period window `[v_start, now()]` as today).
- When `p_day IS NOT NULL` → window becomes `[p_day, p_day + 1 day)`:
  - `t.created_at >= p_day::timestamptz AND t.created_at < (p_day + 1)::timestamptz`
  - `p_period` is ignored.
- `inventory_value` is a *current-stock* figure and is **not meaningful for a past day**.
  Keep returning it (cheap, shape stays stable); the hero already ignores it in this view.

This is a new migration file (e.g. `0006_dashboard_summary_day.sql`), `create or replace`,
idempotent, following the existing migration style/header.

**Timezone note (known MVP limitation):** `created_at` is `timestamptz` and the existing
period logic truncates in the database session timezone. The single-day window inherits the
same behaviour — a sale near local midnight could fall on the neighbouring day if the DB
session tz differs from the shop's local tz. This matches the *existing* today/week/month
behaviour and is accepted for the MVP. Revisit with a shop-timezone column if it bites.

### 3.2 Data layer (Flutter)

- `AnalyticsRepository.getSummary` gains an optional `DateTime? day`; when non-null it passes
  `p_day` as an ISO date string (`YYYY-MM-DD`) and may pass any period (ignored server-side).
  Signature stays backwards-compatible for the existing period calls.
- New provider in `analytics_controller.dart`:
  ```dart
  final daySummaryProvider = FutureProvider.autoDispose
      .family<DashboardSummary, DateTime>((ref, day) async {
        ref.watch(dataRefreshProvider);
        final shop = ref.watch(myShopProvider).value;
        if (shop == null) return DashboardSummary.empty;
        final result = await ref.watch(analyticsRepositoryProvider)
            .getSummary(shop.id, AnalyticsPeriod.all, day: day);
        return result.when(success: (s) => s, failure: (f) => throw f);
      });
  ```
  (Family key is the date; normalize to date-only — midnight local — before use.)

## 4. UI / interaction

Location: the `Entrance(index: 1)` block on `dashboard_screen.dart` that currently holds the
`SegmentPills`.

- Add a small calendar icon button (`Icons.calendar_today_outlined`) to the **right** of the
  pills (Row: pills `Expanded`, then the icon). Keep it inside the same entrance block.
- Tapping it calls `showDatePicker`:
  - `firstDate`: shop `created_at` date (fallback: `now - 1 year`).
  - `lastDate`: today (future days disabled).
  - `initialDate`: the currently-selected day, else today.
- On pick → set `selectedDayProvider` to the chosen date (date-only).

**Day-mode hero:**
- When a day is selected, the hero renders `daySummaryProvider(selectedDay)` instead of
  `summaryProvider(_period)`.
- Label reads `Revenue · <EEE, d MMM>` (e.g. "Revenue · Wed, 2 Jul") via the existing
  `periodWord` slot — pass the formatted date string instead of the period word.
- Show Revenue / Profit / Margin / Items sold, same as the normal hero. Margin is
  `profit / revenue * 100` (same formula already in the screen).
- The daily-delta badge (`↘ 100%`) is **suppressed** in day-mode. (While here, also gate it
  so it only shows for `AnalyticsPeriod.today` as originally intended — it currently renders a
  daily delta next to Week/Month totals, which is misleading. Small, in-scope correctness fix.)
- A dismiss affordance: a `✕` chip / label (e.g. a small "×  Wed, 2 Jul" pill or an outlined
  chip near the pills) clears `selectedDayProvider` back to null → hero returns to the period
  view.

**Pill interaction:** selecting any pill (Today/Week/Month) clears `selectedDayProvider`
(`= null`) so period and day-mode are mutually exclusive and never ambiguous.

## 5. State

- New `selectedDayProvider` — `StateProvider<DateTime?>` (null = normal period view), colocated
  with the dashboard/analytics providers.
- `DashboardScreen` reads it: `selectedDay != null` → day-mode hero; else existing period hero.
- Keep `_period` local state as-is for the pills.

## 6. Components & responsibilities

| Unit | Responsibility | Depends on |
|---|---|---|
| `get_dashboard_summary` (RPC) | Compute totals for a period *or* a single day, server-side | `transactions`, `products` |
| `AnalyticsRepository.getSummary(shopId, period, {day})` | Call the RPC, map row → `DashboardSummary` | Supabase client |
| `daySummaryProvider(DateTime)` | Expose one day's summary reactively | repo, shop, refresh |
| `selectedDayProvider` | Hold the picked day (or null) | — |
| `DashboardScreen` period block | Pills + calendar icon + dismiss chip; choose which hero to render | providers above |
| `RevenueHero` | Unchanged rendering; just fed day figures + a date label | — |

## 7. Error / edge handling

- **No sales that day** → RPC returns zeros → hero shows `$0 / 0 items` for the date (valid
  "quiet day" state, not an error). Optional: a subtle "No sales on this day" caption.
- **Load error** → same `_ErrorText('Could not load summary.')` path already used by the hero.
- **Future date** → not selectable (`lastDate: today`).
- **Very busy day (thousands of sales)** → handled by design: server returns only totals.
- **Refresh / new sale** → `daySummaryProvider` watches `dataRefreshProvider`, so recording a
  sale re-fetches (though a *past* day rarely changes).

## 8. Testing

- **Unit (Dart):** a helper that normalizes a picked `DateTime` to date-only; verify the
  repo passes `p_day` as `YYYY-MM-DD` and omits/ignores it when null. Follow the existing
  `test/period_since_test.dart` style.
- **RPC (manual / SQL):** with seeded sales across two days, `get_dashboard_summary(shop,
  'all', '2026-07-02')` returns only that day's totals; `p_day => null` matches prior period
  behaviour (regression check that existing calls are unchanged).
- **Widget (optional, MVP-light):** selecting a day swaps the hero label to the date and
  clears on pill tap.

## 9. Migration / rollout

1. Add migration `0006_dashboard_summary_day.sql` (create-or-replace, idempotent). Existing
   two-arg calls keep working (new param defaults null).
2. Ship Flutter changes; the repo's new `day` param is optional so nothing else breaks.
3. No data backfill, no RLS change (same tables, same shop scoping).
