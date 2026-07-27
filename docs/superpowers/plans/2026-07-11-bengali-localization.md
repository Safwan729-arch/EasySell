# Bengali Localization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an in-app English⇄Bengali language switcher so the entire UI (labels, buttons, numbers, dates) follows the user's choice, persisted across launches.

**Architecture:** Flutter `gen-l10n` (ARB catalogs) provides typed strings via `context.l10n`. A Riverpod `localeProvider` (mirroring the existing `themeModeProvider`) holds the choice, persists it to SharedPreferences, and syncs `Intl.defaultLocale` so `intl` number/date formatters emit Bengali digits automatically. A bundled Bengali font renders Bengali glyphs. Strings are extracted screen-group by screen-group so partial progress always builds (untranslated text stays English).

**Tech Stack:** Flutter `flutter_localizations` + `gen-l10n`, `intl` (already present), Riverpod, `shared_preferences` (already present), Hind Siliguri font (OFL).

**Reference:** Spec at `docs/superpowers/specs/2026-07-11-bengali-localization-design.md`. Approved wording in `docs/superpowers/mockups/bengali-ui-mockup.html`.

**Bengali style:** natural shop Bengali, Bengali digits (০-৯). Product/user data is NOT translated.

---

## Bengali Glossary (use these consistently across all ARB entries)

| English | Bengali | | English | Bengali |
|---|---|---|---|---|
| Home | হোম | | Add to cart | কার্টে যোগ |
| Items / Products | পণ্য | | Checkout | চেকআউট |
| Reports | রিপোর্ট | | Remove | মুছুন |
| History | হিস্ট্রি | | Restock | রিস্টক |
| Inventory | পণ্যতালিকা | | Low stock | কম স্টক |
| Cart | কার্ট | | in stock | স্টকে |
| Settings | সেটিংস | | Sold | বিক্রি |
| Search | খুঁজুন | | Revenue | আয় |
| Profit | লাভ | | Margin | মার্জিন |
| Total | মোট | | Today / Week / Month | আজ / সপ্তাহ / মাস |
| Sign out | লগ আউট | | Sell | বিক্রি |
| Language | ভাষা | | Cancel | বাতিল |
| Save | সংরক্ষণ | | Retry | আবার চেষ্টা |
| Sale | বিক্রি | | Loading… | লোড হচ্ছে… |

Key naming convention: `<feature>_<meaning>`, lowerCamel meaning — e.g. `cart_checkout`, `inventory_title`, `settings_signOut`, `common_cancel`. Shared strings go under `common_`.

---

## Phase 1 — Localization infrastructure

### Task 1: Add localization deps + gen-l10n config + seed ARBs

**Files:**
- Modify: `pubspec.yaml`
- Create: `l10n.yaml`
- Create: `lib/l10n/app_en.arb`
- Create: `lib/l10n/app_bn.arb`

- [ ] **Step 1: Add `flutter_localizations` and `generate: true`**

In `pubspec.yaml`, under `dependencies:` (after `flutter:` sdk block):

```yaml
  flutter_localizations:
    sdk: flutter
```

Under the `flutter:` section (sibling to `uses-material-design: true`):

```yaml
  generate: true
```

- [ ] **Step 2: Create `l10n.yaml` at repo root**

```yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
output-class: AppLocalizations
synthetic-package: false
nullable-getter: false
```

- [ ] **Step 3: Create seed ARB catalogs**

`lib/l10n/app_en.arb`:
```json
{
  "@@locale": "en",
  "settings_title": "Settings"
}
```

`lib/l10n/app_bn.arb`:
```json
{
  "@@locale": "bn",
  "settings_title": "সেটিংস"
}
```

- [ ] **Step 4: Fetch deps and generate**

Run: `flutter pub get && flutter gen-l10n`
Expected: creates `lib/l10n/app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_bn.dart`. No errors.

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock l10n.yaml lib/l10n/
git commit -m "feat(l10n): add flutter_localizations + gen-l10n scaffolding"
```

### Task 2: `context.l10n` accessor

**Files:**
- Create: `lib/core/l10n/l10n_ext.dart`

- [ ] **Step 1: Write the extension**

```dart
import 'package:flutter/widgets.dart';

import 'package:ai_shopkeeper/l10n/app_localizations.dart';

/// Ergonomic access to generated strings: `context.l10n.settings_title`.
/// Non-null because `nullable-getter: false` is set in l10n.yaml.
extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
```

- [ ] **Step 2: Verify it analyzes**

Run: `flutter analyze lib/core/l10n/l10n_ext.dart`
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add lib/core/l10n/l10n_ext.dart
git commit -m "feat(l10n): context.l10n accessor extension"
```

### Task 3: `localeProvider` (mirror themeModeProvider) + persistence + Intl sync

**Files:**
- Create: `lib/shared/providers/locale_provider.dart`

- [ ] **Step 1: Write the provider**

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The languages the app ships. English is the template/fallback.
const supportedAppLocales = [Locale('en'), Locale('bn')];

/// Seeded at startup in `main()` from SharedPreferences (overridden in the
/// ProviderScope), mirroring [initialThemeModeProvider]. Falls back to English
/// during a hot reload (which never re-runs `main()`); a hot restart picks up
/// the persisted value.
final initialLocaleProvider = Provider<Locale>((ref) => const Locale('en'));

const _prefsKey = 'locale';

/// The app's active [Locale]. `MaterialApp.router` watches this. [setLocale]
/// updates it, syncs `Intl.defaultLocale` (so number/date formatters localize),
/// and persists so the choice survives restarts.
class LocaleController extends Notifier<Locale> {
  @override
  Locale build() {
    final loc = ref.watch(initialLocaleProvider);
    Intl.defaultLocale = loc.languageCode;
    return loc;
  }

  Future<void> setLocale(Locale locale) async {
    state = locale;
    Intl.defaultLocale = locale.languageCode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, locale.languageCode);
  }
}

final localeProvider = NotifierProvider<LocaleController, Locale>(
  LocaleController.new,
);

/// Reads the persisted language once, for seeding [initialLocaleProvider].
/// First launch with no stored choice follows the device locale when it is
/// Bengali, otherwise English.
Future<Locale> loadLocale() async {
  final prefs = await SharedPreferences.getInstance();
  final code = prefs.getString(_prefsKey);
  if (code == 'bn') return const Locale('bn');
  if (code == 'en') return const Locale('en');
  final device = WidgetsBinding.instance.platformDispatcher.locale;
  return device.languageCode == 'bn' ? const Locale('bn') : const Locale('en');
}
```

- [ ] **Step 2: Verify it analyzes**

Run: `flutter analyze lib/shared/providers/locale_provider.dart`
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add lib/shared/providers/locale_provider.dart
git commit -m "feat(l10n): localeProvider with persistence + Intl.defaultLocale sync"
```

### Task 4: Wire locale into `main.dart` + `app.dart`

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/app.dart`

- [ ] **Step 1: Seed locale + init date formatting in `main.dart`**

Add imports:
```dart
import 'package:intl/date_symbol_data_local.dart';
import 'shared/providers/locale_provider.dart';
```

In `main()`, after `final themeMode = await loadThemeMode();` add:
```dart
  await initializeDateFormatting();
  final locale = await loadLocale();
```

Add to the `overrides:` list in `runApp`:
```dart
        initialLocaleProvider.overrideWithValue(locale),
```

- [ ] **Step 2: Apply locale + delegates in `app.dart`**

Add imports:
```dart
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';
import 'shared/providers/locale_provider.dart';
```

In `build`, after `final themeMode = ref.watch(themeModeProvider);`:
```dart
    final locale = ref.watch(localeProvider);
```

Add these arguments to `MaterialApp.router(...)` (next to `themeMode: themeMode,`):
```dart
      locale: locale,
      supportedLocales: supportedAppLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
```

- [ ] **Step 3: Verify build**

Run: `flutter analyze lib/main.dart lib/app.dart`
Expected: No issues.

- [ ] **Step 4: Commit**

```bash
git add lib/main.dart lib/app.dart
git commit -m "feat(l10n): wire locale + localization delegates into the app"
```

### Task 5: ARB key-parity test

**Files:**
- Create: `test/l10n_parity_test.dart`

- [ ] **Step 1: Write the test**

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every translatable key in the English template must have a Bengali
/// translation and vice-versa. Guards against half-translated screens.
void main() {
  Set<String> keysOf(String path) {
    final map = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    // Skip @@locale and @-metadata entries.
    return map.keys.where((k) => !k.startsWith('@')).toSet();
  }

  test('app_en.arb and app_bn.arb expose identical key sets', () {
    final en = keysOf('lib/l10n/app_en.arb');
    final bn = keysOf('lib/l10n/app_bn.arb');
    expect(en.difference(bn), isEmpty,
        reason: 'English keys missing a Bengali translation');
    expect(bn.difference(en), isEmpty,
        reason: 'Bengali keys with no English template entry');
  });
}
```

- [ ] **Step 2: Run — expect PASS (both seed files have only `settings_title`)**

Run: `flutter test test/l10n_parity_test.dart`
Expected: PASS. (This test must stay green after every future extraction task.)

- [ ] **Step 3: Commit**

```bash
git add test/l10n_parity_test.dart
git commit -m "test(l10n): assert en/bn ARB key parity"
```

---

## Phase 2 — Number formatting + Bengali font

### Task 6: Localize `Qty.format`

**Files:**
- Modify: `lib/shared/extensions/format.dart:10-13`
- Test: `test/qty_format_locale_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:ai_shopkeeper/shared/extensions/format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

void main() {
  tearDown(() => Intl.defaultLocale = null);

  test('Qty.format uses Bengali digits under bn locale', () {
    Intl.defaultLocale = 'bn';
    expect(Qty.format(1234), '১,২৩৪');
    expect(Qty.format(2.5), '২.৫');
  });

  test('Qty.format uses Western digits under en locale', () {
    Intl.defaultLocale = 'en';
    expect(Qty.format(1234), '1,234');
    expect(Qty.format(2.5), '2.5');
  });
}
```

- [ ] **Step 2: Run — expect FAIL**

Run: `flutter test test/qty_format_locale_test.dart`
Expected: FAIL (current impl returns `'1234'` / `'1234'`, no localization).

- [ ] **Step 3: Implement**

Replace the body of `Qty.format` in `lib/shared/extensions/format.dart`:
```dart
  static String format(num v) {
    final d = v.toDouble();
    return d == d.roundToDouble()
        ? NumberFormat.decimalPattern().format(d)
        : NumberFormat('#,##0.###').format(d);
  }
```
(`intl` is already imported in this file.)

- [ ] **Step 4: Run — expect PASS**

Run: `flutter test test/qty_format_locale_test.dart`
Expected: PASS.

- [ ] **Step 5: Confirm money tests still pass**

Run: `flutter test test/money_format_test.dart`
Expected: PASS (no signature change; `Money.*` already localize via `Intl.defaultLocale`).

- [ ] **Step 6: Commit**

```bash
git add lib/shared/extensions/format.dart test/qty_format_locale_test.dart
git commit -m "feat(l10n): localize Qty.format digits via NumberFormat"
```

### Task 7: Bundle Hind Siliguri font + theme fallback

**Files:**
- Add: `assets/fonts/HindSiliguri-Regular.ttf`, `assets/fonts/HindSiliguri-SemiBold.ttf`
- Modify: `pubspec.yaml`
- Modify: `lib/core/config/theme.dart:270-273`

- [ ] **Step 1: Obtain the font files**

Download Hind Siliguri (OFL) Regular + SemiBold from https://fonts.google.com/specimen/Hind+Siliguri
and place the two TTFs at `assets/fonts/HindSiliguri-Regular.ttf` and
`assets/fonts/HindSiliguri-SemiBold.ttf`. (These are the only binary assets in this plan; if
unavailable, on-device system Bengali fonts still render — but bundle for consistent output.)

- [ ] **Step 2: Declare the font + assets in `pubspec.yaml`**

Under the `flutter:` section:
```yaml
  assets:
    - assets/fonts/
  fonts:
    - family: HindSiliguri
      fonts:
        - asset: assets/fonts/HindSiliguri-Regular.ttf
        - asset: assets/fonts/HindSiliguri-SemiBold.ttf
          weight: 600
```

- [ ] **Step 3: Add the fallback to the text theme**

In `lib/core/config/theme.dart`, in `_typography`, change the `base` assignment:
```dart
    final base = GoogleFonts.interTextTheme(
      ThemeData(brightness: brightness).textTheme,
    ).apply(fontFamilyFallback: const ['HindSiliguri']);
```

- [ ] **Step 4: Verify build**

Run: `flutter pub get && flutter analyze lib/core/config/theme.dart`
Expected: No issues; pub get resolves the font asset.

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml assets/fonts/ lib/core/config/theme.dart
git commit -m "feat(l10n): bundle Hind Siliguri as Bengali font fallback"
```

---

## Phase 3 — Settings language switcher (first fully-localized screen)

### Task 8: Language selector + localize Settings screen

**Files:**
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_bn.arb`
- Modify: `lib/features/settings/presentation/settings_screen.dart`
- Test: `test/settings_locale_switch_test.dart`

- [ ] **Step 1: Add settings + common keys to both ARBs**

Add to `lib/l10n/app_en.arb` (keep `settings_title`):
```json
  "common_signOut": "Sign out",
  "settings_sectionProfile": "Profile",
  "settings_sectionShop": "Shop",
  "settings_sectionAssistant": "Assistant",
  "settings_sectionAppearance": "Appearance",
  "settings_sectionInventory": "Inventory",
  "settings_sectionLanguage": "Language",
  "settings_appLanguage": "App language",
  "settings_guestSession": "Guest session",
  "settings_signedIn": "Signed in",
  "settings_anonymousData": "Anonymous — data is tied to this device",
  "settings_shopName": "Shop name",
  "settings_address": "Address",
  "settings_phone": "Phone",
  "settings_currency": "Currency",
  "settings_aiInsights": "AI Insights",
  "settings_aiInsightsSub": "Suggestions from the assistant",
  "settings_trends": "Trends",
  "settings_trendsSub": "Sales trend dashboards",
  "settings_themeLight": "Light",
  "settings_themeDark": "Dark",
  "settings_manageCategories": "Manage categories",
  "settings_manageCategoriesSub": "Rename, add, or remove categories",
  "settings_archivedProducts": "Archived products",
  "settings_archivedProductsSub": "View and restore removed products"
```

Add the matching keys to `lib/l10n/app_bn.arb` (keep `settings_title`):
```json
  "common_signOut": "লগ আউট",
  "settings_sectionProfile": "প্রোফাইল",
  "settings_sectionShop": "দোকান",
  "settings_sectionAssistant": "অ্যাসিস্ট্যান্ট",
  "settings_sectionAppearance": "চেহারা",
  "settings_sectionInventory": "পণ্য",
  "settings_sectionLanguage": "ভাষা",
  "settings_appLanguage": "অ্যাপের ভাষা",
  "settings_guestSession": "গেস্ট সেশন",
  "settings_signedIn": "সাইন ইন করা আছে",
  "settings_anonymousData": "বেনামী — ডেটা এই ডিভাইসে সংরক্ষিত",
  "settings_shopName": "দোকানের নাম",
  "settings_address": "ঠিকানা",
  "settings_phone": "ফোন",
  "settings_currency": "মুদ্রা",
  "settings_aiInsights": "এআই ইনসাইট",
  "settings_aiInsightsSub": "অ্যাসিস্ট্যান্টের পরামর্শ",
  "settings_trends": "ট্রেন্ড",
  "settings_trendsSub": "বিক্রির ট্রেন্ড",
  "settings_themeLight": "লাইট",
  "settings_themeDark": "ডার্ক",
  "settings_manageCategories": "ক্যাটাগরি পরিচালনা",
  "settings_manageCategoriesSub": "যোগ, নাম বদল বা মুছুন",
  "settings_archivedProducts": "আর্কাইভ পণ্য",
  "settings_archivedProductsSub": "সরানো পণ্য দেখুন ও ফেরান"
```

Run: `flutter gen-l10n` — expected: regenerates with the new getters, no errors.

- [ ] **Step 2: Verify ARB parity still passes**

Run: `flutter test test/l10n_parity_test.dart`
Expected: PASS.

- [ ] **Step 3: Replace hardcoded strings + add the language selector**

In `settings_screen.dart`:
- Add import: `import '../../../core/l10n/l10n_ext.dart';` and `import '../../../shared/providers/locale_provider.dart';`
- Replace each literal with its key, e.g. `AppBar(title: Text(context.l10n.settings_title))`,
  `_SectionHeader(context.l10n.settings_sectionProfile)`, the guest/signed-in ternaries with
  `context.l10n.settings_guestSession` / `settings_signedIn`, subtitles with their keys, the
  Assistant/Inventory ListTiles, and the sign-out label with `context.l10n.common_signOut`.
- In `_ThemeModeSelector`, replace `Text('Light')`/`Text('Dark')` with
  `Text(context.l10n.settings_themeLight)` / `settings_themeDark`.
- Add a new `_SectionHeader(context.l10n.settings_sectionLanguage)` + `const _LanguageSelector()`
  block (place it just above the Appearance section).
- Append this widget to the file:

```dart
/// English / বাংলা picker. The choice is persisted via [localeProvider] and
/// applied app-wide by MaterialApp.router.
class _LanguageSelector extends ConsumerWidget {
  const _LanguageSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final selected =
        locale.languageCode == 'bn' ? const Locale('bn') : const Locale('en');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: SegmentedButton<Locale>(
        segments: const [
          ButtonSegment(value: Locale('en'), label: Text('English')),
          ButtonSegment(value: Locale('bn'), label: Text('বাংলা')),
        ],
        selected: {selected},
        showSelectedIcon: false,
        onSelectionChanged: (s) =>
            ref.read(localeProvider.notifier).setLocale(s.first),
      ),
    );
  }
}
```
(English/বাংলা are endonyms shown in both modes, so they stay literal — not ARB keys.)

- [ ] **Step 4: Write the widget test**

`test/settings_locale_switch_test.dart`:
```dart
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:ai_shopkeeper/shared/providers/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal harness: a screen that shows the localized settings title and flips
/// locale via the provider, proving the wiring end-to-end.
void main() {
  testWidgets('changing localeProvider swaps the settings title language',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) {
            final locale = ref.watch(localeProvider);
            return MaterialApp(
              locale: locale,
              supportedLocales: supportedAppLocales,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: Builder(
                builder: (context) =>
                    Text(AppLocalizations.of(context).settings_title),
              ),
            );
          },
        ),
      ),
    );

    expect(find.text('Settings'), findsOneWidget);

    await container.read(localeProvider.notifier).setLocale(const Locale('bn'));
    await tester.pumpAndSettle();

    expect(find.text('সেটিংস'), findsOneWidget);
  });
}
```

- [ ] **Step 5: Run tests + analyze**

Run: `flutter test test/settings_locale_switch_test.dart && flutter analyze lib/features/settings`
Expected: PASS, no issues.

- [ ] **Step 6: Manual smoke (optional but recommended)**

Run the app, open Settings, toggle বাংলা → the Settings screen text switches to Bengali and
survives an app restart.

- [ ] **Step 7: Commit**

```bash
git add lib/l10n/ lib/features/settings/ test/settings_locale_switch_test.dart
git commit -m "feat(l10n): language switcher + fully localized Settings screen"
```

---

## Phase 4 — Extract strings screen-group by screen-group

**Recipe for every task below (the mechanical pattern, established in Task 8):**
1. Open the screen file(s); find every user-facing English string literal (titles, labels, buttons,
   hints, subtitles, snackbars, dialog text, empty/error states). Skip product/shop *data* and
   `// MEMBER B/C` seams' data.
2. Add a key per string to **both** ARBs using the `<feature>_<meaning>` convention and the Bengali
   glossary above for shared terms. For strings with a number/name inside, use an ARB placeholder
   (e.g. `"inventory_itemCount": "{count} items", "@inventory_itemCount": {"placeholders":{"count":{"type":"int"}}}`)
   so the digit localizes.
3. Run `flutter gen-l10n`.
4. Replace literals with `context.l10n.<key>` (add `import '../../../core/l10n/l10n_ext.dart';`).
   For `ConsumerWidget`/`StatelessWidget` without a `context` in scope (e.g. static helpers), pass the
   string in or read it where a `BuildContext` exists.
5. Run `flutter test test/l10n_parity_test.dart` (must stay green) and `flutter analyze <dir>`.
6. Commit `feat(l10n): localize <screen group>`.

Do the groups in this order (each is shippable on its own; unconverted screens stay English):

### Task 9: Dashboard

**Files:** `lib/features/dashboard/presentation/dashboard_screen.dart`, `revenue_hero.dart`, `summary_breakdown_sheet.dart`

Concrete strings → keys (add to both ARBs; Bengali shown):
- `dashboard_yourShop` "Your shop" / "আপনার দোকান"
- `dashboard_periodToday` "Today" / "আজ", `dashboard_periodWeek` "Week" / "সপ্তাহ", `dashboard_periodMonth` "Month" / "মাস", `dashboard_periodAll` "All" / "সব"
- `dashboard_notificationsCaughtUp` "You're all caught up" / "সব দেখা হয়ে গেছে"
- `dashboard_notificationsHint` "We'll alert you about low stock and sales here." / "কম স্টক আর বিক্রির খবর এখানে পাবেন।"
- `dashboard_salesLast7` "Sales · last 7 days" / "বিক্রি · গত ৭ দিন"
- `dashboard_bestDay` "{day} best" / "{day} সেরা" (placeholder `day`, type String)
- `dashboard_topPerformer` "TOP PERFORMER" / "সেরা বিক্রেতা"
- `dashboard_noSalesYet` "No sales yet — your best seller will appear here." / "এখনো বিক্রি নেই — সেরা বিক্রেতা এখানে দেখাবে।"
- `dashboard_soldRevenue` "{units} sold · {revenue} revenue" / "{units} বিক্রি · {revenue} আয়" (placeholders: units String, revenue String)
- `dashboard_lowStock` "Low stock" / "কম স্টক"
- `dashboard_viewAll` "View all" / "সব দেখুন"
- `dashboard_fullyStocked` "You're fully stocked — nothing needs reordering." / "স্টক ভরা — কিছু রিঅর্ডার করতে হবে না।"
- `dashboard_leftReorder` "{qty} left · reorder" / "{qty} বাকি · রিঅর্ডার" (placeholder qty String)
- `common_restock` "Restock" / "রিস্টক"
- `common_sell` "Sell" / "বিক্রি"
- `dashboard_couldNotLoadSummary` "Could not load summary." / "সারসংক্ষেপ লোড করা যায়নি।"
- `dashboard_couldNotLoadSales` "Could not load sales." / "বিক্রি লোড করা যায়নি।"
- Hero (`revenue_hero.dart`): `dashboard_revenuePeriod` "Revenue · {period}" / "আয় · {period}", `dashboard_profit` "Profit" / "লাভ", `dashboard_margin` "Margin" / "মার্জিন", `dashboard_itemsSold` "Items sold" / "বিক্রি", `dashboard_vsYesterday` "vs yesterday" / "গতকালের চেয়ে"
- Enumerate any remaining literals in `summary_breakdown_sheet.dart` the same way.

Follow the recipe. Commit `feat(l10n): localize Dashboard`.

### Task 10: Inventory (list, form, detail, categories, archived)

**Files:** `lib/features/inventory/presentation/*.dart`

Concrete strings for the list screen (extend to the others by the recipe):
- `inventory_title` "Inventory" / "পণ্যতালিকা"
- `inventory_itemsValue` "{count} items · {value} value" / "{count}টি পণ্য · {value} মূল্য" (placeholders count int, value String)
- `common_searchItems` "Search items" / "পণ্য খুঁজুন"
- `inventory_filterAll` "All" / "সব", `inventory_filterLowStock` "Low stock" / "কম স্টক"
- `inventory_inStock` "{qty} in stock" / "{qty} স্টকে" (placeholder qty String)
- `inventory_noProducts` "No products yet.\nTap \"Add product\" to start." / "এখনো কোনো পণ্য নেই।\nশুরু করতে \"পণ্য যোগ\" চাপুন।"
- `inventory_noMatch` "No products match your filters." / "আপনার ফিল্টারে কোনো পণ্য মেলেনি।"
- `inventory_couldNotLoad` "Could not load inventory. Pull to retry." / "পণ্যতালিকা লোড করা যায়নি। রিফ্রেশ করুন।"
- `common_retry` "Retry" / "আবার চেষ্টা"
- `inventory_addProduct` "Add product" / "পণ্য যোগ", `inventory_scanProduct` "Scan product" / "পণ্য স্ক্যান"

For `product_form_screen.dart`, `product_detail_screen.dart`, `manage_categories_screen.dart`,
`archived_products_screen.dart`: read each file, extract every label/button/hint/dialog/snackbar
following the recipe and glossary. Commit `feat(l10n): localize Inventory`.

### Task 11: Cart + Scan

**Files:** `lib/features/cart/presentation/*.dart`, `lib/features/scan/presentation/*.dart`

Concrete cart strings:
- `cart_title` "Cart" / "কার্ট"
- `common_clear` "Clear" / "খালি করুন"
- `cart_itemsInCart` "{count} items in cart" / "{count}টি পণ্য কার্টে" (placeholder count int; keep the singular/plural via ARB plural if desired: use `plural` ICU form)
- `cart_clearTitle` "Clear cart?" / "কার্ট খালি করবেন?"
- `cart_clearBody` "This removes every item from the cart. Nothing is sold." / "এটি কার্টের সব পণ্য সরিয়ে দেবে। কিছু বিক্রি হবে না।"
- `cart_keep` "Keep" / "থাক", `common_remove` "Remove" / "মুছুন"
- `cart_totalItems` "Total · {count} items" / "মোট · {count}টি পণ্য"
- `cart_checkout` "Checkout" / "চেকআউট", `cart_selling` "Selling…" / "বিক্রি হচ্ছে…"
- `cart_empty` "Your cart is empty" / "আপনার কার্ট খালি"
- `cart_emptyHint` "Add products from Items or Scan to build a sale, then check out here." / "পণ্য বা স্ক্যান থেকে পণ্য যোগ করে বিক্রি শুরু করুন, তারপর এখানে চেকআউট করুন।"
- `cart_itemsSold` "{count} items sold · {total}" / "{count}টি পণ্য বিক্রি · {total}"
- `cart_checkoutFailed` "Checkout failed. Please try again." / "চেকআউট ব্যর্থ। আবার চেষ্টা করুন।"
- `cart_pricePerUnit` "{price} / {unit}" / "{price} / {unit}"

Concrete scan strings:
- `scan_title` "Scan product" / "পণ্য স্ক্যান"
- `scan_failed` "Scan failed. Try again." / "স্ক্যান ব্যর্থ। আবার চেষ্টা করুন।"
- `scan_addedToCart` "Added {name} to cart" / "{name} কার্টে যোগ হয়েছে"
- `scan_outOfStock` "{name} is out of stock." / "{name} স্টকে নেই।"
- `scan_fullyStaged` "{name} is already fully staged in your cart." / "{name} ইতিমধ্যে কার্টে পুরো যোগ হয়ে আছে।"
- `scan_didYouMean` "Did you mean?" / "আপনি কি বোঝাতে চেয়েছেন?"
- `scan_noMatchPick` "No match — pick the product" / "মেলেনি — পণ্য বেছে নিন"
- `common_couldNotRecognize` "Could not recognize the product. Please try again." / "পণ্য শনাক্ত করা যায়নি। আবার চেষ্টা করুন।"
- Also localize `add_to_cart_sheet.dart` and `product_picker_sheet.dart` literals per recipe.

Commit `feat(l10n): localize Cart + Scan`.

### Task 12: Transactions / History

**Files:** `lib/features/transactions/presentation/*.dart`

Read `history_screen.dart` and `transaction_confirmation_sheet.dart`; extract all literals
(title "History"/"হিস্ট্রি", empty/error states, receipt row labels, restock sheet labels) per the
recipe + glossary. Commit `feat(l10n): localize History`.

### Task 13: Analytics / Insights / Trends

**Files:** `lib/features/analytics/presentation/*.dart`, `lib/features/insights/presentation/*.dart`, `lib/features/trends/presentation/*.dart`

Read each screen; extract chart headers, metric labels, empty/error states, and the read-only
insight/trend section headers (the JSON *content* from Member B stays as-is). Commit
`feat(l10n): localize Analytics/Insights/Trends`.

### Task 14: Auth / Onboarding

**Files:** `lib/features/auth/presentation/*.dart`, `lib/features/onboarding/presentation/welcome_screen.dart`

Read login, profile setup, and welcome screens; extract titles, field labels, buttons, validation
messages, and onboarding copy per recipe. Commit `feat(l10n): localize Auth + Onboarding`.

### Task 15: Shared widgets + final sweep

**Files:** `lib/core/widgets/*.dart`, `lib/features/shell/presentation/main_shell.dart`, any remainder

- [ ] **Step 1: Localize the bottom-nav labels**

In `main_shell.dart`, the `AppNavItem` labels (`Home`, `Items`, `Reports`, `History`) are built in a
`const` list. Convert that list to be built in `build` (non-const) so labels can read `context.l10n`:
`nav_home` "Home"/"হোম", `nav_items` "Items"/"পণ্য", `nav_reports` "Reports"/"রিপোর্ট",
`nav_history` "History"/"হিস্ট্রি". Add these to both ARBs.

- [ ] **Step 2: Grep for any remaining hardcoded UI strings**

Run: `grep -rnE "Text\(\s*'[A-Za-z]" lib/ | grep -v l10n`
Review each hit; localize any user-facing literal missed above (skip debug-only or data strings).

- [ ] **Step 3: Full verification**

Run: `flutter analyze && flutter test`
Expected: no issues; all tests (parity, formatting, settings switch) pass.

- [ ] **Step 4: On-device Bengali pass**

Build/run in Bengali and walk the core flows (Home → Items → add to Cart → Checkout → Settings) plus
a scan, confirming layout holds and digits are Bengali.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(l10n): localize nav + shared widgets; final sweep"
```

---

## Self-Review notes (addressed)
- **Spec coverage:** framework (T1-2), locale state + persistence + default (T3-4), Intl sync (T3-4),
  number/date localization (T4, T6), font (T7), settings toggle (T8), per-screen extraction incl. all
  screens named in spec §2 (T8-15), tests (T5, T6, T8, T15).
- **Placeholder discipline:** infra tasks carry full code; extraction tasks carry the concrete string
  tables for the screens already read (settings, dashboard, inventory, cart, scan) and an explicit,
  repeatable recipe + glossary for the remaining files, which the executor enumerates per file.
- **Type consistency:** `context.l10n`, `localeProvider`/`LocaleController.setLocale`,
  `initialLocaleProvider`, `supportedAppLocales`, `loadLocale`, and ARB key names are used identically
  across tasks.
