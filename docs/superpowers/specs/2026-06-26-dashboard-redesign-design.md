# Dashboard (Home tab) Redesign — Design Spec

**Date:** 2026-06-26
**Owner:** Member A (Flutter)
**Status:** Approved — ready for implementation
**Mockups:** `docs/superpowers/mockups/dashboard-full-idea.html` (+ supporting comparison files)

## 1. Problem

The Home tab is opened 50–100×/day while serving customers, yet it was built as a
finance-monitoring dashboard, not a working surface. Specific issues found in the current
[dashboard_screen.dart](../../../lib/features/dashboard/presentation/dashboard_screen.dart):

- The largest element is the greeting ("Hi, {name}"), the least useful information.
- A 2×2 metric grid (Revenue / Profit / Sales / Low stock) spreads four KPIs across four
  cards; "Low stock" is duplicated as both a count card and a full list below.
- The period pills (Today/Week/Month) drive only the grid; the chart, top performer and
  low-stock list ignore them, so a "Month" selection sits above a "this week" chart.
- "Sales" ambiguously labels unit count.
- No sale-entry point exists anywhere on the shell.

## 2. Goals

Make Home scannable in 2–3 seconds, money-first, and resilient to large numbers, while
staying within the existing Riverpod + Material 3 architecture. No backend/RPC changes.

## 3. Final design

Vertical order on the Home tab:

1. **Greeting (demoted).** A thin line: shop name (bold, ~titleMedium) + date below
   (bodySmall, muted). The big "Hi, {name}" is removed. Bell + settings icons unchanged.
2. **Period pills** (Today/Week/Month) — unchanged control.
3. **Revenue hero** (new) — a brand-filled card replacing the entire 2×2 grid:
   - Label `Revenue · {Today|Week|Month}` (mirrors the active pill).
   - Big revenue value (compact-formatted, see §4), auto-shrinking so it never overflows.
   - A day-over-day delta chip (existing `_revenueDelta` logic); the "vs yesterday"
     suffix shows only for the Today period.
   - A 3-up split row — **Profit · Margin · Items sold** — each column `Expanded`,
     single-line, compact-formatted.
   - A small "EXACT ⤢" chip top-right signalling tappability.
   - **Tapping the card** opens the breakdown sheet (§5).
4. **Sales chart** — existing weekly bar card, relabelled `Sales · last 7 days` so it no
   longer contradicts the period pills.
5. **Top performer** — existing card, unchanged.
6. **Low stock** — existing list card, unchanged. (The duplicate count card is gone with
   the grid.)
7. **Sell FAB** — `FloatingActionButton.extended` ("＋ Sell"), bottom-right, on the Home
   Scaffold only. Tapping navigates to the Items tab (`context.go('/inventory')`); the
   existing product → detail → Record-sale flow continues from there. (Chosen as the
   low-cost option; no new product-picker is built in this task.)

The clean 4-tab bottom nav (Home / Items / Reports / History) is unchanged — no center
button.

## 4. Number formatting — "Conservative" compact

New helpers in [format.dart](../../../lib/shared/extensions/format.dart). **Single threshold:
100,000.**

| Raw | Money | Count |
|---|---|---|
| < 100,000 | full, no cents (`$1,284`, `$430`) | full (`86`, `12,480`) |
| 100,000 – 999,999 | `$452K` | `250K` |
| ≥ 1,000,000 | `$1.28M` (2 dp; 1 dp at ≥ 10M) | `1.28M` |

- `Money.compact(amount, {currencyCode})` — money, rule above, no decimals below threshold.
- `Money.compactCount(count)` — integer counts, same thresholds.
- Margin is never compacted: `{x.toStringAsFixed(1)}%`.
- Safety net: every hero value is wrapped in `FittedBox(fit: scaleDown)` + `maxLines: 1`,
  so even an unusual value shrinks instead of overflowing.
- `Money.format` (with cents) is unchanged and used by the breakdown sheet.

## 5. Exact-breakdown bottom sheet

`showSummaryBreakdownSheet(context, summary, period, currency)` — a `showModalBottomSheet`
(drag handle, matching restock/confirmation sheets). Rows use **full precision with cents**
from the already-loaded `DashboardSummary` (no new data):

- Revenue — `Money.format` (big)
- Cost of goods — `summary.cost`
- Gross profit — `summary.profit` (green, big)
- Margin — `profit / revenue * 100`
- Items sold — `summary.unitsSold`
- Avg item price — `revenue / unitsSold` (guard divide-by-zero)
- Footer button **"View full report"** → `context.go('/analytics')` then close.

> Note: "Orders" / "Avg order value" from the mockup are **not** included — the summary
> RPC returns units, not transaction count. Adding them would require a new field on
> `get_dashboard_summary`; deferred as a future enhancement.

## 6. Components & files

- `lib/shared/extensions/format.dart` — add `compact`, `compactCount` (+ unit tests).
- `lib/features/dashboard/presentation/dashboard_screen.dart` — replace grid with hero;
  demote greeting; relabel chart; add FAB; wire breakdown sheet.
- `lib/features/dashboard/presentation/revenue_hero.dart` — new hero widget.
- `lib/features/dashboard/presentation/summary_breakdown_sheet.dart` — new sheet.
- `lib/features/dashboard/presentation/profit_card.dart` — **delete** (orphaned).
- `MetricCard`, `DeltaChip` — unchanged (still used by analytics / hero).

## 7. Testing

- Unit tests for `Money.compact` / `compactCount` at the boundaries: 430, 1,284, 99,999,
  100,000, 452,180, 999,999, 1,284,500, 19,260,000, and negatives.
- `flutter analyze` clean, `dart format`, `flutter test` green.
- Manual: hero renders Today/Week/Month; tap opens sheet with exact figures; FAB lands on
  Items; large-number period does not overflow.

## 8. Out of scope

Product-picker quick-sale, transaction-count metrics, expiry tracking, recent-transactions
peek, customizable cards. Captured as future work.
