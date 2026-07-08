# Kalo-dark UI Redesign — Design Spec

**Date:** 2026-06-23
**Owner:** Member A (Flutter + Supabase)
**Status:** Approved (design), pending spec review

## 1. Goal

Redesign the entire AI Shopkeeper Assistant UI to a premium **dark-mode bento
aesthetic** inspired by the five screenshots in `UI-UX design/` (E-Wallet,
Workouts, Kalo nutrition ×2, Activities fitness). The Kalo nutrition screens are
the primary reference because the app is analytics-heavy with period tabs,
charts, and insight cards.

This is a **presentation-layer redesign only**. Riverpod controllers,
repositories, RPC calls, routing logic, and data models are untouched. Member B
(AI) and Member C (device plugins) integration seams remain stubbed with their
existing `// MEMBER B` / `// MEMBER C` comments.

## 2. Approved decisions

| Decision | Choice |
|---|---|
| Approach | Theme-led re-skin + targeted per-screen layout passes (not a rewrite) |
| Accent | Lime-green `#C6F432` (Kalo) |
| Theme mode | **Dark-only** (remove light theme) |
| Scope | Full app, all screens |
| Bottom nav | 4 tabs **+ center lime FAB** opening a quick-action sheet |
| Charts | Full Kalo-rich (gradient bars, trend line w/ end-dot, donut, glowing streak ring) via `fl_chart ^1.2.0` (already a dependency) |

## 3. Design tokens (`lib/core/config/theme.dart`)

Dark-only. `AppTheme.light` is removed; `MaterialApp` uses a single dark theme
(set `themeMode: ThemeMode.dark` or pass `dark` to both slots).

**Color palette**

| Token | Value | Use |
|---|---|---|
| Background | `#0A0A0A` | scaffold |
| Card | `#141414` | standard bento card |
| Card raised / nested | `#1C1C1C` | nested tiles, sheets |
| Border hairline | `#242424` | card outlines, dividers |
| Accent (primary) | `#C6F432` | active tab, FAB, hero fill, chart highlight |
| Accent deep | `#B4E600` | gradient end, pressed states |
| On-accent | `#0A0A0A` | text/icons on lime fills |
| Text primary | `#FFFFFF` | hero numbers, titles |
| Text muted | `#8A8A8A` | labels, captions |
| Positive / up | `#C6F432` (lime) | profit, up deltas |
| Negative / down | `#FF5C5C` | loss, down deltas |
| Warning / low-stock | `#FFB020` | low-stock ring/chip |

**Shape & spacing**: cards radius 24; pills/buttons stadium; icon tiles radius
16. Screen padding 16; bento gutter 12. **Type**: keep Inter + tabular figures;
hero numbers `w800` at display sizes; labels `w500` muted. Keep the existing
`_typeScale` mechanism.

**`AppColors` extension** keeps its shape but is recolored: `positive` → lime,
`negative` → `#FF5C5C`, `muted` → `#1C1C1C`, `navBar` → `#000000`, `onNavBar` →
`#8A8A8A`. Add `warning` (`#FFB020`) and `heroOnAccent` (`#0A0A0A`) fields for
the lime hero card and low-stock states.

## 4. Shared widgets (restyle in place — `lib/core/widgets/`)

Logic/animation preserved; only visuals change unless noted.

- **`MetricCard`** — bento card: tiny muted label, huge `w800` number, optional
  `DeltaChip`, optional corner line-icon. New `filled` flag renders a lime hero
  card (lime bg, near-black text) for the dashboard headline stat.
- **`SegmentPills`** — Kalo period row: lime active pill, `#1C1C1C` track, muted
  inactive labels. Already generic; restyle only.
- **`AppBottomNav`** — 4 tabs **+ center FAB**. FAB is a lime circle with a
  near-black `+`. New `onFabTap` callback. Active tab keeps the expand-to-pill
  behavior, recolored lime. (See §6 for the FAB sheet.)
- **New `GradientBars`** — vertical bars with green→yellow vertical gradient, one
  highlighted bar (peak), muted weekday axis. `fl_chart` `BarChart`.
- **New `TrendLine`** — line chart with end-dot + floating value label, lime
  stroke, faint area gradient. `fl_chart` `LineChart`.
- **New `DonutChart`** — category-mix ring with legend (lime/olive/amber/grey
  segments). `fl_chart` `PieChart` with center hole.
- **New `StreakRing`** — circular progress ring with a lime/amber glow
  (`BoxShadow` blur) around a center icon/number. Custom painter or `fl_chart`.
- **`RoundedIconTile`, `DeltaChip`, `Skeleton`, `Entrance`, `Pressable`,
  `AnimatedCount`** — recolor to dark/lime; behavior unchanged.

## 5. Screen-by-screen

- **Dashboard** (`dashboard_screen.dart`): greeting row with circular
  profile/store button → `SegmentPills` period → **lime hero card** ("Revenue"
  for the period) with `GradientBars` → 2×2 bento (Profit / Units sold /
  Inventory value / Low-stock count) using `MetricCard` → "Needs attention"
  low-stock list (dark rows, amber warning tile).
- **Analytics** (`analytics_screen.dart` + `sales_chart.dart`): `SegmentPills`
  → revenue **`GradientBars`** card (highlighted peak day, "vs last period"
  delta chip) → profit **`TrendLine`** card → 2-up Streak/Best-day +
  **`DonutChart`** (sales by category) → insights bento row.
- **Inventory** (`inventory_list_screen.dart`): large "Inventory" title +
  circular filter/add buttons → search field (dark, lime focus) → product cards
  (dark, thumbnail, name, qty pill, amber ring when low-stock). `product_detail`
  & `product_form`: dark fields, lime focus border, stadium buttons.
- **Insights / Trends** (`insights_screen.dart`, `trend_screen.dart`): render
  Member B's JSON read-only in dark bento insight cards using the shared card
  language. No new data contracts.
- **Auth** (`login_screen.dart`, `profile_setup_screen.dart`): near-black, lime
  primary button, minimal fields. **Onboarding** (`welcome_screen.dart`):
  dark hero, lime CTA.
- **Settings / More** (`settings_screen.dart`, `more_screen.dart`): grouped dark
  list rows with circular leading icons.
- **Transaction confirmation sheet**
  (`transaction_confirmation_sheet.dart`): dark bottom sheet, product summary,
  lime confirm button. Still gated before `record_sale` RPC (never auto-commit).

## 6. Center FAB quick-action sheet

Tapping the nav FAB opens a dark bottom sheet with four actions:

1. **Record sale** → existing sale flow → `transaction_confirmation_sheet` →
   `record_sale` RPC.
2. **Add product** → `product_form_screen`.
3. **Voice** → `// MEMBER C` seam (mic plugin). Stub: opens a "coming soon" /
   wires to existing callback if present.
4. **Scan image** → `// MEMBER C` seam (camera) → upload to Storage → hand URL to
   Member B vision function. Stub for now.

Voice/Scan are stubbed seams — no new plugin work. They surface the entry points
the redesign promises without implementing Member C's layer.

## 7. Out of scope / unchanged

- Riverpod controllers, repositories, `record_sale` and analytics RPCs.
- `go_router` routes and the auth-redirect guard (nav shell wiring only changes
  to add the FAB callback).
- Domain models (`freezed`), Supabase schema, RLS.
- Light theme is **removed**, not maintained.
- Member B prompt/JSON shapes and Member C plugin implementations.

## 8. Sequencing & verification

1. Theme + tokens (`theme.dart`, `AppColors`) — everything depends on this.
2. Shared widgets restyle + new chart widgets.
3. `AppBottomNav` + FAB + quick-action sheet + `main_shell` wiring.
4. Dashboard (proves the system end-to-end).
5. Analytics.
6. Inventory (list + detail + form).
7. Remaining screens (Insights, Trends, Auth, Onboarding, Settings, More,
   confirmation sheet).

Run `flutter analyze` after each layer; `dart format .` before completion. No
new dependencies (fl_chart already present). Manual visual check on Dashboard &
Analytics against the Kalo screenshots.

## 9. Success criteria

- App is uniformly dark with the lime accent; no light-theme remnants.
- Dashboard & Analytics visibly match the Kalo bento + chart language.
- 4-tab nav + center lime FAB with working quick-action sheet.
- Rich charts render (gradient bars, trend line, donut, streak ring).
- `flutter analyze` clean; existing data flows still function.
