# History Calendar Day-Filter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the History tab's `All` segment with a calendar day-drill, and let every in-app date picker (Home, Reports, History) reach back to the shop's first-ever sale.

**Architecture:** History gains the shared `CalendarDayButton` + `DayFilterChip` day-drill (already used by Home/Reports). A picked day is fetched with a dedicated, uncapped, day-bounded Supabase query (not filtered over the recent-100 list). A shared `earliestSaleDateProvider` supplies the picker's lower bound to all three calendars via a new optional `firstDate` parameter on `CalendarDayButton`.

**Tech Stack:** Flutter, Riverpod (`flutter_riverpod`), `supabase_flutter`, `intl` (`DateFormat`), `flutter_test`.

**Branch:** `feat/history-calendar-day-filter` (already checked out; spec already committed).

---

## File Structure

- **Create** `lib/features/transactions/data/day_range.dart` — pure helper computing the UTC half-open range for a local calendar day (query bounds). One responsibility, unit-testable without a network.
- **Create** `lib/features/transactions/presentation/sales_providers.dart` — cross-feature Riverpod providers: `earliestSaleDateProvider` (picker floor) and `salesForDayProvider` (day-scoped list). Lives outside `history_screen.dart` so Home/Reports can import it without depending on History.
- **Create** `test/day_range_test.dart` — unit tests for `dayRangeUtc`.
- **Modify** `lib/features/transactions/data/transaction_repository.dart` — add `salesForDay` and `earliestSaleDate`.
- **Modify** `lib/core/widgets/calendar_day_button.dart` — add optional `firstDate`.
- **Modify** `lib/features/transactions/presentation/history_screen.dart` — 2-segment control + calendar button + chip + day-mode data source + day-specific empty state; drop `_Scope.all`.
- **Modify** `lib/features/dashboard/presentation/dashboard_screen.dart` — pass `firstDate`.
- **Modify** `lib/features/analytics/presentation/analytics_screen.dart` — pass `firstDate`.

---

## Task 1: Day-range helper (TDD)

**Files:**
- Create: `lib/features/transactions/data/day_range.dart`
- Test: `test/day_range_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/day_range_test.dart`:

```dart
import 'package:ai_shopkeeper/features/transactions/data/day_range.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dayRangeUtc — local calendar day to UTC half-open range', () {
    final range = dayRangeUtc(DateTime(2026, 6, 20));

    test('start is local midnight of the day', () {
      expect(range.startUtc, DateTime(2026, 6, 20).toUtc());
    });

    test('end is local midnight of the next day', () {
      expect(range.endUtc, DateTime(2026, 6, 21).toUtc());
    });

    test('a sale at 23:59:59 local sits inside the range', () {
      final at = DateTime(2026, 6, 20, 23, 59, 59).toUtc();
      expect(!at.isBefore(range.startUtc) && at.isBefore(range.endUtc), isTrue);
    });

    test('midnight of the next day is excluded (half-open)', () {
      final at = DateTime(2026, 6, 21).toUtc();
      expect(at.isBefore(range.endUtc), isFalse);
    });

    test('ignores the time component of the input day', () {
      final withTime = dayRangeUtc(DateTime(2026, 6, 20, 17, 45));
      expect(withTime.startUtc, range.startUtc);
      expect(withTime.endUtc, range.endUtc);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/day_range_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'ai_shopkeeper' ... day_range.dart` / `dayRangeUtc` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `lib/features/transactions/data/day_range.dart`:

```dart
/// The UTC half-open range `[startUtc, endUtc)` that covers the local calendar
/// day of [day]. The time component of [day] is ignored. Used to bound a
/// "sales on this day" query so it can never leak into an adjacent day.
({DateTime startUtc, DateTime endUtc}) dayRangeUtc(DateTime day) {
  final startLocal = DateTime(day.year, day.month, day.day);
  final endLocal = startLocal.add(const Duration(days: 1));
  return (startUtc: startLocal.toUtc(), endUtc: endLocal.toUtc());
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/day_range_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/transactions/data/day_range.dart test/day_range_test.dart
git commit -m "feat(transactions): dayRangeUtc helper for day-bounded queries"
```

---

## Task 2: Repository methods `salesForDay` + `earliestSaleDate`

**Files:**
- Modify: `lib/features/transactions/data/transaction_repository.dart`

No unit test: these are thin Supabase queries and the codebase has no repository/network mocking harness (existing tests cover only pure helpers). Correctness of the day bounds is covered by Task 1; these methods are verified by `flutter analyze` and the manual run in Task 7.

- [ ] **Step 1: Add the `day_range.dart` import**

At the top of `transaction_repository.dart`, add to the relative-import group (after `import '../domain/transaction.dart';`):

```dart
import 'day_range.dart';
```

- [ ] **Step 2: Add both methods after `recentSales`**

Insert directly after the closing brace of `recentSales(...)` (currently ends at line ~67, before `_callRpc`):

```dart
  /// All SALE transactions on [day] (the shopper's local calendar day), newest
  /// first. Unlike [recentSales] there is NO recent-N cap, so a drilled-into
  /// past day is always complete regardless of how many newer sales exist.
  Future<Result<List<Transaction>>> salesForDay({
    required String shopId,
    required DateTime day,
  }) async {
    try {
      final range = dayRangeUtc(day);
      final rows = await _client
          .from('transactions')
          .select()
          .eq('shop_id', shopId)
          .eq('type', 'sale')
          .gte('created_at', range.startUtc.toIso8601String())
          .lt('created_at', range.endUtc.toIso8601String())
          .order('created_at', ascending: false);
      final list = (rows as List)
          .map((r) => Transaction.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
      return Result.success(list);
    } catch (e) {
      return Result.failure(_map(e));
    }
  }

  /// The local calendar date of the shop's first-ever sale, or null when the
  /// shop has no sales yet. Backs the lower bound of every in-app date picker.
  Future<Result<DateTime?>> earliestSaleDate({required String shopId}) async {
    try {
      final rows = await _client
          .from('transactions')
          .select('created_at')
          .eq('shop_id', shopId)
          .eq('type', 'sale')
          .order('created_at', ascending: true)
          .limit(1);
      final list = rows as List;
      if (list.isEmpty) return const Result.success(null);
      final raw = (list.first as Map)['created_at'] as String;
      final local = DateTime.parse(raw).toLocal();
      return Result.success(DateTime(local.year, local.month, local.day));
    } catch (e) {
      return Result.failure(_map(e));
    }
  }
```

- [ ] **Step 3: Verify it compiles**

Run: `flutter analyze lib/features/transactions/data/transaction_repository.dart`
Expected: No errors (info/warnings unrelated to these lines are acceptable).

- [ ] **Step 4: Commit**

```bash
git add lib/features/transactions/data/transaction_repository.dart
git commit -m "feat(transactions): salesForDay + earliestSaleDate repo queries"
```

---

## Task 3: Shared providers (`earliestSaleDateProvider`, `salesForDayProvider`)

**Files:**
- Create: `lib/features/transactions/presentation/sales_providers.dart`

- [ ] **Step 1: Create the providers file**

Create `lib/features/transactions/presentation/sales_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/refresh_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../data/transaction_repository.dart';
import '../domain/transaction.dart';

/// Lower bound for every in-app date picker: the shop's first-ever sale date
/// (local calendar day), or null when the shop has no sales yet — in which case
/// pickers fall back to their legacy floor. Refreshes with [dataRefreshProvider]
/// so the first sale of a brand-new shop opens the calendar immediately.
final earliestSaleDateProvider = FutureProvider.autoDispose<DateTime?>((
  ref,
) async {
  ref.watch(dataRefreshProvider);
  final shopId = ref.watch(myShopProvider).value?.id;
  if (shopId == null) return null;
  final result = await ref
      .read(transactionRepositoryProvider)
      .earliestSaleDate(shopId: shopId);
  return result.when(success: (d) => d, failure: (_) => null);
});

/// All SALE transactions on a specific local calendar [day], newest first and
/// uncapped, so drilling into a past day in History is always complete.
final salesForDayProvider = FutureProvider.autoDispose
    .family<List<Transaction>, DateTime>((ref, day) async {
      ref.watch(dataRefreshProvider);
      final shopId = ref.watch(myShopProvider).value?.id;
      if (shopId == null) return const <Transaction>[];
      final result = await ref
          .read(transactionRepositoryProvider)
          .salesForDay(shopId: shopId, day: day);
      return result.when(success: (l) => l, failure: (f) => throw f);
    });
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/features/transactions/presentation/sales_providers.dart`
Expected: No errors. (If `myShopProvider` is not found, confirm its export in `lib/features/auth/data/auth_repository.dart` — `history_screen.dart` imports it from there.)

- [ ] **Step 3: Commit**

```bash
git add lib/features/transactions/presentation/sales_providers.dart
git commit -m "feat(transactions): shared earliestSaleDate + salesForDay providers"
```

---

## Task 4: `CalendarDayButton` gains an optional `firstDate`

**Files:**
- Modify: `lib/core/widgets/calendar_day_button.dart`

- [ ] **Step 1: Add the `firstDate` field to the constructor**

Replace the constructor (lines ~10-15) and the field declarations block so it reads:

```dart
  const CalendarDayButton({
    super.key,
    required this.selectedDay,
    required this.onPick,
    this.firstDate,
    this.size = 40,
  });

  final DateTime? selectedDay;
  final ValueChanged<DateTime> onPick;

  /// Lower bound of the picker. When null, defaults to one year before today
  /// (legacy behavior). Callers pass the shop's earliest sale date so the whole
  /// sales history is reachable.
  final DateTime? firstDate;

  /// Diameter of the circular button. Icon and tap radius scale with it so the
  /// Reports card can use a slightly smaller button than the dashboard header.
  final double size;
```

- [ ] **Step 2: Use `firstDate` in `showDatePicker`**

Replace the existing `firstDate:` argument line (currently `firstDate: DateTime(now.year - 1, now.month, now.day),`) with:

```dart
          firstDate: firstDate ?? DateTime(now.year - 1, now.month, now.day),
```

- [ ] **Step 3: Verify it compiles**

Run: `flutter analyze lib/core/widgets/calendar_day_button.dart`
Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add lib/core/widgets/calendar_day_button.dart
git commit -m "feat(widgets): optional firstDate on CalendarDayButton"
```

---

## Task 5: History screen — day-drill replaces `All`

**Files:**
- Modify: `lib/features/transactions/presentation/history_screen.dart`

This task edits several regions of one file. Apply the sub-steps in order, then verify once.

- [ ] **Step 1: Add imports**

At the top of the file, add to the relative-import group (after `import '../domain/transaction.dart';`) and the package group:

```dart
import 'package:intl/intl.dart';
```
```dart
import '../../../core/widgets/calendar_day_button.dart';
import 'sales_providers.dart';
```

(Keep imports grouped/sorted the way the file already is; `package:intl` goes with the other `package:` imports.)

- [ ] **Step 2: Shrink the `_Scope` enum**

Replace:

```dart
enum _Scope { today, week, all }
```

with:

```dart
enum _Scope { today, week }
```

- [ ] **Step 3: Update state fields**

Replace:

```dart
  _Scope _scope = _Scope.all;
```

with:

```dart
  _Scope _scope = _Scope.today;
  DateTime? _selectedDay;
```

- [ ] **Step 4: Update `_inScope`**

Replace the whole `_inScope` method with (drops the `all` case; short-circuits in day-mode since the fetched list is already the single day):

```dart
  bool _inScope(DateTime? createdAt) {
    if (_selectedDay != null) return true; // day-mode: list is already the day
    final now = DateTime.now();
    final local = (createdAt ?? now).toLocal();
    final startOfToday = DateTime(now.year, now.month, now.day);
    return switch (_scope) {
      _Scope.today => !local.isBefore(startOfToday),
      // Rolling 7 days (today plus the previous six).
      _Scope.week => !local.isBefore(
        startOfToday.subtract(const Duration(days: 6)),
      ),
    };
  }
```

- [ ] **Step 5: Rewrite the `build` method**

Replace the entire `build` method (from `Widget build(BuildContext context) {` through its closing `}`) with:

```dart
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final day = _selectedDay;
    final salesAsync = day == null
        ? ref.watch(recentSalesProvider)
        : ref.watch(salesForDayProvider(day));
    final firstDate = ref.watch(earliestSaleDateProvider).value;
    final currency = ref.watch(myShopProvider).value?.currency ?? 'USD';
    final products =
        ref.watch(productsStreamProvider).value ?? const <Product>[];
    final nameById = {for (final p in products) p.id: p.name};

    void refreshActive() {
      if (_selectedDay == null) {
        ref.invalidate(recentSalesProvider);
      } else {
        ref.invalidate(salesForDayProvider(_selectedDay!));
      }
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: salesAsync.when(
          loading: () => const _HistorySkeleton(),
          error: (e, _) => _ErrorState(
            message: e is Failure
                ? e.message
                : 'Could not load sales history. Pull to retry.',
            onRetry: refreshActive,
          ),
          data: (all) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Text(
                    'Sales history',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Search sales',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _debounce?.cancel();
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                            ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _ScopeSelector(
                              scope: _scope,
                              dayActive: day != null,
                              onChanged: (s) => setState(() {
                                _scope = s;
                                _selectedDay = null;
                              }),
                            ),
                          ),
                          const SizedBox(width: 8),
                          CalendarDayButton(
                            selectedDay: day,
                            firstDate: firstDate,
                            onPick: (picked) =>
                                setState(() => _selectedDay = picked),
                          ),
                        ],
                      ),
                      if (day != null) ...[
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: DayFilterChip(
                            label: DateFormat('EEE, d MMM y').format(day),
                            onClear: () => setState(() => _selectedDay = null),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: all.isEmpty
                      ? _EmptyState(
                          message: day == null
                              ? 'No sales recorded yet.'
                              : 'No sales on ${DateFormat('EEE, d MMM y').format(day)}.',
                          showHint: day == null,
                        )
                      : _SalesTable(
                          rows: _visibleRows(all, nameById),
                          sortKey: _sortKey,
                          ascending: _ascending,
                          currency: currency,
                          onSort: _onSort,
                          onRefresh: () async => refreshActive(),
                          scrollController: ref.watch(
                            branchScrollControllerProvider(3),
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
```

- [ ] **Step 6: Update `_ScopeSelector` for 2 segments + day-active state**

Replace the whole `_ScopeSelector` class with:

```dart
/// Today / Week connected segmented control. When [dayActive] is true a specific
/// calendar day is selected, so neither segment is highlighted.
class _ScopeSelector extends StatelessWidget {
  const _ScopeSelector({
    required this.scope,
    required this.dayActive,
    required this.onChanged,
  });

  final _Scope scope;
  final bool dayActive;
  final ValueChanged<_Scope> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          for (final s in _Scope.values)
            Expanded(
              child: _ScopeTab(
                label: switch (s) {
                  _Scope.today => 'Today',
                  _Scope.week => 'Week',
                },
                selected: !dayActive && s == scope,
                onTap: () => onChanged(s),
              ),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 7: Add a `showHint` flag to `_EmptyState`**

Replace the `_EmptyState` class's constructor + fields and wrap its hint in the flag. Replace:

```dart
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;
```

with:

```dart
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message, this.showHint = true});

  final String message;

  /// The "Record a sale from Items…" hint only makes sense when the shop has no
  /// sales at all — it's hidden when a specific (empty) day is selected.
  final bool showHint;
```

Then, inside its `build`, wrap the trailing hint `Padding` (the one containing `'Record a sale from Items → tap a product → Record sale.'`) so it only renders when `showHint` is true. Replace:

```dart
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Record a sale from Items → tap a product → Record sale.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
```

with:

```dart
          if (showHint) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'Record a sale from Items → tap a product → Record sale.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
```

- [ ] **Step 8: Verify the whole file compiles**

Run: `flutter analyze lib/features/transactions/presentation/history_screen.dart`
Expected: No errors. (Common misses: leftover `_Scope.all` reference, or a missing `intl`/`calendar_day_button` import.)

- [ ] **Step 9: Run the full test suite (nothing regressed)**

Run: `flutter test`
Expected: PASS. `test/sales_in_scope_test.dart` still passes — it exercises `AnalyticsPeriod.all` (a different enum), not the removed `_Scope.all`.

- [ ] **Step 10: Commit**

```bash
git add lib/features/transactions/presentation/history_screen.dart
git commit -m "feat(history): calendar day-drill replaces the All segment"
```

---

## Task 6: Wire the shop-lifetime floor into Home & Reports

**Files:**
- Modify: `lib/features/dashboard/presentation/dashboard_screen.dart`
- Modify: `lib/features/analytics/presentation/analytics_screen.dart`

- [ ] **Step 1: Import the shared provider in both screens**

In `dashboard_screen.dart` and `analytics_screen.dart`, add to the relative-import group:

```dart
import '../../transactions/presentation/sales_providers.dart';
```

- [ ] **Step 2: Pass `firstDate` on the dashboard's `CalendarDayButton`**

In `dashboard_screen.dart`, in the `CalendarDayButton( selectedDay: selectedDay, onPick: ... )` (around line 186), add the `firstDate` argument:

```dart
                    CalendarDayButton(
                      selectedDay: selectedDay,
                      firstDate: ref.watch(earliestSaleDateProvider).value,
                      onPick: (day) =>
                          ref.read(selectedDayProvider.notifier).set(day),
                    ),
```

- [ ] **Step 3: Pass `firstDate` on the Reports `CalendarDayButton`**

In `analytics_screen.dart`, in the `CalendarDayButton( selectedDay: day, size: 34, onPick: ... )` (around line 313), add the `firstDate` argument:

```dart
            CalendarDayButton(
              selectedDay: day,
              size: 34,
              firstDate: ref.watch(earliestSaleDateProvider).value,
              onPick: (d) =>
                  ref.read(reportSelectedDayProvider.notifier).set(d),
            ),
```

> If either `CalendarDayButton` sits in a `build` without a `ref` in scope (e.g. a plain `StatelessWidget` sub-widget rather than a `Consumer`/`ConsumerState`), thread `firstDate` down as a constructor parameter from the nearest `ref`-bearing ancestor instead of calling `ref.watch` inline. Both current call sites already use `ref` nearby (`ref.read(...notifier)` in `onPick`), so inline `ref.watch` is expected to work.

- [ ] **Step 4: Verify both compile**

Run: `flutter analyze lib/features/dashboard/presentation/dashboard_screen.dart lib/features/analytics/presentation/analytics_screen.dart`
Expected: No errors.

- [ ] **Step 5: Commit**

```bash
git add lib/features/dashboard/presentation/dashboard_screen.dart lib/features/analytics/presentation/analytics_screen.dart
git commit -m "feat(dashboard,analytics): calendar floor = shop's first sale"
```

---

## Task 7: Full verification

**Files:** none (verification only)

- [ ] **Step 1: Analyze the whole project**

Run: `flutter analyze`
Expected: No new errors introduced by this branch.

- [ ] **Step 2: Run the full test suite**

Run: `flutter test`
Expected: All tests pass (including the new `test/day_range_test.dart`).

- [ ] **Step 3: Manual smoke test on device/emulator**

Run: `flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`

Verify, on the **History** tab:
- The control shows `[Today | Week]` with a circular calendar button to the right — no `All`.
- Tapping the calendar opens a picker whose earliest selectable date is the shop's **first sale** (tap the year label to confirm you can reach that year).
- Picking a past day deselects Today/Week, shows a `Fri, 3 Jul 2026`-style chip, and lists only that day's sales; the ✕ on the chip returns to the Today view.
- A day with no sales shows "No sales on <day>." with no "Record a sale…" hint.
- Search and column sorting still work inside a selected day.

Verify, on **Home** and **Reports**: their calendar pickers now also reach back to the shop's first sale (previously capped at 1 year).

- [ ] **Step 4: Final review commit (if any manual fixups were needed)**

Only if Step 3 surfaced fixes:

```bash
git add -A
git commit -m "fix(history): address manual smoke-test findings"
```

---

## Self-Review Notes

- **Spec coverage:** Layout (Task 5) · earliest-sale floor across all three calendars (Tasks 3, 4, 6) · uncapped day query (Tasks 1, 2) · `All` removed / default Today (Task 5) · day-mode empty state (Task 5) · error/retry reuse (Task 5, `refreshActive`) · tests (Task 1, Task 7). All spec sections mapped.
- **Chip format:** History uses `EEE, d MMM y` (includes the year) because the feature spans years; Home/Reports keep their existing `EEE, d MMM`. This is an intentional, per-surface choice.
- **Type consistency:** `dayRangeUtc` returns a record `({DateTime startUtc, DateTime endUtc})` used identically in Task 2. `salesForDay`/`earliestSaleDate` signatures match their provider call sites in Task 3. `CalendarDayButton.firstDate` (`DateTime?`) matches the `ref.watch(earliestSaleDateProvider).value` (`DateTime?`) passed in Tasks 5 and 6.
