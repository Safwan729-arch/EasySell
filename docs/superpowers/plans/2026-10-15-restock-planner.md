# Restock Planner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tell the shopkeeper what to restock and how much, from a 4-week weighted sales speed that ignores out-of-stock days, so one spike week no longer drives his buying.

**Architecture:**
- A read-only Postgres RPC (`get_restock_speeds`, migration 0017) rebuilds each product's daily stock from transactions and returns a smoothed units-per-day speed plus last week's rate.
- A pure Dart function (`planRestock`) turns speeds, good stock and the "restock every N days" setting into a Buy-now list and an Enough-for-now list.
- The UI is a Restock list screen, a Home card and a Settings tile, all in a new `lib/features/restock/` feature.

**Tech Stack:** Flutter, Riverpod 3, go_router, supabase_flutter RPC, SharedPreferences, ARB l10n (en + bn), flutter_test.

**Spec:** `docs/superpowers/specs/2026-10-15-restock-planner-design.md`

## Global Constraints

- The window is the 28 full local days ending **yesterday**. Week 0 is the 7 days ending yesterday, and so on through week 3. Today is never counted.
- Week weights are **0.4 / 0.3 / 0.2 / 0.1**, renormalised over the weeks that have a rate.
- An in-stock day is one with start-of-day stock above 0 **or** a sale that day. Days before the product's local `created_at` date never count.
- Net change per transaction: `restock +q`, `sale −q`, `adjustment −q`. Units are `quantity` on `sale` rows only.
- Trend: **up** if `week0Rate > 1.2 × speed`, **down** if `week0Rate < 0.8 × speed`, otherwise flat. A missing week-0 rate is flat.
- Suggestion = `ceil(speed × (restockDays + 2) − goodStock)`. The buffer is **2 days**. At most 0 means nothing to buy.
- Buy now: suggestion ≥ 1, ordered by days left ascending, then by name.
- Enough for now: the rest with speed > 0, in the same order.
- Products with speed 0 are never shown.
- Days left = `goodStock ÷ speed`. "Runs out today" when under 1. Red when days left ≤ 2, amber otherwise.
- Good stock = `goodStockOf(product, productExpiryProvider)`. Expired units never count.
- Restock days is a phone-local setting (SharedPreferences), range 1–30, default **7**.
- Dates sent to the server are the phone's local date plus its UTC offset in minutes.
- Every new string goes in **both** `lib/l10n/app_en.arb` and `lib/l10n/app_bn.arb` (`test/l10n_parity_test.dart` enforces it). Run `flutter gen-l10n` after editing ARBs.
- Run `dart format` on **touched files only**. Never run `dart format .`.
- Never stage `.gitignore`, `docs/business/`, `new design/`, `docs/superpowers/specs/2026-10-13-offline-selling-sync-design.md`, or the user's own hunks in `docs/00-Map.md`.
  - Stage map hunks only with: `rtk proxy git diff docs/00-Map.md | awk '/^@@/{n++} n<2{print}' > .git/x.patch && git apply --cached .git/x.patch && rm .git/x.patch`.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Never use the Supabase MCP. The user pastes SQL into the Supabase SQL editor.

## Review Focus

1. **Out-of-stock days are skipped.** A product that sold out mid-week must keep a high speed, not drop to the diluted average. This is SQL-only, so the verification query in Task 1 is the only check. The reviewer must trace `start_stock` by hand for one sold-out case.
2. **A product created inside the window**, with opening stock and no restock row, must not count the days before it existed. That is the `d >= created_day` filter in Task 1.
3. **Late evening in Bangladesh (UTC+6):** a sale at 23:30 local belongs to that local day, not the next UTC day. Task 1 uses `created_at at time zone 'UTC' + offset`, and Task 4's provider sends `timeZoneOffset.inMinutes`.
4. **Floating-point suggestions** (for example `5.0 × 9 − 10 = 35.000000000004`) must not round up to 36. Task 2 has the `ceil(x − 1e-9)` test.
5. **Missing migration or offline:** the Home card must hide and the list must show the error state with Retry, never a crash. Task 4 and Task 5 have the error-state tests.

---

## File Structure

| File | Responsibility |
|---|---|
| `supabase/migrations/0017_restock_speeds.sql` (create) | `get_restock_speeds` RPC |
| `lib/features/restock/domain/restock_plan.dart` (create) | `RestockSpeed`, `RestockTrend`, `RestockItem`, `RestockPlan`, `planRestock` — pure |
| `lib/features/restock/data/restock_repository.dart` (create) | RPC call → `List<RestockSpeed>` |
| `lib/features/restock/presentation/restock_prefs.dart` (create) | `restockDaysProvider`, `loadRestockDays()` |
| `lib/features/restock/presentation/restock_providers.dart` (create) | `restockSpeedsProvider`, `restockPlanProvider` |
| `lib/features/restock/presentation/restock_text.dart` (create) | shared "Runs out…" / days text |
| `lib/features/restock/presentation/restock_screen.dart` (create) | Restock list |
| `lib/features/restock/presentation/restock_card.dart` (create) | Home "Restock soon" card |
| `lib/features/restock/presentation/restock_settings_tile.dart` (create) | "I restock every N days" tile |
| `lib/main.dart` (modify) | seed `initialRestockDaysProvider` |
| `lib/core/router/app_router.dart` (modify) | `AppRoutes.restock` + route |
| `lib/features/dashboard/presentation/dashboard_screen.dart` (modify) | insert card |
| `lib/features/inventory/presentation/inventory_list_screen.dart` (modify) | app-bar button |
| `lib/features/settings/presentation/settings_screen.dart` (modify) | add tile |
| `lib/l10n/app_en.arb`, `lib/l10n/app_bn.arb` (modify) | strings |
| tests: `test/restock_plan_test.dart`, `test/restock_prefs_test.dart`, `test/widgets/restock_screen_test.dart`, `test/widgets/restock_card_test.dart` (create) | |

---

### Task 1: Migration 0017 — `get_restock_speeds`

**Files:**
- Create: `supabase/migrations/0017_restock_speeds.sql`

**Interfaces:**
- Produces: the RPC `get_restock_speeds(p_shop_id uuid, p_today date, p_utc_offset_minutes integer)` returns rows `{product_id uuid, speed numeric, week0_rate numeric|null}`, only for products with speed > 0 that are not archived.

No automated test is possible, because the repo has no Postgres harness. The ledger records this as a ruling. Verification is by the query in Step 2, which the user runs.

- [ ] **Step 1: Write the migration**

```sql
-- =============================================================================
-- 0017: restock planner speeds (spec 2026-10-15-restock-planner-design.md §3)
-- =============================================================================
-- Per product: a units-per-day speed over the 28 full LOCAL days ending
-- yesterday, weeks weighted 0.4/0.3/0.2/0.1, counting only days the product
-- could be sold (start-of-day stock > 0, or a sale that day). Days when the
-- shelf was empty are skipped: counting them made a product that sold out look
-- slow, which is the exact mistake the planner exists to stop.
--
-- Start-of-day stock is rebuilt BACKWARDS from products.quantity:
--   stock_at_start(d) = quantity - sum(net change of every row on day >= d)
-- with restock +q, sale -q, adjustment -q (every adjustment is a removal:
-- 0011/0013/0014/0015). Stock edited by hand before commit 310bd5d left no row,
-- so such products' early history is off by the edit; accepted, it ages out.
-- Days before the product's created_at never count: opening stock has no
-- restock row, so the rebuild would show it on shelves before it existed.
--
-- p_today and p_utc_offset_minutes come from the phone: the server's
-- current_date is UTC, still "yesterday" in Bangladesh until 6 AM.
--
-- Read-only, not security definer: RLS on products/transactions applies.
-- Run after 0016. Safe to re-run.
-- =============================================================================

drop function if exists get_restock_speeds(uuid, date, integer);

create function get_restock_speeds(
  p_shop_id            uuid,
  p_today              date,
  p_utc_offset_minutes integer default 0
) returns table (product_id uuid, speed numeric, week0_rate numeric)
language sql
stable
as $$
  with
  days as (
    select generate_series((p_today - 28)::timestamp,
                           (p_today - 1)::timestamp,
                           interval '1 day')::date as d
  ),
  prod as (
    select p.id, p.quantity,
           ((p.created_at at time zone 'UTC')
              + make_interval(mins => p_utc_offset_minutes))::date as created_day
    from products p
    where p.shop_id = p_shop_id
      and not coalesce(p.is_archived, false)
  ),
  txn as (
    select x.product_id, x.d,
           sum(x.net)  as net,
           sum(x.sold) as sold
    from (
      select t.product_id,
             ((t.created_at at time zone 'UTC')
                + make_interval(mins => p_utc_offset_minutes))::date as d,
             case t.type when 'restock' then t.quantity else -t.quantity end
               as net,
             case t.type when 'sale' then t.quantity else 0 end as sold
      from transactions t
      where t.shop_id = p_shop_id
    ) x
    where x.d >= p_today - 28
    group by x.product_id, x.d
  ),
  grid as (
    select p.id as product_id,
           dy.d,
           p.created_day,
           coalesce(tx.sold, 0) as sold,
           p.quantity - coalesce((
             select sum(t2.net) from txn t2
             where t2.product_id = p.id and t2.d >= dy.d
           ), 0) as start_stock
    from prod p
    cross join days dy
    left join txn tx on tx.product_id = p.id and tx.d = dy.d
  ),
  weekly as (
    select g.product_id,
           (p_today - 1 - g.d) / 7 as w,
           sum(g.sold) as units,
           count(*) filter (
             where g.d >= g.created_day
               and (g.start_stock > 0 or g.sold > 0)
           ) as in_days
    from grid g
    group by g.product_id, (p_today - 1 - g.d) / 7
  ),
  rates as (
    select wk.product_id, wk.w,
           wk.units::numeric / wk.in_days as rate,
           case wk.w when 0 then 0.4 when 1 then 0.3 when 2 then 0.2 else 0.1
           end as wt
    from weekly wk
    where wk.in_days > 0
  )
  select r.product_id,
         sum(r.rate * r.wt) / sum(r.wt)        as speed,
         max(r.rate) filter (where r.w = 0)    as week0_rate
  from rates r
  group by r.product_id
  having sum(r.rate * r.wt) > 0;
$$;
```

- [ ] **Step 2: Append the verification query as a trailing comment**

Add this at the end of the file, commented out, so the user can run it after the migration. It prints one product's 28 days for a hand check.

```sql
-- -----------------------------------------------------------------------------
-- VERIFY (run by hand; replace the email and product name):
--
-- select * from get_restock_speeds(
--   (select s.id from shops s join auth.users u on u.id = s.owner_id
--     where u.email = 'safwansaka55555@gmail.com'),
--   current_date, 360);
--
-- Hand check for one product -- each day's sold units and start-of-day stock:
-- with p as (select id, quantity from products where name = 'Pepsi'),
-- t as (select ((created_at at time zone 'UTC') + interval '360 minutes')::date d,
--              case type when 'restock' then quantity else -quantity end net,
--              case type when 'sale' then quantity else 0 end sold
--       from transactions where product_id = (select id from p))
-- select g.d,
--        coalesce((select sum(sold) from t where t.d = g.d), 0) as sold,
--        (select quantity from p)
--          - coalesce((select sum(net) from t where t.d >= g.d), 0) as start_stock
-- from generate_series(current_date - 28, current_date - 1, interval '1 day') g(d)
-- order by g.d;
-- -----------------------------------------------------------------------------
```

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/0017_restock_speeds.sql
git commit -m "feat(restock): get_restock_speeds RPC (0017)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Domain — `planRestock`

**Files:**
- Create: `lib/features/restock/domain/restock_plan.dart`
- Test: `test/restock_plan_test.dart`

**Interfaces:**
- Consumes: `Product` (`lib/features/inventory/domain/product.dart`: `id`, `name`, `quantity`, `unitType`).
- Produces:
  - `class RestockSpeed { final String productId; final double speed; final double? week0Rate; factory RestockSpeed.fromMap(Map<String, dynamic>) }`
  - `enum RestockTrend { up, down, flat }`
  - `class RestockItem { final Product product; final double speed; final double goodStock; final double daysLeft; final double suggestion; final RestockTrend trend; }`
  - `class RestockPlan { final List<RestockItem> buyNow; final List<RestockItem> enough; static const empty; }`
  - `const restockBufferDays = 2;`
  - `RestockPlan planRestock({required List<Product> products, required Map<String, RestockSpeed> speeds, required double Function(Product) goodStock, required int restockDays})`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/restock/domain/restock_plan.dart';
import 'package:flutter_test/flutter_test.dart';

Product _p(String id, {double qty = 0, UnitType unit = UnitType.piece}) =>
    Product(id: id, shopId: 's', name: id, quantity: qty, unitType: unit);

RestockPlan _plan(
  List<Product> products,
  Map<String, RestockSpeed> speeds, {
  int days = 7,
}) => planRestock(
  products: products,
  speeds: speeds,
  goodStock: (p) => p.quantity,
  restockDays: days,
);

RestockSpeed _s(String id, double speed, [double? w0]) =>
    RestockSpeed(productId: id, speed: speed, week0Rate: w0);

void main() {
  test('spec §3.6 Mojo: 5/day, 10 in stock, every 7 days → buy 35', () {
    final plan = _plan([_p('Mojo', qty: 10)], {'Mojo': _s('Mojo', 5, 8)});
    final m = plan.buyNow.single;
    expect(m.daysLeft, 2);
    expect(m.suggestion, 35);
    expect(m.trend, RestockTrend.up);
  });

  test('a float just over a whole number does not round up', () {
    // 5 × 9 − 10 may come out as 35.000000000004.
    final plan = _plan([_p('A', qty: 10)], {'A': _s('A', 5.0000000000004)});
    expect(plan.buyNow.single.suggestion, 35);
  });

  test('trend thresholds: >1.2× up, <0.8× down, else and null flat', () {
    RestockTrend t(double? w0) =>
        _plan([_p('A', qty: 0)], {'A': _s('A', 10, w0)}).buyNow.single.trend;
    expect(t(12.1), RestockTrend.up);
    expect(t(12), RestockTrend.flat);
    expect(t(8), RestockTrend.flat);
    expect(t(7.9), RestockTrend.down);
    expect(t(null), RestockTrend.flat);
  });

  test('zero good stock: days left 0 and the full period is suggested', () {
    final item = _plan([_p('A')], {'A': _s('A', 2)}).buyNow.single;
    expect(item.daysLeft, 0);
    expect(item.suggestion, 18);
  });

  test('negative stock is treated as zero', () {
    final item = _plan([_p('A', qty: -3)], {'A': _s('A', 1)}).buyNow.single;
    expect(item.goodStock, 0);
    expect(item.suggestion, 9);
  });

  test('suggestion of exactly 1 is Buy now; 0 or less is Enough', () {
    final plan = _plan(
      [_p('One', qty: 8), _p('Zero', qty: 9), _p('Over', qty: 50)],
      {'One': _s('One', 1), 'Zero': _s('Zero', 1), 'Over': _s('Over', 1)},
    );
    expect(plan.buyNow.map((i) => i.product.id), ['One']);
    expect(plan.enough.map((i) => i.product.id), ['Zero', 'Over']);
    expect(plan.enough.first.suggestion, 0);
  });

  test('ordered by days left, ties by name', () {
    final plan = _plan(
      [_p('b', qty: 2), _p('a', qty: 2), _p('c', qty: 1)],
      {'a': _s('a', 1), 'b': _s('b', 1), 'c': _s('c', 1)},
    );
    expect(plan.buyNow.map((i) => i.product.id), ['c', 'a', 'b']);
  });

  test('speed 0 or no speed row: not planned', () {
    final plan = _plan(
      [_p('A', qty: 1), _p('B', qty: 1)],
      {'A': _s('A', 0)},
    );
    expect(plan.buyNow, isEmpty);
    expect(plan.enough, isEmpty);
  });

  test('decimal units: suggestion rounds up to a whole unit', () {
    final plan = _plan(
      [_p('Rice', qty: 1.5, unit: UnitType.weight)],
      {'Rice': _s('Rice', 0.75)},
    );
    // 0.75 × 9 − 1.5 = 5.25 → 6
    expect(plan.buyNow.single.suggestion, 6);
    expect(plan.buyNow.single.daysLeft, 2);
  });

  test('restock days changes the cover', () {
    final plan = _plan([_p('A', qty: 0)], {'A': _s('A', 1)}, days: 3);
    expect(plan.buyNow.single.suggestion, 5);
  });

  test('RestockSpeed.fromMap reads numerics as num or string', () {
    final s = RestockSpeed.fromMap({
      'product_id': 'p1',
      'speed': '2.5',
      'week0_rate': null,
    });
    expect(s.productId, 'p1');
    expect(s.speed, 2.5);
    expect(s.week0Rate, isNull);
    expect(
      RestockSpeed.fromMap({
        'product_id': 'p2',
        'speed': 3,
        'week0_rate': 4,
      }).week0Rate,
      4,
    );
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/restock_plan_test.dart`
Expected: FAIL, loading error (`restock_plan.dart` does not exist).

- [ ] **Step 3: Write the implementation**

```dart
import 'dart:math' as math;

import '../../inventory/domain/product.dart';

/// Days of stock added on top of the restock period, to cover a late trip
/// (spec §3.4).
const restockBufferDays = 2;

/// One product's speed from `get_restock_speeds` (0017).
class RestockSpeed {
  const RestockSpeed({
    required this.productId,
    required this.speed,
    this.week0Rate,
  });

  factory RestockSpeed.fromMap(Map<String, dynamic> m) => RestockSpeed(
    productId: m['product_id'] as String,
    speed: _num(m['speed']) ?? 0,
    week0Rate: _num(m['week0_rate']),
  );

  final String productId;

  /// Units per in-stock day, weeks weighted 0.4/0.3/0.2/0.1.
  final double speed;

  /// Last week's units per in-stock day; null when it had no in-stock day.
  final double? week0Rate;

  static double? _num(Object? v) => switch (v) {
    final num n => n.toDouble(),
    final String s => double.tryParse(s),
    _ => null,
  };
}

enum RestockTrend { up, down, flat }

class RestockItem {
  const RestockItem({
    required this.product,
    required this.speed,
    required this.goodStock,
    required this.daysLeft,
    required this.suggestion,
    required this.trend,
  });

  final Product product;
  final double speed;
  final double goodStock;
  final double daysLeft;

  /// Whole units to buy; 0 when there is enough.
  final double suggestion;
  final RestockTrend trend;
}

class RestockPlan {
  const RestockPlan({required this.buyNow, required this.enough});

  static const empty = RestockPlan(buyNow: [], enough: []);

  final List<RestockItem> buyNow;
  final List<RestockItem> enough;

  bool get isEmpty => buyNow.isEmpty && enough.isEmpty;
}

/// Spec §3.4–3.5. Products without a speed above zero are left out: with no
/// sales in four weeks there is nothing to plan from.
RestockPlan planRestock({
  required List<Product> products,
  required Map<String, RestockSpeed> speeds,
  required double Function(Product) goodStock,
  required int restockDays,
}) {
  final items = <RestockItem>[];
  for (final p in products) {
    final s = speeds[p.id];
    if (s == null || s.speed <= 0) continue;
    final good = math.max(0.0, goodStock(p));
    final raw = s.speed * (restockDays + restockBufferDays) - good;
    // 1e-9: 5 × 9 − 10 can come out a hair over 35 and must not become 36.
    final suggestion = math.max(0, (raw - 1e-9).ceil()).toDouble();
    final w0 = s.week0Rate;
    final trend = w0 == null
        ? RestockTrend.flat
        : w0 > 1.2 * s.speed
        ? RestockTrend.up
        : w0 < 0.8 * s.speed
        ? RestockTrend.down
        : RestockTrend.flat;
    items.add(
      RestockItem(
        product: p,
        speed: s.speed,
        goodStock: good,
        daysLeft: good / s.speed,
        suggestion: suggestion,
        trend: trend,
      ),
    );
  }
  items.sort((a, b) {
    final c = a.daysLeft.compareTo(b.daysLeft);
    if (c != 0) return c;
    return a.product.name.toLowerCase().compareTo(b.product.name.toLowerCase());
  });
  return RestockPlan(
    buyNow: [for (final i in items) if (i.suggestion >= 1) i],
    enough: [for (final i in items) if (i.suggestion < 1) i],
  );
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/restock_plan_test.dart`
Expected: all 11 tests PASS.

- [ ] **Step 5: Format and commit**

```bash
dart format lib/features/restock/domain/restock_plan.dart test/restock_plan_test.dart
git add lib/features/restock/domain/restock_plan.dart test/restock_plan_test.dart
git commit -m "feat(restock): planRestock — days left, trend and buy suggestion

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: "I restock every N days" setting

**Files:**
- Create: `lib/features/restock/presentation/restock_prefs.dart`
- Create: `lib/features/restock/presentation/restock_settings_tile.dart`
- Modify: `lib/main.dart` (next to `final expiryPrefs = await loadExpiryPrefs();` and its override)
- Modify: `lib/features/settings/presentation/settings_screen.dart` (Inventory section, after the archived-products `ListTile`)
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_bn.arb`
- Test: `test/restock_prefs_test.dart`

**Interfaces:**
- Produces:
  - `final initialRestockDaysProvider = Provider<int>((ref) => 7);`
  - `final restockDaysProvider = NotifierProvider<RestockDaysController, int>(...)`, with `Future<void> set(int days)`
  - `Future<int> loadRestockDays()`
  - `const restockDayChoices = [1, 2, 3, 5, 7, 10, 14, 30];`
  - the widget `RestockDaysTile`

Ruling recorded in advance: the spec says "1–30". The tile offers presets inside that range, matching the expiry warn-days picker's `SimpleDialog`, rather than a free number field. `set` clamps any value to 1–30.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:ai_shopkeeper/features/restock/presentation/restock_prefs.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('defaults to 7 days', () async {
    expect(await loadRestockDays(), 7);
  });

  test('a change persists across a reload, clamped to 1–30', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(restockDaysProvider.notifier).set(3);
    expect(c.read(restockDaysProvider), 3);
    expect(await loadRestockDays(), 3);

    await c.read(restockDaysProvider.notifier).set(90);
    expect(c.read(restockDaysProvider), 30);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/restock_prefs_test.dart`
Expected: FAIL, loading error (file missing).

- [ ] **Step 3: Implement the prefs**

`lib/features/restock/presentation/restock_prefs.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Presets for "I restock every N days" (spec §4.3: 1–30, default 7).
const restockDayChoices = [1, 2, 3, 5, 7, 10, 14, 30];

const _kRestockDays = 'restock_every_days';

/// Seeded in `main()` from SharedPreferences, like `initialExpiryPrefsProvider`.
final initialRestockDaysProvider = Provider<int>((ref) => 7);

class RestockDaysController extends Notifier<int> {
  @override
  int build() => ref.watch(initialRestockDaysProvider);

  Future<void> set(int days) async {
    state = days.clamp(1, 30);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kRestockDays, state);
  }
}

final restockDaysProvider = NotifierProvider<RestockDaysController, int>(
  RestockDaysController.new,
);

Future<int> loadRestockDays() async {
  final prefs = await SharedPreferences.getInstance();
  return (prefs.getInt(_kRestockDays) ?? 7).clamp(1, 30);
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/restock_prefs_test.dart`
Expected: 2 tests PASS.

- [ ] **Step 5: Add the strings**

In `lib/l10n/app_en.arb`, after the `"expiry_thrownAway"` entry and its `@` metadata:

```json
  "settings_restockEvery": "I restock every {days} days",
  "@settings_restockEvery": { "placeholders": { "days": { "type": "String" } } },
  "settings_restockEveryTitle": "How often do you restock?",
  "restockPlan_daysShort": "{days} days",
  "@restockPlan_daysShort": { "placeholders": { "days": { "type": "String" } } },
```

In `lib/l10n/app_bn.arb`, after `"expiry_thrownAway"`:

```json
  "settings_restockEvery": "আমি প্রতি {days} দিনে রিস্টক করি",
  "settings_restockEveryTitle": "কত দিন পরপর রিস্টক করেন?",
  "restockPlan_daysShort": "{days} দিন",
```

Run: `flutter gen-l10n`

- [ ] **Step 6: Write the tile**

`lib/features/restock/presentation/restock_settings_tile.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../shared/extensions/format.dart';
import 'restock_prefs.dart';

/// Settings: how often the shopkeeper restocks, which sets how many days the
/// buy suggestion covers (restock spec §4.3).
class RestockDaysTile extends ConsumerWidget {
  const RestockDaysTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final days = ref.watch(restockDaysProvider);
    return ListTile(
      leading: const Icon(Icons.shopping_basket_outlined),
      title: Text(l10n.settings_restockEvery(Qty.format(days))),
      onTap: () async {
        final picked = await showDialog<int>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: Text(l10n.settings_restockEveryTitle),
            children: [
              for (final d in restockDayChoices)
                SimpleDialogOption(
                  onPressed: () => Navigator.of(ctx).pop(d),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(l10n.restockPlan_daysShort(Qty.format(d))),
                      ),
                      if (d == days) const Icon(Icons.check, size: 18),
                    ],
                  ),
                ),
            ],
          ),
        );
        if (picked != null) {
          await ref.read(restockDaysProvider.notifier).set(picked);
        }
      },
    );
  }
}
```

- [ ] **Step 7: Wire it into Settings and `main()`**

In `settings_screen.dart`, import `'../../restock/presentation/restock_settings_tile.dart'` and insert after the archived-products `ListTile` (the one with `onTap: () => context.push(AppRoutes.archivedProducts)`), before its `const Divider()`:

```dart
          const RestockDaysTile(),
```

In `lib/main.dart`, import `'features/restock/presentation/restock_prefs.dart'`. Next to `final expiryPrefs = await loadExpiryPrefs();` add:

```dart
  final restockDays = await loadRestockDays();
```

Next to `initialExpiryPrefsProvider.overrideWithValue(expiryPrefs),` add:

```dart
        initialRestockDaysProvider.overrideWithValue(restockDays),
```

- [ ] **Step 8: Analyze, test and commit**

Run: `flutter analyze` (expected: No issues found) and `flutter test test/restock_prefs_test.dart test/l10n_parity_test.dart` (expected: PASS).

```bash
dart format lib/features/restock/presentation/restock_prefs.dart lib/features/restock/presentation/restock_settings_tile.dart lib/main.dart lib/features/settings/presentation/settings_screen.dart test/restock_prefs_test.dart
git add lib/features/restock/presentation/restock_prefs.dart lib/features/restock/presentation/restock_settings_tile.dart lib/main.dart lib/features/settings/presentation/settings_screen.dart lib/l10n test/restock_prefs_test.dart
git commit -m "feat(restock): 'I restock every N days' setting

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Repository, providers, Restock list screen, route, Inventory entry

**Files:**
- Create: `lib/features/restock/data/restock_repository.dart`
- Create: `lib/features/restock/presentation/restock_providers.dart`
- Create: `lib/features/restock/presentation/restock_text.dart`
- Create: `lib/features/restock/presentation/restock_screen.dart`
- Modify: `lib/core/router/app_router.dart` (`AppRoutes` + a `GoRoute` beside `AppRoutes.alerts`)
- Modify: `lib/features/inventory/presentation/inventory_list_screen.dart` (before the `IconButton.filled` with `Icons.add`)
- Modify: ARB files
- Test: `test/widgets/restock_screen_test.dart`

**Interfaces:**
- Consumes:
  - `planRestock`, `RestockPlan`, `RestockItem`, `RestockTrend` and `RestockSpeed` (Task 2),
  - `restockDaysProvider` (Task 3),
  - `productsStreamProvider` (`inventory_controller.dart`), `productExpiryProvider` (`expiry_providers.dart`), `goodStockOf` (`expiry_estimate.dart`),
  - `myShopProvider` (`auth_repository.dart`), `dataRefreshProvider` (`shared/providers/refresh_provider.dart`),
  - `todayProvider` and `nowProvider` (`expiry/presentation/today_provider.dart`), `ymd` (`expiry/domain/expiry_dates.dart`),
  - `showRestockSheet(context, product:, initialQuantity:)` (`transactions/presentation/transaction_confirmation_sheet.dart`).
- Produces:
  - `restockRepositoryProvider`,
  - `restockSpeedsProvider` (`FutureProvider.autoDispose<Map<String, RestockSpeed>>`),
  - `restockPlanProvider` (`Provider.autoDispose<AsyncValue<RestockPlan>>`),
  - `String runsOutText(AppLocalizations l10n, RestockItem i)` and `String daysLeftShort(AppLocalizations l10n, RestockItem i)`,
  - `AppRoutes.restock = '/restock'`, `RestockScreen`.

- [ ] **Step 1: Add the strings**

`app_en.arb`, after `"restockPlan_daysShort"` and its metadata:

```json
  "restockPlan_title": "Restock list",
  "restockPlan_buyNow": "Buy now",
  "restockPlan_enough": "Enough for now ({count})",
  "@restockPlan_enough": { "placeholders": { "count": { "type": "String" } } },
  "restockPlan_runsOutToday": "Runs out today",
  "restockPlan_runsOutIn": "Runs out in {days} days",
  "@restockPlan_runsOutIn": { "placeholders": { "days": { "type": "String" } } },
  "restockPlan_today": "today",
  "restockPlan_buyAbout": "Buy about {qty} {unit}",
  "@restockPlan_buyAbout": { "placeholders": { "qty": { "type": "String" }, "unit": { "type": "String" } } },
  "restockPlan_inStock": "{qty} {unit} in stock",
  "@restockPlan_inStock": { "placeholders": { "qty": { "type": "String" }, "unit": { "type": "String" } } },
  "restockPlan_empty": "Nothing to restock yet. Suggestions appear after a few days of sales.",
  "restockPlan_loadError": "Could not load the restock list.",
```

`app_bn.arb`, after `"restockPlan_daysShort"`:

```json
  "restockPlan_title": "রিস্টক তালিকা",
  "restockPlan_buyNow": "এখন কিনুন",
  "restockPlan_enough": "আপাতত যথেষ্ট ({count})",
  "restockPlan_runsOutToday": "আজই শেষ হবে",
  "restockPlan_runsOutIn": "{days} দিনে শেষ হবে",
  "restockPlan_today": "আজ",
  "restockPlan_buyAbout": "প্রায় {qty} {unit} কিনুন",
  "restockPlan_inStock": "স্টকে {qty} {unit}",
  "restockPlan_empty": "এখনো রিস্টক করার কিছু নেই। কয়েক দিনের বিক্রির পর পরামর্শ দেখা যাবে।",
  "restockPlan_loadError": "রিস্টক তালিকা লোড করা যায়নি।",
```

Run: `flutter gen-l10n`

- [ ] **Step 2: Write the failing widget tests**

`test/widgets/restock_screen_test.dart`:

```dart
import 'package:ai_shopkeeper/core/config/theme.dart';
import 'package:ai_shopkeeper/core/error/failure.dart';
import 'package:ai_shopkeeper/features/auth/data/auth_repository.dart';
import 'package:ai_shopkeeper/features/auth/domain/shop.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/restock/domain/restock_plan.dart';
import 'package:ai_shopkeeper/features/restock/presentation/restock_providers.dart';
import 'package:ai_shopkeeper/features/restock/presentation/restock_screen.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:ai_shopkeeper/shared/providers/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

const _mojo = Product(id: 'mojo', shopId: 's1', name: 'Mojo', quantity: 10);
const _salt = Product(id: 'salt', shopId: 's1', name: 'Salt', quantity: 40);

final _plan = RestockPlan(
  buyNow: [
    RestockItem(
      product: _mojo,
      speed: 5,
      goodStock: 10,
      daysLeft: 2,
      suggestion: 35,
      trend: RestockTrend.up,
    ),
  ],
  enough: [
    RestockItem(
      product: _salt,
      speed: 1,
      goodStock: 40,
      daysLeft: 40,
      suggestion: 0,
      trend: RestockTrend.flat,
    ),
  ],
);

Future<void> _pump(WidgetTester tester, AsyncValue<RestockPlan> plan) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        restockPlanProvider.overrideWithValue(plan),
        myShopProvider.overrideWith(
          (ref) async =>
              const Shop(id: 's1', ownerId: 'o1', name: 'Shop', currency: 'BDT'),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('en'),
        supportedLocales: supportedAppLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const RestockScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('a Buy-now row says when it runs out and how many to buy', (
    tester,
  ) async {
    await _pump(tester, AsyncValue.data(_plan));
    expect(find.text('Buy now'), findsOneWidget);
    expect(find.text('Mojo'), findsOneWidget);
    expect(find.text('Runs out in 2 days'), findsOneWidget);
    expect(find.text('Buy about 35 pcs'), findsOneWidget);
    expect(find.text('10 pcs in stock'), findsOneWidget);
    expect(find.byIcon(Icons.trending_up), findsOneWidget);
    // Enough-for-now starts collapsed.
    expect(find.text('Enough for now (1)'), findsOneWidget);
    expect(find.text('Salt'), findsNothing);
  });

  testWidgets('tapping a Buy-now row opens restock with the suggestion', (
    tester,
  ) async {
    await _pump(tester, AsyncValue.data(_plan));
    await tester.tap(find.text('Mojo'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm restock'), findsOneWidget);
    expect(find.text('35 pcs'), findsOneWidget);
  });

  testWidgets('empty plan shows the empty state', (tester) async {
    await _pump(tester, const AsyncValue.data(RestockPlan.empty));
    expect(
      find.text(
        'Nothing to restock yet. Suggestions appear after a few days of sales.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a failed load shows the error with Retry, not a crash', (
    tester,
  ) async {
    await _pump(
      tester,
      AsyncValue.error(
        const DatabaseFailure('function get_restock_speeds does not exist'),
        StackTrace.empty,
      ),
    );
    expect(find.text('Could not load the restock list.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run them to verify they fail**

Run: `flutter test test/widgets/restock_screen_test.dart`
Expected: FAIL, loading error (`restock_providers.dart` and `restock_screen.dart` missing).

- [ ] **Step 4: Write the repository**

`lib/features/restock/data/restock_repository.dart`:

```dart
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../expiry/domain/expiry_dates.dart';
import '../domain/restock_plan.dart';

/// Reads `get_restock_speeds` (0017). The speed needs the transaction
/// history, so it is computed in Postgres (restock spec §5).
class RestockRepository {
  RestockRepository(this._client);

  final SupabaseClient _client;

  Future<Result<List<RestockSpeed>>> fetchSpeeds(
    String shopId, {
    required DateTime today,
    required int utcOffsetMinutes,
  }) async {
    try {
      final rows = await _client.rpc(
        'get_restock_speeds',
        params: {
          'p_shop_id': shopId,
          'p_today': ymd(today),
          'p_utc_offset_minutes': utcOffsetMinutes,
        },
      );
      return Result.success([
        for (final r in rows as List)
          RestockSpeed.fromMap(Map<String, dynamic>.from(r as Map)),
      ]);
    } catch (e) {
      return Result.failure(_map(e));
    }
  }

  Failure _map(Object e) {
    if (e is PostgrestException) return DatabaseFailure(e.message);
    if (e is SocketException) {
      return const NetworkFailure('No internet connection. Please try again.');
    }
    return const UnexpectedFailure('Something went wrong. Please try again.');
  }
}

final restockRepositoryProvider = Provider<RestockRepository>(
  (ref) => RestockRepository(ref.watch(supabaseClientProvider)),
);
```

- [ ] **Step 5: Write the providers**

`lib/features/restock/presentation/restock_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/refresh_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../../expiry/domain/expiry_estimate.dart';
import '../../expiry/presentation/expiry_providers.dart';
import '../../expiry/presentation/today_provider.dart';
import '../../inventory/domain/product.dart';
import '../../inventory/presentation/inventory_controller.dart';
import '../data/restock_repository.dart';
import '../domain/restock_plan.dart';
import 'restock_prefs.dart';

/// Speeds by product id. Refetches after a sale or restock
/// ([dataRefreshProvider]) and when the local date changes.
final restockSpeedsProvider =
    FutureProvider.autoDispose<Map<String, RestockSpeed>>((ref) async {
      ref.watch(dataRefreshProvider);
      final shop = ref.watch(myShopProvider).value;
      if (shop == null) return const {};
      final today = ref.watch(todayProvider);
      final offset = ref.read(nowProvider)().timeZoneOffset.inMinutes;
      final r = await ref
          .watch(restockRepositoryProvider)
          .fetchSpeeds(shop.id, today: today, utcOffsetMinutes: offset);
      return r.when(
        success: (l) => {for (final s in l) s.productId: s},
        failure: (f) => throw f,
      );
    });

/// The Restock list. Days left and the suggestion use GOOD stock -- the app's
/// own expiry estimate -- so they are computed here, not in SQL (spec §5).
final restockPlanProvider = Provider.autoDispose<AsyncValue<RestockPlan>>((
  ref,
) {
  final speeds = ref.watch(restockSpeedsProvider);
  final products = ref.watch(productsStreamProvider).value ?? const <Product>[];
  final byProduct = ref.watch(productExpiryProvider);
  final days = ref.watch(restockDaysProvider);
  return speeds.whenData(
    (s) => planRestock(
      products: products,
      speeds: s,
      goodStock: (p) => goodStockOf(p, byProduct),
      restockDays: days,
    ),
  );
});
```

- [ ] **Step 6: Write the shared text helpers**

`lib/features/restock/presentation/restock_text.dart`:

```dart
import '../../../l10n/app_localizations.dart';
import '../../../shared/extensions/format.dart';
import '../domain/restock_plan.dart';

/// "Runs out today" under one day, else "Runs out in N days" (whole days).
String runsOutText(AppLocalizations l10n, RestockItem i) => i.daysLeft < 1
    ? l10n.restockPlan_runsOutToday
    : l10n.restockPlan_runsOutIn(Qty.format(i.daysLeft.floor()));

/// "today" / "N days", for the Home card's one-line list.
String daysLeftShort(AppLocalizations l10n, RestockItem i) => i.daysLeft < 1
    ? l10n.restockPlan_today
    : l10n.restockPlan_daysShort(Qty.format(i.daysLeft.floor()));
```

- [ ] **Step 7: Write the screen**

`lib/features/restock/presentation/restock_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/theme.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../shared/extensions/format.dart';
import '../../transactions/presentation/transaction_confirmation_sheet.dart';
import '../domain/restock_plan.dart';
import 'restock_providers.dart';
import 'restock_text.dart';

/// What to restock and how much (restock spec §4.2).
class RestockScreen extends ConsumerWidget {
  const RestockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final plan = ref.watch(restockPlanProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.restockPlan_title)),
      body: switch (plan) {
        AsyncData(:final value) when value.isEmpty => _Message(
          icon: Icons.inventory_2_outlined,
          text: l10n.restockPlan_empty,
        ),
        AsyncData(:final value) => ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            if (value.buyNow.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  l10n.restockPlan_buyNow,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              for (final i in value.buyNow) _RestockRow(item: i, buy: true),
            ],
            if (value.enough.isNotEmpty)
              Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    l10n.restockPlan_enough(
                      Qty.format(value.enough.length),
                    ),
                    style: theme.textTheme.titleSmall,
                  ),
                  children: [
                    for (final i in value.enough)
                      _RestockRow(item: i, buy: false),
                  ],
                ),
              ),
          ],
        ),
        AsyncError() => _Message(
          icon: Icons.cloud_off_outlined,
          text: l10n.restockPlan_loadError,
          onRetry: () => ref.invalidate(restockSpeedsProvider),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _RestockRow extends StatelessWidget {
  const _RestockRow({required this.item, required this.buy});

  final RestockItem item;
  final bool buy;

  Future<void> _open(BuildContext context) async {
    if (!buy) {
      context.push('/inventory/${item.product.id}');
      return;
    }
    final recorded = await showRestockSheet(
      context,
      product: item.product,
      initialQuantity: item.suggestion,
    );
    if (recorded == true && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(context.l10n.common_stockAdded)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final p = item.product;
    final urgent = item.daysLeft <= 2;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => _open(context),
      title: Row(
        children: [
          Flexible(child: Text(p.name, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 6),
          switch (item.trend) {
            RestockTrend.up => Icon(
              Icons.trending_up,
              size: 18,
              color: colors.positive,
            ),
            RestockTrend.down => Icon(
              Icons.trending_down,
              size: 18,
              color: colors.negative,
            ),
            RestockTrend.flat => const SizedBox.shrink(),
          },
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            runsOutText(l10n, item),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: buy
                  ? (urgent ? colors.negative : colors.warning)
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: buy ? FontWeight.w600 : null,
            ),
          ),
          if (buy)
            Text(
              l10n.restockPlan_buyAbout(
                Qty.format(item.suggestion),
                p.unitLabel,
              ),
              style: theme.textTheme.bodyMedium,
            ),
          Text(
            l10n.restockPlan_inStock(Qty.format(item.goodStock), p.unitLabel),
            style: muted,
          ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.onRetry});

  final IconData icon;
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onRetry,
                child: Text(context.l10n.common_retry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 8: Add the route**

In `app_router.dart`:
- add `static const String restock = '/restock';` to `AppRoutes`, after `alerts`,
- import `'../../features/restock/presentation/restock_screen.dart'`,
- add this after the `AppRoutes.alerts` `GoRoute`:

```dart
      GoRoute(
        path: AppRoutes.restock,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (_, _) => _transitionPage(const RestockScreen()),
      ),
```

- [ ] **Step 9: Add the Inventory entry**

In `inventory_list_screen.dart`, immediately before the `IconButton.filled` whose `onPressed` is `() => context.push('/inventory/new')`, insert the following. Import `'../../../core/router/app_router.dart'` if it isn't already imported.

```dart
                  IconButton.filled(
                    onPressed: () => context.push(AppRoutes.restock),
                    icon: const Icon(Icons.shopping_basket_outlined),
                    tooltip: l10n.restockPlan_title,
                  ),
                  const SizedBox(width: 8),
```

- [ ] **Step 10: Run the tests to verify they pass**

Run: `flutter test test/widgets/restock_screen_test.dart`
Expected: 4 tests PASS.

If "tapping a Buy-now row" fails because the restock sheet needs a provider the test does not override, add that override (for example `transactionControllerProvider`). Do not weaken the assertion. Ledger it as a ruling.

- [ ] **Step 11: Analyze, run the full suite, commit**

Run `flutter analyze` (expected: No issues found) and `flutter test` (expected: all pass).

```bash
dart format lib/features/restock lib/core/router/app_router.dart lib/features/inventory/presentation/inventory_list_screen.dart test/widgets/restock_screen_test.dart
git add lib/features/restock lib/core/router/app_router.dart lib/features/inventory/presentation/inventory_list_screen.dart lib/l10n test/widgets/restock_screen_test.dart
git commit -m "feat(restock): Restock list screen

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Home "Restock soon" card

**Files:**
- Create: `lib/features/restock/presentation/restock_card.dart`
- Modify: `lib/features/dashboard/presentation/dashboard_screen.dart` (the `Entrance` list near `ExpiryAlertsCard`)
- Modify: ARB files
- Test: `test/widgets/restock_card_test.dart`

**Interfaces:**
- Consumes: `restockPlanProvider`, `daysLeftShort` (Task 4), `AppRoutes.restock` (Task 4), `RestockPlan`/`RestockItem` (Task 2).
- Produces: the widget `RestockSoonCard`.

- [ ] **Step 1: Add the strings**

`app_en.arb`, after `"restockPlan_loadError"`:

```json
  "restockPlan_cardTitle": "Restock soon",
  "restockPlan_cardSummary": "{count} items to restock",
  "@restockPlan_cardSummary": { "placeholders": { "count": { "type": "String" } } },
  "restockPlan_cardItem": "{name} · {days}",
  "@restockPlan_cardItem": { "placeholders": { "name": { "type": "String" }, "days": { "type": "String" } } },
```

`app_bn.arb`, after `"restockPlan_loadError"`:

```json
  "restockPlan_cardTitle": "শীঘ্রই রিস্টক করুন",
  "restockPlan_cardSummary": "{count}টি পণ্য রিস্টক করতে হবে",
  "restockPlan_cardItem": "{name} · {days}",
```

Run: `flutter gen-l10n`

- [ ] **Step 2: Write the failing tests**

`test/widgets/restock_card_test.dart`:

```dart
import 'package:ai_shopkeeper/core/config/theme.dart';
import 'package:ai_shopkeeper/core/error/failure.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/restock/domain/restock_plan.dart';
import 'package:ai_shopkeeper/features/restock/presentation/restock_card.dart';
import 'package:ai_shopkeeper/features/restock/presentation/restock_providers.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:ai_shopkeeper/shared/providers/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

RestockItem _item(String name, double daysLeft) => RestockItem(
  product: Product(id: name, shopId: 's1', name: name),
  speed: 1,
  goodStock: daysLeft,
  daysLeft: daysLeft,
  suggestion: 5,
  trend: RestockTrend.flat,
);

Future<void> _pump(WidgetTester tester, AsyncValue<RestockPlan> plan) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [restockPlanProvider.overrideWithValue(plan)],
      child: MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('en'),
        supportedLocales: supportedAppLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const Scaffold(body: RestockSoonCard()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('names the count and the top two with days left', (
    tester,
  ) async {
    await _pump(
      tester,
      AsyncValue.data(
        RestockPlan(
          buyNow: [_item('Mojo', 0.5), _item('Pepsi', 3.4), _item('Salt', 6)],
          enough: const [],
        ),
      ),
    );
    expect(find.text('Restock soon'), findsOneWidget);
    expect(find.text('3 items to restock'), findsOneWidget);
    expect(find.text('Mojo · today'), findsOneWidget);
    expect(find.text('Pepsi · 3 days'), findsOneWidget);
    expect(find.textContaining('Salt'), findsNothing);
  });

  testWidgets('hidden when nothing needs buying', (tester) async {
    await _pump(
      tester,
      AsyncValue.data(
        RestockPlan(buyNow: const [], enough: [_item('Salt', 40)]),
      ),
    );
    expect(find.text('Restock soon'), findsNothing);
  });

  testWidgets('hidden on error (e.g. 0017 not run yet) and while loading', (
    tester,
  ) async {
    await _pump(
      tester,
      AsyncValue.error(const DatabaseFailure('missing'), StackTrace.empty),
    );
    expect(find.text('Restock soon'), findsNothing);
    await _pump(tester, const AsyncValue.loading());
    expect(find.text('Restock soon'), findsNothing);
  });
}
```

- [ ] **Step 3: Run them to verify they fail**

Run: `flutter test test/widgets/restock_card_test.dart`
Expected: FAIL, loading error (`restock_card.dart` missing).

- [ ] **Step 4: Write the card**

`lib/features/restock/presentation/restock_card.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/theme.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/extensions/format.dart';
import 'restock_providers.dart';
import 'restock_text.dart';

/// Home's "Restock soon" card (restock spec §4.1). Hidden unless something
/// needs buying -- and on error or while loading, so a shop that has not run
/// 0017 sees no change.
class RestockSoonCard extends ConsumerWidget {
  const RestockSoonCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final buyNow = ref.watch(restockPlanProvider).value?.buyNow ?? const [];
    if (buyNow.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: InkWell(
          onTap: () => context.push(AppRoutes.restock),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.shopping_basket_outlined,
                      size: 18,
                      color: colors.warning,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      l10n.restockPlan_cardTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => context.push(AppRoutes.restock),
                      child: Text(l10n.dashboard_viewAll),
                    ),
                  ],
                ),
                Text(
                  l10n.restockPlan_cardSummary(Qty.format(buyNow.length)),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                for (final i in buyNow.take(2))
                  Text(
                    l10n.restockPlan_cardItem(
                      i.product.name,
                      daysLeftShort(l10n, i),
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: i.daysLeft <= 2
                          ? colors.negative
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Put it on Home**

In `dashboard_screen.dart`, import `'../../restock/presentation/restock_card.dart'`. Replace:

```dart
              const Entrance(index: 6, child: ExpiryAlertsCard()),
              Entrance(
                index: 7,
                child: _LowStockCard(products: lowStock, currency: currency),
              ),
```

with:

```dart
              const Entrance(index: 6, child: RestockSoonCard()),
              const Entrance(index: 7, child: ExpiryAlertsCard()),
              Entrance(
                index: 8,
                child: _LowStockCard(products: lowStock, currency: currency),
              ),
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/widgets/restock_card_test.dart`
Expected: 3 tests PASS.

- [ ] **Step 7: Analyze, run the full suite, commit**

Run `flutter analyze` (expected: No issues found) and `flutter test` (expected: all pass). If an existing dashboard test now fails because `restockSpeedsProvider` reaches Supabase, add `restockPlanProvider.overrideWithValue(const AsyncValue.data(RestockPlan.empty))` to that test's overrides, and ledger it as a ruling.

```bash
dart format lib/features/restock/presentation/restock_card.dart lib/features/dashboard/presentation/dashboard_screen.dart test/widgets/restock_card_test.dart
git add lib/features/restock/presentation/restock_card.dart lib/features/dashboard/presentation/dashboard_screen.dart lib/l10n test/widgets/restock_card_test.dart
git commit -m "feat(restock): Home 'Restock soon' card

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Docs, build, install

**Files:**
- Modify: `docs/superpowers/specs/2026-10-15-restock-planner-design.md` (status line)
- Modify: `docs/00-Map.md` (Restock planner entry)

- [ ] **Step 1: Update the spec status line**

Replace `Status: approved in conversation 2026-10-15 (rule and screens). Spec awaiting review.` with `Status: built 2026-10-15 (migration 0017). Plan: [[2026-10-15-restock-planner|Plan]].`

Then append a `## 9. Build notes` section listing every `Ruling:` line from the ledger, each with its one-line reason.

- [ ] **Step 2: Update the map entry**

In `docs/00-Map.md`, change `- [[2026-10-15-restock-planner-design|Design]] (spec, not built yet)` to `- [[2026-10-15-restock-planner-design|Design]] / [[2026-10-15-restock-planner|Plan]] (built 2026-10-15, migration 0017)`. Keep the rest of the line.

- [ ] **Step 3: Commit (map hunk only)**

```bash
rtk proxy git diff docs/00-Map.md | awk '/^@@/{n++} n<2{print}' > .git/x.patch && git apply --cached .git/x.patch && rm .git/x.patch
git add docs/superpowers/specs/2026-10-15-restock-planner-design.md docs/superpowers/plans/2026-10-15-restock-planner.md
git commit -m "docs(restock): mark planner built

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 4: Build and install**

```bash
flutter build apk --release --dart-define-from-file=dart_defines.json
adb -s R5CT44FKMQH install -r build/app/outputs/flutter-apk/app-release.apk
```

Expected: `√ Built ...app-release.apk`, then `Success`.
