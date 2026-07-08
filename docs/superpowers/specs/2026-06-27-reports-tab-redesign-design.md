# Reports tab (Analytics) Redesign — Design Spec

**Date:** 2026-06-27
**Owner:** Member A (Flutter)
**Status:** Approved — ready for implementation
**Mockup:** `docs/superpowers/mockups/reports-redesign.html`

## 1. Problem

The Reports tab ([analytics_screen.dart](../../../lib/features/analytics/presentation/analytics_screen.dart))
is three stacked cards: a fixed 6-month revenue bar chart, a "Revenue by category" list, and a
"Best sellers · units" list. Issues:

- **No profit anywhere.** The product is profit-focused, yet Reports only ever shows revenue. The
  `seriesProvider` and `summaryProvider` both already carry profit/cost/margin — it's just unused.
- **Locked to one timeframe.** The chart is hard-wired to monthly; there's no way to look at a day
  or a week.
- **Sections disagree silently.** The chart shows "last 6 months" while the category split and best
  sellers read `recentSalesProvider` (newest 100 sales, unscoped) — a different, unlabeled timeframe.
- **No period control**, unlike Home which has Today/Week/Month pills.

## 2. Goals

Turn Reports into a coherent **business-review** surface focused on two questions — *how is the
trend?* (revenue or profit) and *what's selling?* (categories + best sellers) — scoped to a period
the user chooses, within the existing Riverpod + Material 3 architecture. One small repo query
change; no new RPCs.

## 3. Final design — "Editorial report" direction

**Design intent:** Reports must read as *its own screen*, not a second Home. Home's signature is a
brand-filled blue revenue hero + filled period pills + vertical gradient bars + avatar-tile rows.
Reports deliberately uses **none** of those. Instead it adopts an editorial/report language: a
"kicker + headline" rhythm, plain-language takeaways, a **smooth area line** (not bars), and a
**donut** (not progress bars). Same design *system* (royal-blue palette, Material 3, fonts) — a
distinct visual *voice*. Mockup: `reports-redesign.html`.

Vertical order on the Reports tab:

1. **Header** — a small uppercase kicker `BUSINESS REPORT` + the `Reports` title. No controls here.

2. **Trend card** — a **smooth area line chart** (SVG cubic path + gradient fill under the line +
   end-point dot), explicitly replacing Home's `GradientBars`. Two independent controls:
   - **Revenue / Profit** pill toggle — which metric the line plots (client-side switch; the series
     already carries both). This toggle is where profit lives on Reports. Short cross-fade.
   - **Day / Week / Month** underline toggle — chart only, independent of the period selector.
   - Header: kicker `{Revenue|Profit} trend · {granularity}`, the series total, and a `DeltaChip`
     (last bucket vs previous).

3. **Category card** — `Where revenue comes from` kicker + a **donut chart** (SVG, center shows the
   top category's share) with a **legend list** (color dot · name · %). Replaces the progress-bar
   rows. **Directly under the donut sits the period control** — `Week · Month · All` underline tabs
   (NOT Home's filled `SegmentPills`; `Today` omitted — Reports is a review surface). This selector
   scopes both the donut and the best-sellers list (§4). It lives here, beside the data it filters,
   rather than at the top of the page — the trend card has its own independent controls and is
   unaffected by it.

4. **Best sellers card** — `Biggest wins` kicker + a lede *"{top product} is carrying {period}."* +
   a **numbered rank list** (1–4) showing units and revenue per product. Rank numbers, not avatar
   tiles (those are Home's). Scoped to the period selected in the category card (§3).

> **Removed by request:** an earlier draft led with a dedicated "profit insight" card (profit figure,
> margin meter, "You kept 30¢ of every dollar" lede). It's dropped — Reports goes straight from the
> header into the trend chart. Profit/margin remain reachable via the trend chart's Revenue/Profit
> toggle.

Each card owns its `AsyncValue` states: loader (skeleton), friendly error, and a "No sales yet"
empty state.

**Implementation note:** the area-line chart and donut are new lightweight widgets drawn with
`CustomPainter` (no new chart package); they live in the analytics feature folder. `GradientBars`
stays as-is for Home.

## 4. Data & scoping

**Global period → enum.** Week / Month / All map to the existing `AnalyticsPeriod` (week, month,
all). A small `StateProvider`/`Notifier` holds the selected period for the page.

- **Category split + best sellers (§3.3, §3.4)** — currently `recentSalesProvider` (newest 100,
  unscoped). Add an optional `since` (DateTime?) param to `TransactionRepository.recentSales` →
  a `gte('created_at', since)` filter; introduce `periodSalesProvider(period)` that derives the
  `since` from the period. **The boundary must match whatever `get_dashboard_summary` uses for that
  period** (so KPIs and movers never disagree): week = last 7 days, month = current calendar month,
  all = no filter (`since = null`). If the RPC's boundaries differ, mirror the RPC, not this list.
  Keep the existing best-sellers/category aggregation client-side (CLAUDE.md §5, tiny volumes). For
  `all`, raise/remove the 100-row limit within reason.
- **Chart (§3.2)** — `seriesProvider(ChartBucket.daily | weekly | monthly)`; each `SalesPoint`
  already has `revenue` and `profit`, so the metric toggle is client-side only. No new query. The
  `summaryProvider` is no longer needed by Reports (the profit/KPI block was removed).

## 5. Formatting

Reuse the dashboard helpers in [format.dart](../../../lib/shared/extensions/format.dart):
`Money.compact` (100k threshold, no cents below it) for the chart-total money figure and best-seller
revenue, `Money.compactCount` for unit counts. Category percentages render as `{x.round()}%`. No
cents needed on this surface (a future tap-to-expand sheet could add them — out of scope).

## 6. Visuals & motion

- White rounded `Card` surfaces, generous 22px padding (roomier than Home), royal-blue accents
  (`brand = 0xFF2563EB` light / `0xFF5B9CFF` dark). **No brand-filled hero anywhere** — that's
  Home's signature.
- Editorial rhythm: every section opens with an uppercase muted **kicker** + (where it helps) a bold
  **lede sentence**. Numbers are big and ink-colored, not white-on-blue.
- **Period control:** underline text tabs, NOT `SegmentPills`. **Chart metric:** small pill toggle.
  **Granularity:** underline mini-tabs. `AppHaptics.tap()` on every change.
- **Charts are distinct from Home:** area line (`CustomPainter`, cubic-smoothed, gradient fill) for
  the trend; donut (`CustomPainter`) for category. `DeltaChip` reused for the trend delta.
- Respect `AppMotion.reduced`; subtle cross-fades only when switching period/metric — no layout jump.

## 7. Components & files

- `analytics_screen.dart` — restructure into the editorial sections (header tabs, trend, category,
  best sellers); add global-period state; new private widgets `_PeriodTabs`, `_TrendCard` (metric
  pill + granularity tabs), `_CategoryDonutCard`, `_BestSellersCard`.
- `analytics_controller.dart` — add `periodSalesProvider(period)` and the selected-period state
  provider; reuse existing `seriesProvider` / `bestSellersProvider` (`summaryProvider` no longer
  used here).
- `transaction_repository.dart` — add optional `since` param to `recentSales` (gte filter).
- New shared widgets (analytics feature folder, `CustomPainter`-based, no new package):
  `area_line_chart.dart`, `donut_chart.dart`.
- Reused unchanged: `DeltaChip`, `Money.compact/compactCount`. `GradientBars` stays Home-only.

## 8. Testing

- Unit: `periodSalesProvider` since-derivation per period; trend-delta math (last bucket vs previous)
  incl. guards (prev ≤ 0, empty/short series).
- `flutter analyze` clean, `dart format`, `flutter test` green.
- Manual: switch Week/Month/All — category + best sellers move together; chart Day/Week/Month and
  Revenue/Profit toggles work independently; empty shop shows empty states; large numbers don't
  overflow.

## 9. Out of scope

Tap-to-expand exact breakdown sheet on Reports, slow/dead-stock analysis, CSV/PDF export, custom
date ranges, profit-by-category breakdown. Captured as future work.
