# Dashboard Day Drill-Down Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the shopkeeper tap a calendar icon beside the dashboard period pills, pick a single past day, and see that day's Revenue / Profit / Margin / Items in place — without changing the Today / Week / Month views.

**Architecture:** A new optional `p_day` parameter on the existing `get_dashboard_summary` Postgres RPC computes one calendar day's totals server-side (small payload regardless of transaction volume). Flutter gains a `daySummaryProvider` and a `selectedDayProvider`; the dashboard's revenue hero renders the day summary when a day is selected and the period summary otherwise. Selecting a period pill clears the day.

**Tech Stack:** Flutter, Riverpod (`flutter_riverpod`), Supabase (`supabase_flutter`) Postgres RPC, `intl` for date formatting, `flutter_test`.

**Design spec:** `docs/superpowers/specs/2026-07-02-dashboard-day-drilldown-design.md`

---

## File Structure

| File | Change | Responsibility |
|---|---|---|
| `supabase/migrations/0006_dashboard_summary_day.sql` | Create | `create or replace get_dashboard_summary` with optional `p_day` single-day window |
| `lib/features/analytics/domain/analytics.dart` | Modify | Add `dayParam()` date-only helper (shared by data + presentation) |
| `lib/features/analytics/presentation/analytics_controller.dart` | Modify | Add `selectedDayProvider`, `daySummaryProvider` |
| `lib/features/analytics/data/analytics_repository.dart` | Modify | `getSummary` gains optional `day` param → passes `p_day` |
| `lib/features/dashboard/presentation/dashboard_screen.dart` | Modify | Calendar button beside pills, date picker, day-filter chip, day-mode hero, delta-badge fix |
| `test/day_param_test.dart` | Create | Unit test for `dayParam()` date-only formatting |

---

## Task 1: Postgres RPC — optional single-day window

**Files:**
- Create: `supabase/migrations/0006_dashboard_summary_day.sql`

This RPC is applied manually via the Supabase SQL Editor (see the header comments in the existing `supabase/migrations/0005_product_archive.sql`). There is no Dart test for SQL; verification is a SQL query in Task 1 Step 3.

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/0006_dashboard_summary_day.sql`:

```sql
-- =============================================================================
-- 0006_dashboard_summary_day.sql — optional single-day window for the summary.
-- Run AFTER 0005_product_archive.sql (Dashboard SQL Editor → paste → Run).
-- Idempotent (create or replace).
--
-- Adds p_day: when non-null, get_dashboard_summary returns totals for that single
-- calendar day [p_day, p_day + 1 day) and IGNORES p_period. When p_day is null,
-- behaviour is unchanged from 0005. Aggregation stays in the database (CLAUDE.md
-- §5). inventory_value remains a current-stock figure (unchanged).
--
-- Timezone note: the day window is interpreted in the DB session timezone, the
-- same looseness the existing today/week/month truncation already has. Accepted
-- for the MVP.
-- =============================================================================

create or replace function get_dashboard_summary(
  p_shop_id uuid,
  p_period text default 'all',
  p_day date default null
) returns table (
  revenue          numeric,
  cost             numeric,
  profit           numeric,
  units_sold       bigint,
  inventory_value  numeric
)
language plpgsql
as $$
declare
  v_start timestamptz;
  v_end   timestamptz;
begin
  if p_day is not null then
    v_start := p_day::timestamptz;
    v_end   := (p_day + 1)::timestamptz;
  else
    v_start := case lower(coalesce(p_period, 'all'))
      when 'today' then date_trunc('day', now())
      when 'week'  then date_trunc('week', now())
      when 'month' then date_trunc('month', now())
      when 'year'  then date_trunc('year', now())
      else '-infinity'::timestamptz
    end;
    v_end := 'infinity'::timestamptz;
  end if;

  return query
  select
    coalesce(sum(t.selling_price * t.quantity), 0)::numeric as revenue,
    coalesce(sum(t.buying_price * t.quantity), 0)::numeric as cost,
    coalesce(sum((t.selling_price - t.buying_price) * t.quantity), 0)::numeric as profit,
    coalesce(sum(t.quantity), 0)::bigint as units_sold,
    (
      select coalesce(sum(p.buying_price * p.quantity), 0)::numeric
      from products p
      where p.shop_id = p_shop_id
        and not p.is_archived
    ) as inventory_value
  from transactions t
  where t.shop_id = p_shop_id
    and t.type = 'sale'
    and t.created_at >= v_start
    and t.created_at < v_end;
end;
$$;
```

- [ ] **Step 2: Apply the migration**

Paste the file contents into the Supabase Dashboard → SQL Editor → Run (matching how the earlier migrations are applied). Expected: `Success. No rows returned`.

- [ ] **Step 3: Verify both modes in SQL**

In the SQL Editor, run (substitute a real shop id that has sales):

```sql
-- Single-day mode: only that day's sales.
select * from get_dashboard_summary('<shop-uuid>', 'all', '2026-07-02');
-- Period mode unchanged (p_day defaults null): matches previous behaviour.
select * from get_dashboard_summary('<shop-uuid>', 'month');
```

Expected: the first returns one row scoped to 2026-07-02 (zeros if no sales that day, not an error); the second returns the running-month totals exactly as before. Backwards-compatible: the two-argument call still works.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/0006_dashboard_summary_day.sql
git commit -m "feat(db): optional p_day single-day window in get_dashboard_summary"
```

---

## Task 2: `dayParam()` date-only helper (TDD)

**Files:**
- Modify: `lib/features/analytics/domain/analytics.dart`
- Test: `test/day_param_test.dart`

`dayParam` formats a picked `DateTime` as the `p_day` argument (`YYYY-MM-DD`) using the local Y/M/D so the string matches the calendar day the user tapped, regardless of the time component. It lives in the **domain** layer (`analytics.dart`) so both the repository (data) and providers (presentation) can use it without a cross-layer import.

- [ ] **Step 1: Write the failing test**

Create `test/day_param_test.dart`:

```dart
import 'package:ai_shopkeeper/features/analytics/domain/analytics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dayParam — YYYY-MM-DD date-only formatting', () {
    test('drops the time component', () {
      expect(dayParam(DateTime(2026, 7, 2, 14, 30)), '2026-07-02');
    });

    test('zero-pads month and day', () {
      expect(dayParam(DateTime(2026, 1, 5)), '2026-01-05');
    });

    test('handles double-digit month and day', () {
      expect(dayParam(DateTime(2026, 12, 25, 23, 59)), '2026-12-25');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/day_param_test.dart`
Expected: FAIL — `The function 'dayParam' isn't defined`.

- [ ] **Step 3: Add the helper**

In `lib/features/analytics/domain/analytics.dart`, add at the end of the file (after the `ChartBucket` enum):

```dart
/// Formats [day] as the `p_day` argument (YYYY-MM-DD, date-only) for
/// `get_dashboard_summary`. Uses local year/month/day so the string matches the
/// calendar day the user tapped, ignoring the time component.
String dayParam(DateTime day) {
  final y = day.year.toString().padLeft(4, '0');
  final m = day.month.toString().padLeft(2, '0');
  final d = day.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/day_param_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/analytics/domain/analytics.dart test/day_param_test.dart
git commit -m "feat(analytics): dayParam helper for single-day summary arg"
```

---

## Task 3: Repository — optional `day` param on `getSummary`

**Files:**
- Modify: `lib/features/analytics/data/analytics_repository.dart:18-37`

Adds an optional named `day`. When non-null, the RPC is called with `p_day`; when null, the call is byte-for-byte the same as today, so existing `getSummary(shop.id, period)` callers are unaffected. `dayParam` is already reachable via the existing `../domain/analytics.dart` import (line 9) — no new import needed.

- [ ] **Step 1: Extend `getSummary`**

Replace the `getSummary` method (lines 18-37) with:

```dart
  Future<Result<DashboardSummary>> getSummary(
    String shopId,
    AnalyticsPeriod period, {
    DateTime? day,
  }) async {
    try {
      final result = await _client.rpc(
        'get_dashboard_summary',
        params: {
          'p_shop_id': shopId,
          'p_period': period.value,
          if (day != null) 'p_day': dayParam(day),
        },
      );
      // `returns table(...)` → a list of rows; take the single row.
      final row = result is List
          ? (result.isEmpty ? const {} : result.first)
          : result;
      return Result.success(
        DashboardSummary.fromMap(Map<String, dynamic>.from(row as Map)),
      );
    } catch (e) {
      return Result.failure(_map(e));
    }
  }
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/features/analytics/data/analytics_repository.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/features/analytics/data/analytics_repository.dart
git commit -m "feat(analytics): getSummary accepts an optional single day"
```

---

## Task 4: Providers — `selectedDayProvider` and `daySummaryProvider`

**Files:**
- Modify: `lib/features/analytics/presentation/analytics_controller.dart`

Adds the day-selection state and the RPC-backed day summary. Place both directly after the existing `summaryProvider` (which ends at line 25), so the summary providers sit together.

- [ ] **Step 1: Add the providers**

In `lib/features/analytics/presentation/analytics_controller.dart`, insert after `summaryProvider` (after line 25):

```dart
/// The day the user has drilled into on the dashboard, or null for the normal
/// period view. Selecting a period pill (or the chip's clear) resets this to null.
final selectedDayProvider = StateProvider<DateTime?>((ref) => null);

/// One calendar day's summary, RPC-backed so aggregation happens server-side and
/// the payload stays small regardless of that day's transaction count (CLAUDE.md
/// §5). [day] must be date-only (midnight local). Refetches when a sale/restock
/// bumps [dataRefreshProvider].
final daySummaryProvider = FutureProvider.autoDispose
    .family<DashboardSummary, DateTime>((ref, day) async {
      ref.watch(dataRefreshProvider);
      final shop = ref.watch(myShopProvider).value;
      if (shop == null) return DashboardSummary.empty;
      final result = await ref
          .watch(analyticsRepositoryProvider)
          .getSummary(shop.id, AnalyticsPeriod.all, day: day);
      return result.when(success: (s) => s, failure: (f) => throw f);
    });
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/features/analytics/presentation/analytics_controller.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/features/analytics/presentation/analytics_controller.dart
git commit -m "feat(analytics): selectedDay + daySummary providers"
```

---

## Task 5: Dashboard UI — calendar button, day-mode hero, delta fix

**Files:**
- Modify: `lib/features/dashboard/presentation/dashboard_screen.dart`

Wires the calendar affordance and the day-mode hero. Also fixes the daily-delta badge so it only appears on the Today period (it currently renders a daily delta next to Week/Month totals — see the `↘ 100%` badge on the Month screenshot).

- [ ] **Step 1: Read the selected day in `build`**

In `lib/features/dashboard/presentation/dashboard_screen.dart`, inside `build` (currently around line 93 where `summaryAsync` is assigned), replace:

```dart
    final summaryAsync = ref.watch(summaryProvider(_period));
```

with:

```dart
    final selectedDay = ref.watch(selectedDayProvider);
    final summaryAsync = selectedDay != null
        ? ref.watch(daySummaryProvider(selectedDay))
        : ref.watch(summaryProvider(_period));
```

- [ ] **Step 2: Replace the period pills block with pills + calendar button**

Replace the `Entrance(index: 1, ...)` block (currently lines 165-173) with:

```dart
              Entrance(
                index: 1,
                child: Row(
                  children: [
                    Expanded(
                      child: SegmentPills<AnalyticsPeriod>(
                        values: _periods,
                        selected: _period,
                        labelOf: _periodWord,
                        onChanged: (p) {
                          setState(() => _period = p);
                          // Period and day-mode are mutually exclusive.
                          ref.read(selectedDayProvider.notifier).state = null;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    _CalendarButton(
                      selectedDay: selectedDay,
                      onPick: (day) =>
                          ref.read(selectedDayProvider.notifier).state = day,
                    ),
                  ],
                ),
              ),
              if (selectedDay != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _DayFilterChip(
                    label: DateFormat('EEE, d MMM').format(selectedDay),
                    onClear: () {
                      AppHaptics.tap();
                      ref.read(selectedDayProvider.notifier).state = null;
                    },
                  ),
                ),
              ],
```

- [ ] **Step 3: Render the day-mode hero + fix the delta badge**

Replace the `summaryAsync.when(... data: (s) { ... })` block (currently lines 175-203) with:

```dart
              summaryAsync.when(
                loading: () => const _SummarySkeleton(),
                error: (_, _) => const _ErrorText('Could not load summary.'),
                data: (s) {
                  final margin = s.revenue > 0
                      ? s.profit / s.revenue * 100
                      : 0.0;
                  final isDay = selectedDay != null;
                  // Daily delta is only meaningful for Today; never in day-mode.
                  final delta = (!isDay && _period == AnalyticsPeriod.today)
                      ? _revenueDelta(seriesAsync.value)
                      : null;
                  final label = isDay
                      ? DateFormat('EEE, d MMM').format(selectedDay)
                      : _periodWord(_period);
                  return Entrance(
                    index: 2,
                    child: RevenueHero(
                      revenue: s.revenue,
                      profit: s.profit,
                      marginPercent: margin,
                      unitsSold: s.unitsSold,
                      currency: currency,
                      periodWord: label,
                      deltaPercent: delta,
                      showDeltaSuffix: !isDay && _period == AnalyticsPeriod.today,
                      onTap: () => showSummaryBreakdownSheet(
                        context,
                        summary: s,
                        period: _period,
                        currency: currency,
                      ),
                    ),
                  );
                },
              ),
```

- [ ] **Step 4: Add the `_CalendarButton` and `_DayFilterChip` widgets**

At the end of `lib/features/dashboard/presentation/dashboard_screen.dart` (after the `_ErrorText` class), add:

```dart
/// Circular calendar affordance beside the period pills. Opens a date picker
/// bounded to the past year through today; a picked day is reported via [onPick].
/// Fills with the brand color while a day is active.
class _CalendarButton extends StatelessWidget {
  const _CalendarButton({required this.selectedDay, required this.onPick});

  final DateTime? selectedDay;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = selectedDay != null;
    return InkResponse(
      onTap: () async {
        AppHaptics.tap();
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: selectedDay ?? now,
          firstDate: DateTime(now.year - 1, now.month, now.day),
          lastDate: now,
        );
        if (picked != null) {
          onPick(DateTime(picked.year, picked.month, picked.day));
        }
      },
      radius: 24,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: active ? theme.colorScheme.primary : theme.colorScheme.surface,
          shape: BoxShape.circle,
          border: Border.all(
            color: active
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
          ),
        ),
        child: Icon(
          Icons.calendar_today_outlined,
          size: 18,
          color: active
              ? theme.colorScheme.onPrimary
              : theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// Dismissible chip naming the drilled-into day; its delete action clears the
/// day filter back to the running-period view.
class _DayFilterChip extends StatelessWidget {
  const _DayFilterChip({required this.label, required this.onClear});

  final String label;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return InputChip(
      label: Text(label),
      onDeleted: onClear,
      deleteIcon: const Icon(Icons.close_rounded, size: 16),
    );
  }
}
```

- [ ] **Step 5: Verify it compiles**

Run: `flutter analyze lib/features/dashboard/presentation/dashboard_screen.dart`
Expected: `No issues found!` (`DateFormat`, `AppHaptics`, `SegmentPills`, `AnalyticsPeriod`, `RevenueHero`, `showSummaryBreakdownSheet` are all already imported in this file.)

- [ ] **Step 6: Commit**

```bash
git add lib/features/dashboard/presentation/dashboard_screen.dart
git commit -m "feat(dashboard): calendar day drill-down + Today-only delta badge"
```

---

## Task 6: Full verification

**Files:** none (verification only)

- [ ] **Step 1: Run the whole test suite**

Run: `flutter test`
Expected: all tests pass, including `test/day_param_test.dart` and the existing `test/period_since_test.dart`.

- [ ] **Step 2: Analyze the whole project**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Manual smoke test (device/emulator)**

Run the app (`flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`) and confirm on the Home screen:
1. Today / Week / Month still show running-period totals; the `↘ 100%` badge now appears only on Today (not Week/Month).
2. The calendar icon sits to the right of the pills.
3. Tapping it opens a date picker with future days disabled.
4. Picking a past day: the hero label becomes e.g. `Revenue · Wed, 2 Jul`, figures reflect that day (or `$0 / 0 items` on a quiet day), and no delta badge shows.
5. A chip with the date appears under the pills; tapping its ✕ returns to the period view.
6. Tapping any pill while a day is selected clears the day and restores the period totals.

- [ ] **Step 4: Final commit (if any lint/format fixups were needed)**

```bash
dart format lib/features/dashboard/presentation/dashboard_screen.dart lib/features/analytics/presentation/analytics_controller.dart lib/features/analytics/data/analytics_repository.dart test/day_param_test.dart
git add -A
git commit -m "chore: format day drill-down changes"
```

---

## Notes / known limitations (accepted for MVP)

- **Timezone:** the single-day window is interpreted in the DB session timezone, matching the existing today/week/month behaviour. A sale near local midnight could land on the neighbouring day. Revisit with a shop-timezone column if it becomes a problem.
- **Breakdown sheet in day-mode:** tapping the hero still opens `showSummaryBreakdownSheet` with the exact figures of the selected day (numbers are correct), but its header uses `_period` for labelling, so it may read "This month". The figures are right; only the label is period-worded. Left as-is to keep scope tight — a follow-up can thread the day label through the sheet.
- **Other cards unchanged:** weekly bars, Top performer, and Low-stock continue to reflect live/recent data, not the picked day (by design — only the hero swaps).
```
