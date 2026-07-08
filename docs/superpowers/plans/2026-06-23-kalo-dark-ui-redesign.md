# Kalo-dark UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-skin the entire AI Shopkeeper app to a dark-only, lime-accented bento aesthetic (Kalo-style) without changing any data, routing, or state logic.

**Architecture:** Theme-led re-skin. A single dark `ThemeData` + recolored `AppColors` extension drives ~80% of the change. Shared widgets are restyled in place; four new `fl_chart`-based chart widgets are added; each screen gets a targeted layout pass to hit the bento grid + hero numbers. Riverpod controllers, repositories, RPCs, `go_router`, and domain models are untouched.

**Tech Stack:** Flutter (Material 3), Riverpod, go_router, fl_chart ^1.2.0 (already a dependency), google_fonts (Inter).

**Testing note:** Visual design is not unit-testable. This plan uses Flutter **widget tests** only for testable *behavior* (FAB callback fires, dark theme is applied, hero `MetricCard` paints lime, `SegmentPills` marks the active value). Pure styling changes are verified with `flutter analyze` (must stay clean) plus a manual visual check against `UI-UX design/3.jpg` (Kalo). Reference spec: `docs/superpowers/specs/2026-06-23-kalo-dark-ui-redesign-design.md`.

**Pre-flight (run once before Task 1):**
```bash
flutter pub get && flutter analyze
```
Expected: analyze passes (baseline clean) so later regressions are attributable to this work.

---

## File Structure

**Modified:**
- `lib/core/config/theme.dart` — dark-only tokens, lime accent, extended `AppColors`
- `lib/app.dart` — force `ThemeMode.dark`
- `lib/core/widgets/segment_pills.dart`, `delta_chip.dart`, `rounded_icon_tile.dart`, `metric_card.dart` (+ `filled` hero variant), `app_bottom_nav.dart` (+ center FAB)
- `lib/features/shell/presentation/main_shell.dart` — FAB wiring + quick-action sheet
- `lib/features/analytics/presentation/sales_chart.dart` — recolor existing charts
- Screen files: dashboard, analytics, inventory (list/detail/form), insights, trends, auth (login/profile), onboarding, settings, more, transaction confirmation sheet

**Created:**
- `lib/core/widgets/gradient_bars.dart` — `GradientBars`
- `lib/core/widgets/trend_line.dart` — `TrendLine`
- `lib/core/widgets/donut_chart.dart` — `DonutChart`
- `lib/core/widgets/streak_ring.dart` — `StreakRing`
- `lib/features/shell/presentation/quick_action_sheet.dart` — FAB sheet
- `test/widgets/metric_card_test.dart`, `test/widgets/app_bottom_nav_test.dart`, `test/theme_test.dart`

---

## Task 1: Dark-only theme + lime tokens

**Files:**
- Modify: `lib/core/config/theme.dart`
- Modify: `lib/app.dart:18-21`
- Test: `test/theme_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/theme_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_shopkeeper/core/config/theme.dart';

void main() {
  test('dark theme uses near-black scaffold and lime primary', () {
    final t = AppTheme.dark;
    expect(t.brightness, Brightness.dark);
    expect(t.scaffoldBackgroundColor, const Color(0xFF0A0A0A));
    expect(t.colorScheme.primary, const Color(0xFFC6F432));
  });

  test('AppColors exposes lime positive and warning', () {
    final c = AppTheme.dark.extension<AppColors>()!;
    expect(c.positive, const Color(0xFFC6F432));
    expect(c.warning, const Color(0xFFFFB020));
  });
}
```

Note: confirm the package name in the import — check `name:` in `pubspec.yaml`. If it is not `ai_shopkeeper`, use the actual value in all `package:` imports in this plan.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/theme_test.dart`
Expected: FAIL — `warning` getter undefined on `AppColors`; scaffold/primary colors mismatch.

- [ ] **Step 3: Extend `AppColors` with `warning` + `heroOnAccent`**

In `lib/core/config/theme.dart`, add two fields to the `AppColors` class (constructor, fields, `copyWith`, and `lerp`):

```dart
  const AppColors({
    required this.positive,
    required this.negative,
    required this.warning,
    required this.muted,
    required this.navBar,
    required this.onNavBar,
    required this.heroOnAccent,
  });

  final Color positive;
  final Color negative;
  final Color warning;       // low-stock / caution
  final Color muted;
  final Color navBar;
  final Color onNavBar;
  final Color heroOnAccent;  // text/icon on a lime-filled hero card
```

Update `copyWith` to accept and pass `warning` and `heroOnAccent`, and `lerp` to interpolate both:

```dart
      warning: Color.lerp(warning, other.warning, t)!,
      heroOnAccent: Color.lerp(heroOnAccent, other.heroOnAccent, t)!,
```

- [ ] **Step 4: Rewrite `AppTheme` to dark-only lime tokens**

Replace the brand/positive/negative constants and the `_build` colors in `lib/core/config/theme.dart`:

```dart
  static const Color brand = Color(0xFFC6F432);      // lime accent
  static const Color brandDeep = Color(0xFFB4E600);  // gradient end / pressed
  static const Color _positive = Color(0xFFC6F432);  // profit / up = lime
  static const Color _negative = Color(0xFFFF5C5C);
  static const Color _warning = Color(0xFFFFB020);
  static const Color _bg = Color(0xFF0A0A0A);
  static const Color _card = Color(0xFF141414);
  static const Color _cardRaised = Color(0xFF1C1C1C);
  static const Color _border = Color(0xFF242424);

  // Keep light/dark getters so callers don't break, but both return dark.
  static ThemeData get light => _build();
  static ThemeData get dark => _build();

  static ThemeData _build() {
    final scheme = ColorScheme.fromSeed(
      seedColor: brand,
      brightness: Brightness.dark,
    ).copyWith(
      primary: brand,
      onPrimary: _bg,
      surface: _bg,
      surfaceContainerLowest: _card,
      surfaceContainerLow: _card,
      surfaceContainer: _cardRaised,
      onSurface: Colors.white,
      onSurfaceVariant: const Color(0xFF8A8A8A),
      outlineVariant: _border,
    );

    final textTheme = _typography(Brightness.dark);
    const cardColor = _card;

    final appColors = AppColors(
      positive: _positive,
      negative: _negative,
      warning: _warning,
      muted: _cardRaised,
      navBar: const Color(0xFF000000),
      onNavBar: const Color(0xFF8A8A8A),
      heroOnAccent: _bg,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: _bg,
      textTheme: textTheme,
      extensions: [appColors],
      appBarTheme: AppBarTheme(
        backgroundColor: _bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        clipBehavior: Clip.antiAlias,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brand,
          foregroundColor: _bg,
          minimumSize: const Size.fromHeight(52),
          shape: const StadiumBorder(),
          textStyle: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: const StadiumBorder(),
          side: const BorderSide(color: _border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _cardRaised,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: brand, width: 1.6),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide.none,
        backgroundColor: _cardRaised,
      ),
      dividerTheme: const DividerThemeData(color: _border, space: 1),
    );
  }
```

Keep the existing `_typography(...)` method and `_typeScale` exactly as-is (only its call site changes — it is still called with `Brightness.dark`). Delete the now-unused `isLight` branches.

- [ ] **Step 5: Force dark mode in `app.dart`**

In `lib/app.dart`, change the theme wiring so the app is always dark regardless of the persisted `themeMode`:

```dart
    return MaterialApp.router(
      title: 'AI Shopkeeper',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: router,
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: 1.0,
        maxScaleFactor: 1.0,
        child: child!,
      ),
    );
```

Remove the now-unused `themeMode` local and the `themeModeProvider` import from this file. Leave `theme_mode_provider.dart` in place (Settings may still reference it; it is simply ignored for theme selection now).

- [ ] **Step 6: Run tests + analyze**

Run: `flutter test test/theme_test.dart && flutter analyze`
Expected: theme test PASS; analyze clean (fix any unused-import/variable warnings introduced by removing the light branch).

- [ ] **Step 7: Commit**

```bash
git add lib/core/config/theme.dart lib/app.dart test/theme_test.dart
git commit -m "feat(theme): dark-only lime tokens for Kalo redesign"
```

---

## Task 2: Restyle foundational shared widgets

**Files:**
- Modify: `lib/core/widgets/segment_pills.dart:85-91`, `lib/core/widgets/delta_chip.dart`, `lib/core/widgets/rounded_icon_tile.dart`, `lib/core/widgets/metric_card.dart`
- Test: `test/widgets/metric_card_test.dart`

- [ ] **Step 1: Write the failing test for the hero `MetricCard`**

```dart
// test/widgets/metric_card_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_shopkeeper/core/config/theme.dart';
import 'package:ai_shopkeeper/core/widgets/metric_card.dart';

void main() {
  testWidgets('filled MetricCard renders with lime background', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: const Scaffold(
        body: MetricCard(label: 'Revenue', value: r'$5,230', filled: true),
      ),
    ));
    final card = tester.widget<Card>(find.byType(Card));
    expect(card.color, const Color(0xFFC6F432));
    expect(find.text(r'$5,230'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/metric_card_test.dart`
Expected: FAIL — `MetricCard` has no `filled` parameter.

- [ ] **Step 3: Add the `filled` hero variant to `MetricCard`**

In `lib/core/widgets/metric_card.dart`, add `this.filled = false` to the constructor and `final bool filled;` field. In `build`, derive colors from `filled` and pass an explicit `color:` to the `Card`:

```dart
    final theme = Theme.of(context);
    final appColors = theme.extension<AppColors>()!;
    final accent = color ?? theme.colorScheme.primary;
    final onCard = filled ? appColors.heroOnAccent : Colors.white;
    final labelColor = filled
        ? appColors.heroOnAccent.withValues(alpha: 0.7)
        : theme.colorScheme.onSurfaceVariant;
    final valueStyle = theme.textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w800,
      color: onCard,
    );
```

Add `import '../config/theme.dart';` at the top. Set `Card(color: filled ? theme.colorScheme.primary : null, ...)`. Use `labelColor` for the label `Text`, `onCard` for the icon and subtitle, and pass `valueStyle` (already colored) to the value. Leave the static-vs-animated value branch logic unchanged.

- [ ] **Step 4: Run the hero test to verify it passes**

Run: `flutter test test/widgets/metric_card_test.dart`
Expected: PASS.

- [ ] **Step 5: Recolor `SegmentPills` active text to on-accent**

In `lib/core/widgets/segment_pills.dart`, the active pill background already uses `scheme.primary` (now lime). Change the active label color from `Colors.white` to the near-black on-accent so text is legible on lime. Replace line ~87:

```dart
                color: selected ? const Color(0xFF0A0A0A) : scheme.onSurfaceVariant,
```

- [ ] **Step 6: Verify `DeltaChip` + `RoundedIconTile` need no code change**

`DeltaChip` reads `AppColors.positive/negative` (now lime/`#FF5C5C`) — correct automatically. `RoundedIconTile` uses `accent.withValues(alpha: 0.14)` over a dark card — reads fine on lime/amber. No edits; just confirm by reading both files.

- [ ] **Step 7: Analyze + commit**

Run: `flutter analyze`
Expected: clean.

```bash
git add lib/core/widgets/metric_card.dart lib/core/widgets/segment_pills.dart test/widgets/metric_card_test.dart
git commit -m "feat(widgets): lime hero MetricCard + dark pill restyle"
```

---

## Task 3: Bottom nav center FAB + quick-action sheet

**Files:**
- Modify: `lib/core/widgets/app_bottom_nav.dart`
- Create: `lib/features/shell/presentation/quick_action_sheet.dart`
- Modify: `lib/features/shell/presentation/main_shell.dart`
- Test: `test/widgets/app_bottom_nav_test.dart`

- [ ] **Step 1: Write the failing test for the FAB callback**

```dart
// test/widgets/app_bottom_nav_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_shopkeeper/core/config/theme.dart';
import 'package:ai_shopkeeper/core/widgets/app_bottom_nav.dart';

void main() {
  testWidgets('tapping center FAB invokes onFabTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        bottomNavigationBar: AppBottomNav(
          items: const [
            AppNavItem(icon: Icons.home_rounded, label: 'Home'),
            AppNavItem(icon: Icons.inventory_2_rounded, label: 'Inventory'),
            AppNavItem(icon: Icons.bar_chart_rounded, label: 'Analytics'),
            AppNavItem(icon: Icons.grid_view_rounded, label: 'More'),
          ],
          currentIndex: 0,
          onTap: (_) {},
          onFabTap: () => tapped = true,
        ),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('nav-fab')));
    expect(tapped, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/app_bottom_nav_test.dart`
Expected: FAIL — `AppBottomNav` has no `onFabTap`; no `nav-fab` key.

- [ ] **Step 3: Add the center FAB to `AppBottomNav`**

In `lib/core/widgets/app_bottom_nav.dart`, add `required this.onFabTap` to the constructor and `final VoidCallback onFabTap;`. Insert a FAB into the middle of the nav `Row`. Split the items so two sit left of the FAB and the rest right; render the FAB between them:

```dart
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i == items.length ~/ 2) _Fab(onTap: onFabTap, color: scheme.primary),
                Flexible(
                  child: _NavButton(
                    item: items[i],
                    selected: i == currentIndex,
                    activeColor: scheme.primary,
                    inactiveColor: colors.onNavBar,
                    onTap: () => onTap(i),
                  ),
                ),
              ],
            ],
          ),
```

Also change the active `_NavButton` pill text/icon color from `Colors.white` to `const Color(0xFF0A0A0A)` (legible on lime). Add the FAB widget:

```dart
class _Fab extends StatelessWidget {
  const _Fab({required this.onTap, required this.color});
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: InkResponse(
        key: const ValueKey('nav-fab'),
        onTap: onTap,
        radius: 32,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.45),
                blurRadius: 18,
                spreadRadius: 1,
              ),
            ],
          ),
          child: const Icon(Icons.add_rounded, color: Color(0xFF0A0A0A), size: 28),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/app_bottom_nav_test.dart`
Expected: PASS.

- [ ] **Step 5: Create the quick-action sheet**

```dart
// lib/features/shell/presentation/quick_action_sheet.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/rounded_icon_tile.dart';

/// Bottom sheet opened by the nav FAB. Two live actions (Record sale, Add
/// product) and two stubbed device-plugin seams (Voice, Scan) owned by Member C.
class QuickActionSheet extends StatelessWidget {
  const QuickActionSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        backgroundColor: const Color(0xFF141414),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (_) => const QuickActionSheet(),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A2A),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Quick actions',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            _ActionRow(
              icon: Icons.point_of_sale_rounded,
              label: 'Record sale',
              onTap: () {
                Navigator.pop(context);
                context.go('/'); // sale flow lives on dashboard/inventory; adjust if a dedicated route exists
              },
            ),
            _ActionRow(
              icon: Icons.add_box_rounded,
              label: 'Add product',
              onTap: () {
                Navigator.pop(context);
                context.push('/inventory/new');
              },
            ),
            // MEMBER C: mic plugin wires here. Stub until the speech layer lands.
            _ActionRow(
              icon: Icons.mic_rounded,
              label: 'Voice',
              onTap: () => _comingSoon(context, 'Voice capture'),
            ),
            // MEMBER C: camera plugin wires here -> upload to Storage -> Member B vision fn.
            _ActionRow(
              icon: Icons.photo_camera_rounded,
              label: 'Scan image',
              onTap: () => _comingSoon(context, 'Image scan'),
            ),
          ],
        ),
      ),
    );
  }

  void _comingSoon(BuildContext context, String what) {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$what is coming soon')),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: RoundedIconTile(icon: icon),
      title: Text(label,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w600)),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
```

Before relying on the `/inventory/new` route, confirm it exists in `lib/core/router/app_router.dart`. If the product-form route differs (e.g. `/inventory/add`), use the actual path. If no dedicated "record sale" route exists, keep the `context.go('/')` line so the FAB still leads to the sale entry point on the dashboard; note this for the screen task.

- [ ] **Step 6: Wire the FAB in `main_shell.dart`**

In `lib/features/shell/presentation/main_shell.dart`, add the `onFabTap` callback:

```dart
import '../../../core/widgets/app_bottom_nav.dart';
import 'quick_action_sheet.dart';
// ...
      bottomNavigationBar: Builder(
        builder: (context) => AppBottomNav(
          items: _items,
          currentIndex: navigationShell.currentIndex,
          onTap: _onTap,
          onFabTap: () => QuickActionSheet.show(context),
        ),
      ),
```

(The `Builder` provides a `context` beneath the `Navigator`/`GoRouter` so `showModalBottomSheet` and `context.push` resolve.)

- [ ] **Step 7: Analyze, test, commit**

Run: `flutter analyze && flutter test test/widgets/app_bottom_nav_test.dart`
Expected: clean + PASS.

```bash
git add lib/core/widgets/app_bottom_nav.dart lib/features/shell/presentation/ test/widgets/app_bottom_nav_test.dart
git commit -m "feat(nav): center lime FAB + quick-action sheet"
```

---

## Task 4: New rich chart widgets

**Files:**
- Create: `lib/core/widgets/gradient_bars.dart`, `lib/core/widgets/trend_line.dart`, `lib/core/widgets/donut_chart.dart`, `lib/core/widgets/streak_ring.dart`

No unit tests (visual `fl_chart` output). Verify each compiles via `flutter analyze` and renders in the screens that consume them (Tasks 5-6).

- [ ] **Step 1: `GradientBars`**

```dart
// lib/core/widgets/gradient_bars.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../config/motion.dart';
import '../config/theme.dart';

/// Vertical bars with a lime->amber vertical gradient. The bar at [highlight]
/// (the peak by default) is drawn brighter. [labels] are the x-axis captions.
class GradientBars extends StatelessWidget {
  const GradientBars({
    super.key,
    required this.values,
    required this.labels,
    this.highlight,
    this.height = 180,
  });

  final List<double> values;
  final List<String> labels;
  final int? highlight;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).extension<AppColors>()!;
    final maxVal = values.isEmpty ? 1.0 : values.reduce((a, b) => a > b ? a : b);
    final maxY = maxVal <= 0 ? 1.0 : maxVal * 1.2;
    final peak = highlight ??
        (values.isEmpty
            ? 0
            : values.indexOf(values.reduce((a, b) => a > b ? a : b)));

    return SizedBox(
      height: height,
      child: BarChart(
        duration: AppMotion.reduced(context) ? Duration.zero : AppMotion.medium,
        curve: AppMotion.easeOut,
        BarChartData(
          maxY: maxY,
          alignment: BarChartAlignment.spaceAround,
          borderData: FlBorderData(show: false),
          gridData: const FlGridData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= labels.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(labels[i],
                        style: Theme.of(context).textTheme.labelSmall),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < values.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: values[i],
                    width: 14,
                    borderRadius: BorderRadius.circular(6),
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: i == peak
                          ? [scheme.primary, appColors.warning]
                          : [
                              scheme.primary.withValues(alpha: 0.55),
                              scheme.primary.withValues(alpha: 0.85),
                            ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: `TrendLine`**

```dart
// lib/core/widgets/trend_line.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../config/motion.dart';

/// Smooth line with a faint area fill and a dot on the final point — the Kalo
/// "weight trend" style. [labels] caption the x-axis.
class TrendLine extends StatelessWidget {
  const TrendLine({
    super.key,
    required this.values,
    required this.labels,
    this.height = 160,
  });

  final List<double> values;
  final List<String> labels;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (values.isEmpty) return SizedBox(height: height);
    final lastIndex = values.length - 1;

    return SizedBox(
      height: height,
      child: LineChart(
        duration: AppMotion.reduced(context) ? Duration.zero : AppMotion.medium,
        curve: AppMotion.easeOut,
        LineChartData(
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= labels.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(labels[i],
                        style: Theme.of(context).textTheme.labelSmall),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < values.length; i++)
                  FlSpot(i.toDouble(), values[i]),
              ],
              isCurved: true,
              color: scheme.primary,
              barWidth: 3,
              dotData: FlDotData(
                show: true,
                checkToShowDot: (spot, _) => spot.x == lastIndex.toDouble(),
                getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                  radius: 5,
                  color: scheme.primary,
                  strokeColor: const Color(0xFF0A0A0A),
                  strokeWidth: 2,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    scheme.primary.withValues(alpha: 0.25),
                    scheme.primary.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: `DonutChart`**

```dart
// lib/core/widgets/donut_chart.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// One slice of a [DonutChart].
class DonutSlice {
  const DonutSlice({required this.label, required this.value, required this.color});
  final String label;
  final double value;
  final Color color;
}

/// Category-mix ring with a centered total and a side legend.
class DonutChart extends StatelessWidget {
  const DonutChart({super.key, required this.slices, this.size = 120});

  final List<DonutSlice> slices;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = slices.fold<double>(0, (s, e) => s + e.value);
    return Row(
      children: [
        SizedBox(
          width: size,
          height: size,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: size * 0.32,
              sections: [
                for (final s in slices)
                  PieChartSectionData(
                    value: s.value,
                    color: s.color,
                    radius: size * 0.18,
                    showTitle: false,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final s in slices)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                            color: s.color, borderRadius: BorderRadius.circular(3)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(s.label,
                            style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis),
                      ),
                      Text(
                        total <= 0 ? '0%' : '${(s.value / total * 100).round()}%',
                        style: theme.textTheme.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: `StreakRing`**

```dart
// lib/core/widgets/streak_ring.dart
import 'package:flutter/material.dart';

import '../config/theme.dart';

/// A glowing circular progress ring around a center icon — the Kalo "streak"
/// element. [progress] is 0..1; the ring glows with the accent.
class StreakRing extends StatelessWidget {
  const StreakRing({
    super.key,
    required this.progress,
    this.icon = Icons.local_fire_department_rounded,
    this.size = 64,
  });

  final double progress;
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final appColors = Theme.of(context).extension<AppColors>()!;
    final glow = appColors.warning;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: glow.withValues(alpha: 0.5), blurRadius: 16)],
            ),
          ),
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              strokeWidth: 4,
              backgroundColor: const Color(0xFF2A2A2A),
              valueColor: AlwaysStoppedAnimation(glow),
            ),
          ),
          Icon(icon, color: glow, size: size * 0.4),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Analyze + commit**

Run: `flutter analyze`
Expected: clean.

```bash
git add lib/core/widgets/gradient_bars.dart lib/core/widgets/trend_line.dart lib/core/widgets/donut_chart.dart lib/core/widgets/streak_ring.dart
git commit -m "feat(widgets): gradient bars, trend line, donut, streak ring"
```

---

## Task 5: Dashboard redesign

**Files:**
- Modify: `lib/features/dashboard/presentation/dashboard_screen.dart`
- Modify: `lib/features/dashboard/presentation/revenue_card.dart` (if it hard-codes light colors)

- [ ] **Step 1: Read the current dashboard + revenue/profit cards**

Read `dashboard_screen.dart`, `revenue_card.dart`, `profit_card.dart` in full. Confirm `RevenueCard`/`ProfitCard` derive colors from theme; if either hard-codes a light color, switch it to `Theme.of(context)` tokens.

- [ ] **Step 2: Make the revenue card the lime hero**

In `dashboard_screen.dart`, replace the `RevenueCard` usage at index 2 with a full-width hero built from the new widgets. Above the 2-up metric rows, insert:

```dart
              summaryAsync.when(
                loading: () => const _SummarySkeleton(),
                error: (_, _) => const _ErrorText('Could not load summary.'),
                data: (s) => Column(
                  children: [
                    Entrance(
                      index: 2,
                      child: _RevenueHero(
                        revenue: s.revenue,
                        currency: currency,
                        seriesAsync: seriesAsync,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Entrance(
                            index: 3,
                            child: ProfitCard(profit: s.profit, currency: currency),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Entrance(
                            index: 4,
                            child: MetricCard(
                              label: 'Units sold',
                              value: '${s.unitsSold}',
                              animatedValue: s.unitsSold.toDouble(),
                              valueFormatter: (v) => v.round().toString(),
                              icon: Icons.shopping_cart_outlined,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Entrance(
                      index: 5,
                      child: MetricCard(
                        label: 'Inventory value',
                        value: Money.format(s.inventoryValue, currencyCode: currency),
                        animatedValue: s.inventoryValue,
                        valueFormatter: (v) => Money.format(v, currencyCode: currency),
                        icon: Icons.inventory_2_outlined,
                      ),
                    ),
                  ],
                ),
              ),
```

Add the hero widget at the bottom of the file (it embeds `GradientBars` from the 7-day series):

```dart
class _RevenueHero extends StatelessWidget {
  const _RevenueHero({
    required this.revenue,
    required this.currency,
    required this.seriesAsync,
  });

  final double revenue;
  final String currency;
  final AsyncValue<List<SalesPoint>> seriesAsync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = theme.extension<AppColors>()!;
    return Card(
      color: theme.colorScheme.primary,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Revenue',
                style: theme.textTheme.titleSmall
                    ?.copyWith(color: appColors.heroOnAccent.withValues(alpha: 0.7))),
            const SizedBox(height: 6),
            AnimatedCount(
              value: revenue,
              formatter: (v) => Money.format(v, currencyCode: currency),
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: appColors.heroOnAccent,
              ),
            ),
            const SizedBox(height: 16),
            seriesAsync.when(
              loading: () => const SizedBox(height: 120),
              error: (_, _) => const SizedBox(height: 120),
              data: (points) => GradientBars(
                values: [for (final p in points) p.revenue],
                labels: [for (final p in points) DateFormat('E').format(p.bucket).substring(0, 1)],
                height: 120,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

Add imports at the top of `dashboard_screen.dart`: `import 'package:intl/intl.dart';`, `import '../../../core/config/theme.dart';`, `import '../../../core/widgets/gradient_bars.dart';`. Remove the now-unused `revenue_card.dart` import and the old `_OverallSalesCard` if it is no longer referenced (or keep `_OverallSalesCard` lower on the screen if you prefer a second chart — your call, but remove dead code so analyze stays clean).

- [ ] **Step 3: Recolor the low-stock row warning tile**

In the `_LowStockRow` widget, change `RoundedIconTile(icon: Icons.warning_amber_rounded, color: scheme.error)` to use the warning token:

```dart
            leading: RoundedIconTile(
              icon: Icons.warning_amber_rounded,
              color: Theme.of(context).extension<AppColors>()!.warning,
            ),
```

- [ ] **Step 4: Analyze + run app sanity**

Run: `flutter analyze`
Expected: clean (resolve any unused imports from the swap).

- [ ] **Step 5: Commit**

```bash
git add lib/features/dashboard/
git commit -m "feat(dashboard): lime revenue hero + bento metrics"
```

---

## Task 6: Analytics redesign

**Files:**
- Modify: `lib/features/analytics/presentation/analytics_screen.dart`
- Modify: `lib/features/analytics/presentation/sales_chart.dart`

- [ ] **Step 1: Read `analytics_screen.dart` and `analytics_controller.dart`**

Identify the providers feeding the screen (period summary, series, and any category breakdown). Note the exact provider names and model fields for revenue/profit/category so the new widgets bind to real data. If there is **no** category-breakdown provider, the donut uses a simple grouping you can derive client-side from products, or is omitted — decide based on what exists and keep it honest (do not invent a provider).

- [ ] **Step 2: Swap the bar chart to gradient + recolor profit line**

In `sales_chart.dart`, the existing `SalesBarChart` uses `scheme.primary`/`scheme.tertiary`. Leave its structure but change the profit rod color to a muted lime and keep revenue lime, so the dark theme reads correctly:

```dart
                      BarChartRodData(
                        toY: points[i].revenue,
                        color: scheme.primary,
                        width: 7,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      BarChartRodData(
                        toY: points[i].profit,
                        color: scheme.primary.withValues(alpha: 0.45),
                        width: 7,
                        borderRadius: BorderRadius.circular(2),
                      ),
```

Update the `_legend(scheme.tertiary, 'Profit')` call to `_legend(scheme.primary.withValues(alpha: 0.45), 'Profit')`.

- [ ] **Step 3: Restructure the analytics screen into Kalo bento cards**

In `analytics_screen.dart`, present, in order: `SegmentPills` (already present) → a "Revenue by day" card wrapping `GradientBars` with a `DeltaChip` showing vs-last-period → a "Profit trend" card wrapping `TrendLine` → a 2-up row of a Streak/Best-day `MetricCard` and a `DonutChart` card (only if category data exists). Each chart sits inside a `Card` with a title row:

```dart
Card(
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Revenue by day',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            if (deltaPercent != null) DeltaChip(percent: deltaPercent),
          ],
        ),
        const SizedBox(height: 12),
        GradientBars(values: revenueValues, labels: dayLabels),
      ],
    ),
  ),
),
```

Bind `revenueValues`/`dayLabels`/`deltaPercent` to the real provider values found in Step 1. Add imports for `gradient_bars.dart`, `trend_line.dart`, `donut_chart.dart`, and `delta_chip.dart`.

- [ ] **Step 4: Analyze + commit**

Run: `flutter analyze`
Expected: clean.

```bash
git add lib/features/analytics/
git commit -m "feat(analytics): gradient bars, trend line, donut bento"
```

---

## Task 7: Inventory list, detail, and form

**Files:**
- Modify: `lib/features/inventory/presentation/inventory_list_screen.dart`, `product_detail_screen.dart`, `product_form_screen.dart`, `category_picker.dart`, `manage_categories_screen.dart`

- [ ] **Step 1: Read all five inventory presentation files**

Note how product rows, the search field, and the form fields are currently built and which colors they reference.

- [ ] **Step 2: Restyle the list header + product rows**

Give the list a large bold "Inventory" title with circular filter/add buttons (use `RoundedIconTile` inside an `InkResponse`, or `IconButton` in a circular `Ink`). Product rows become dark `Card`s (radius 24 via theme) with a thumbnail (`RoundedTextTile` for the product initial when no image), name (`titleMedium w600`), a quantity pill, and — when `product.isLowStock` — an amber accent: wrap the qty pill background in `AppColors.warning.withValues(alpha: 0.15)` with `warning` text. Concrete qty-pill:

```dart
Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  decoration: BoxDecoration(
    color: (product.isLowStock
            ? Theme.of(context).extension<AppColors>()!.warning
            : Theme.of(context).colorScheme.primary)
        .withValues(alpha: 0.15),
    borderRadius: BorderRadius.circular(20),
  ),
  child: Text(
    '${product.quantity}',
    style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: product.isLowStock
              ? Theme.of(context).extension<AppColors>()!.warning
              : Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
  ),
),
```

- [ ] **Step 3: Confirm detail + form inherit theme**

Detail and form screens should already pick up the dark `inputDecorationTheme` (lime focus) and `filledButtonTheme` (lime stadium). Read both; remove any hard-coded `Colors.white`/light surfaces, replacing with `Theme.of(context).colorScheme.surface`/`surfaceContainer`. Add `import '../../../core/config/theme.dart';` where `AppColors` is used.

- [ ] **Step 4: Analyze + commit**

Run: `flutter analyze`
Expected: clean.

```bash
git add lib/features/inventory/
git commit -m "feat(inventory): dark bento list + low-stock amber pills"
```

---

## Task 8: Insights and Trends (read-only Member-B JSON)

**Files:**
- Modify: `lib/features/insights/presentation/insights_screen.dart`, `lib/features/trends/presentation/trend_screen.dart`

- [ ] **Step 1: Read both screens**

Confirm they render Member B's JSON read-only and note the current card structure.

- [ ] **Step 2: Restyle insight/trend items into dark bento cards**

Wrap each insight/trend entry in a `Card` (theme radius 24) with a `RoundedIconTile` leading icon (lime), a `titleMedium w600` headline, and `bodySmall` muted body. Where a trend value implies up/down, reuse `DeltaChip`. Do not change the data shape or the `// MEMBER B` seam comments. Replace any hard-coded light colors with theme tokens.

- [ ] **Step 3: Analyze + commit**

Run: `flutter analyze`
Expected: clean.

```bash
git add lib/features/insights/ lib/features/trends/
git commit -m "feat(insights,trends): dark bento cards for Member B JSON"
```

---

## Task 9: Auth, onboarding, settings, more, confirmation sheet

**Files:**
- Modify: `lib/features/auth/presentation/login_screen.dart`, `profile_setup_screen.dart`
- Modify: `lib/features/onboarding/presentation/welcome_screen.dart`
- Modify: `lib/features/settings/presentation/settings_screen.dart`
- Modify: `lib/features/shell/presentation/more_screen.dart`
- Modify: `lib/features/transactions/presentation/transaction_confirmation_sheet.dart`

- [ ] **Step 1: Read all six files**

Note hard-coded colors, gradients, and any light-mode assumptions.

- [ ] **Step 2: Auth + onboarding**

Near-black scaffold (theme default now), lime `FilledButton` primary CTA (already themed), muted secondary text. Replace any white card backgrounds with `colorScheme.surfaceContainer`. Keep all auth logic and controller calls unchanged.

- [ ] **Step 3: Settings + More**

Grouped dark list rows with `RoundedIconTile` leading icons and `chevron_right_rounded` trailing. If Settings contains a light/dark theme toggle, leave the control present but note in a code comment that the app is dark-only for the MVP (`// dark-only MVP: toggle is a no-op for now`) — do not delete `theme_mode_provider.dart`.

- [ ] **Step 4: Confirmation sheet**

Dark sheet background (`#141414`), product summary rows in muted text, a lime `FilledButton` "Confirm sale" and an outlined "Cancel". The `record_sale` RPC call and its gating logic stay exactly as-is — this is the no-auto-commit guarantee.

- [ ] **Step 5: Analyze + commit**

Run: `flutter analyze`
Expected: clean.

```bash
git add lib/features/auth/ lib/features/onboarding/ lib/features/settings/ lib/features/shell/presentation/more_screen.dart lib/features/transactions/
git commit -m "feat(ui): dark restyle for auth, onboarding, settings, sheets"
```

---

## Task 10: Full verification pass

**Files:** none (verification only)

- [ ] **Step 1: Static analysis**

Run: `flutter analyze`
Expected: **No issues found.**

- [ ] **Step 2: Format**

Run: `dart format .`
Expected: files formatted; re-run `flutter analyze` to confirm still clean.

- [ ] **Step 3: Full test suite**

Run: `flutter test`
Expected: all tests PASS (theme, metric_card, app_bottom_nav, plus any pre-existing tests).

- [ ] **Step 4: Manual visual check**

Run the app (`flutter run` with the dart-defines from `RUN.md`) and walk: Dashboard → FAB sheet → Inventory → Analytics → Insights → Settings → Login (sign out). Compare Dashboard/Analytics against `UI-UX design/3.jpg`. Confirm: uniform near-black, lime accent only on active tab/FAB/hero/positive deltas, no light-mode flashes, charts render.

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "chore: format + final verification for Kalo-dark redesign"
```

---

## Self-Review Notes (addressed)

- **Spec coverage:** tokens (T1), shared widgets + hero (T2), FAB + sheet (T3), four charts (T4), every screen group (T5-T9), verification (T10). All spec §3-§9 items map to a task.
- **Type consistency:** `AppColors` gains `warning` + `heroOnAccent` in T1 and every later use references those exact names; `MetricCard.filled`, `AppBottomNav.onFabTap`, `GradientBars(values,labels,highlight)`, `TrendLine(values,labels)`, `DonutChart(slices)`/`DonutSlice`, `StreakRing(progress)` are defined once and used consistently.
- **Honesty flags:** Donut in Analytics (T6) is gated on a real category provider existing; the FAB "Record sale" route (T3) is gated on confirming the actual route name in `app_router.dart`. These are called out rather than assumed.
