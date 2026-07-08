# History calendar day-filter + shop-lifetime calendar floor — Design

**Date:** 2026-07-03
**Feature owner:** Member A (Flutter + Supabase)
**Status:** Approved for planning

## 1. Problem / Goal

The History tab's period control is a 3-segment `[Today | Week | All]`. The user
wants to drop **All** and instead drill into a **specific calendar date** (any
date in any year that has data) and see only that day's sales.

Separately, all three calendar affordances in the app (Home dashboard, Reports
tab, History tab) currently cap the date picker at the **past 12 months**. They
should instead let the user reach back to the **shop's first-ever sale**, so any
historical day with data is selectable everywhere.

## 2. Scope

**In scope**
- Replace History's `All` segment with the shared `CalendarDayButton` +
  `DayFilterChip` day-drill pattern already used by Home and Reports.
- A day-scoped, uncapped sales query so a picked day is always complete
  (independent of the recent-100 fetch limit).
- Make the date picker's lower bound = the shop's earliest sale date across
  **all three** calendars (Home, Reports, History).

**Out of scope**
- Any change to how Today/Week/Month windows are computed elsewhere.
- Multi-day ranges, week/month pickers, or a flat "all-time" list (the `All`
  view is intentionally removed).
- Analytics/summary numbers — this is a history-listing + picker-range change.

## 3. Approved decisions

- **Layout:** History gets a 2-segment `[Today | Week]` control with the shared
  circular `CalendarDayButton` to its right (consistent with Home & Reports).
  Picking a day deselects Today/Week, filters the table to that exact date, and
  shows a removable `DayFilterChip` beneath the control. Clearing the chip — or
  tapping Today/Week — returns to the running-window view.
- **Picker floor:** Lower bound = shop's earliest sale date (fallback: today
  when the shop has no sales yet). Applied to Home, Reports, and History.
- **Data correctness:** A picked day is fetched with a dedicated day-bounded
  query, **not** filtered client-side over the recent-100 list, so it can never
  silently miss sales.
- **`All` removed:** There is no longer a flat all-time list; browsing is by
  Today, Week, or a specific day. (User confirmed this tradeoff.)

## 4. Design

### 4.1 Shared widget — `CalendarDayButton` (core/widgets/calendar_day_button.dart)

Add an optional `firstDate` parameter:

```dart
const CalendarDayButton({
  super.key,
  required this.selectedDay,
  required this.onPick,
  this.firstDate,          // NEW — null keeps the legacy "past 1 year" floor
  this.size = 40,
});

final DateTime? firstDate;
```

In `showDatePicker`, use:

```dart
firstDate: firstDate ?? DateTime(now.year - 1, now.month, now.day),
```

The widget stays dumb (no Riverpod dependency); each call site supplies the
floor. `initialDate` remains `selectedDay ?? now`, which is always within
`[firstDate, now]` because the floor is a past-or-today date.

### 4.2 Earliest-sale source (shared provider + repo method)

**Repository** — add to `TransactionRepository`:

```dart
/// The date (local, midnight) of the shop's first recorded sale, or null if
/// the shop has no sales yet. Used to set the calendar picker's lower bound.
Future<Result<DateTime?>> earliestSaleDate({required String shopId});
```

Query: `transactions` where `shop_id = shopId AND type = 'sale'`, order
`created_at` ascending, limit 1; map the single row's `created_at` to a local
date at midnight. Empty → `null`.

**Provider** — a shop-scoped provider reachable by all three features (place in
a shared location, e.g. `lib/features/transactions/presentation/`):

```dart
/// Lower bound for every day-picker in the app. Refreshes with dataRefresh so a
/// brand-new shop's first sale opens up the calendar immediately.
final earliestSaleDateProvider = FutureProvider.autoDispose<DateTime?>((ref) async {
  ref.watch(dataRefreshProvider);
  final shopId = ref.watch(myShopProvider).value?.id;
  if (shopId == null) return null;
  final result = await ref.read(transactionRepositoryProvider)
      .earliestSaleDate(shopId: shopId);
  return result.when(success: (d) => d, failure: (_) => null);
});
```

On failure it yields `null`, so the picker safely falls back to the legacy
1-year floor rather than blocking the UI.

### 4.3 Day-scoped sales query (History correctness)

**Repository** — add to `TransactionRepository`:

```dart
/// All SALE transactions for [day] (local calendar day), newest first, with no
/// recent-N cap so a picked day is always complete.
Future<Result<List<Transaction>>> salesForDay({
  required String shopId,
  required DateTime day,
});
```

Query: `type = 'sale'`, `created_at >= startOfDay(local→UTC)` AND
`created_at < startOfNextDay(local→UTC)`, order `created_at` descending.

**Provider** — in `history_screen.dart` next to `recentSalesProvider`:

```dart
final salesForDayProvider = FutureProvider.autoDispose
    .family<List<Transaction>, DateTime>((ref, day) async {
  ref.watch(dataRefreshProvider);
  final shopId = ref.watch(myShopProvider).value?.id;
  if (shopId == null) return const [];
  final result = await ref.read(transactionRepositoryProvider)
      .salesForDay(shopId: shopId, day: day);
  return result.when(success: (l) => l, failure: (f) => throw f);
});
```

### 4.4 History screen changes (history_screen.dart)

- **State:** `_Scope` enum loses `all` → `enum _Scope { today, week }`. Default
  `_scope = _Scope.today`. Add `DateTime? _selectedDay`.
- **Source selection in `build`:** when `_selectedDay != null`, watch
  `salesForDayProvider(_selectedDay!)`; otherwise watch `recentSalesProvider`.
  Both flow through the existing `loading/error/data` `when` branches (reusing
  `_HistorySkeleton` and `_ErrorState`).
- **`_inScope`:** drops the `all` case. It is only consulted in the running-window
  path; in day-mode the fetched list is already the single day, so scope
  filtering is skipped.
- **Control:** replace the 3-segment `_ScopeSelector` with a `Row` of
  `[Expanded(2-seg Today|Week)] [SizedBox(8)] [CalendarDayButton]`. Wire
  `CalendarDayButton.firstDate` to `ref.watch(earliestSaleDateProvider).value`,
  `selectedDay` to `_selectedDay`, and `onPick` to
  `setState(() => _selectedDay = day)`.
- Tapping a Today/Week segment sets `_selectedDay = null` (mutual exclusivity).
- **Chip:** when `_selectedDay != null`, render a `DayFilterChip`
  (`DateFormat('EEE, d MMM').format(_selectedDay!)`) below the control; its
  `onClear` sets `_selectedDay = null`.
- **Empty state (day-mode):** when the selected day has zero sales, show an empty
  state message *"No sales on <formatted day>."* (a small variant/param on the
  existing `_EmptyState`).

### 4.5 Home & Reports changes

Purely wiring the new floor:

- `dashboard_screen.dart:186` — add
  `firstDate: ref.watch(earliestSaleDateProvider).value` to the existing
  `CalendarDayButton`.
- `analytics_screen.dart:313` — same one-line addition.

No behavioral change beyond the widened lower bound.

## 5. Data flow

```
Home / Reports / History
  └─ CalendarDayButton.firstDate ← earliestSaleDateProvider ← TransactionRepository.earliestSaleDate
History day-mode:
  _selectedDay set ─► salesForDayProvider(day) ─► TransactionRepository.salesForDay ─► day-bounded rows
  _selectedDay null ─► recentSalesProvider (unchanged) ─► Today/Week client filter
```

## 6. Error / edge handling

- `earliestSaleDate` failure or no sales → provider yields `null` → picker uses
  legacy 1-year floor (no crash, graceful degradation).
- `salesForDay` failure → existing `_ErrorState` with Retry (invalidate the
  provider).
- Picked day with no rows → day-mode empty state.
- `dataRefreshProvider` invalidates both new providers, so a fresh sale updates
  the calendar floor and any open day view.
- Timezone: day bounds computed from the local calendar day, converted to UTC
  for the query, matching how `_inScope` already reasons in local time.

## 7. Testing

- Unit: `salesForDay` bounds — a sale at 23:59 local of the picked day is
  included; 00:00 of the next day is excluded.
- Unit: `earliestSaleDate` returns the oldest sale's local date; null when no
  sales.
- Widget/logic: selecting a day deselects Today/Week and clears via the chip;
  tapping Today/Week clears the day.
- Reuse existing `test/sales_in_scope_test.dart` / `test/period_since_test.dart`
  patterns for the scope helper after `all` is removed.

## 8. Files touched

- `lib/core/widgets/calendar_day_button.dart` — optional `firstDate` param.
- `lib/features/transactions/data/transaction_repository.dart` —
  `earliestSaleDate`, `salesForDay`.
- `lib/features/transactions/presentation/…` — `earliestSaleDateProvider`
  (shared location).
- `lib/features/transactions/presentation/history_screen.dart` — control,
  state, providers, empty state.
- `lib/features/dashboard/presentation/dashboard_screen.dart` — pass `firstDate`.
- `lib/features/analytics/presentation/analytics_screen.dart` — pass `firstDate`.
- Tests under `test/`.
