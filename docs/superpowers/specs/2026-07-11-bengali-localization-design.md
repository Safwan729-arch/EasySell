# Bengali Localization + In-App Language Switcher — Design

**Date:** 2026-07-11
**Feature owner:** Member A (Flutter + Supabase)
**Status:** Approved design → implementation planning

## 1. Goal

Let a shopkeeper switch the app's interface between **English** and **Bengali (বাংলা)** from
Settings, with the whole UI — labels, buttons, empty states, numbers, and dates — following the
choice live. Reviewed and approved via the mockup at
`docs/superpowers/mockups/bengali-ui-mockup.html`.

## 2. Scope

**In scope (UI chrome — everything the app itself says):**
- All user-facing strings across every screen: auth, onboarding, dashboard, inventory (list, form,
  detail, categories, archived), cart, scan, transactions/history, analytics, insights, trends,
  settings, shared widgets, snackbars, dialogs, error messages.
- Numbers rendered in Bengali digits (০-৯) and dates in Bengali month/day names when Bengali is active.
- A language switcher in Settings (English | বাংলা), persisted across launches.

**Out of scope (user data — shown as entered, never auto-translated):**
- Product names, brands, variants, category names, shop name/address — the shopkeeper's own data.
  These display exactly as typed, in either language mode. (Confirmed decision: "as-typed".)
- The scan/vision pipeline is unchanged — it matches a photo to the shop's product candidates and
  returns an id; the displayed name is the stored product name regardless of app language. No backend
  or Edge Function change is required for this feature.

## 3. Style decisions (locked)

- **Bengali digits** (০-৯) for all app-rendered numbers, prices, quantities, dates.
- **Natural shop Bengali** — everyday shopkeeper vocabulary, common English loanwords transliterated
  where natural (স্টক, কার্ট, রিপোর্ট, চেকআউট). Approved wording lives in the mockup + notes panel.
- **Currency** stays driven by the shop's `currency` setting; only the digits/grouping localize.

## 4. Architecture

Follows the existing `themeModeProvider` pattern (Riverpod Notifier + SharedPreferences) so language
and theme behave consistently.

### 4.1 Localization framework
- Add `flutter_localizations` (SDK) and enable Flutter's `gen-l10n`.
- ARB message catalogs: `lib/l10n/app_en.arb` (template) and `lib/l10n/app_bn.arb`.
- `flutter gen-l10n` generates `AppLocalizations`; add a `BuildContext.l10n` extension for
  `context.l10n.addToCart`-style access. Keys are semantic (e.g. `cart_checkout`, `inventory_title`,
  `lowStock_reorder`), grouped by feature.
- `MaterialApp.router` gains `localizationsDelegates` (AppLocalizations + Material/Widgets/Cupertino),
  `supportedLocales: [Locale('en'), Locale('bn')]`, and `locale:` bound to the provider.

### 4.2 Locale state
- `localeProvider` (`Notifier<Locale>`) in `lib/shared/providers/`. Persists the choice under a
  `locale` key in SharedPreferences.
- On change (and at startup) it also sets `Intl.defaultLocale` to `'bn'`/`'en'` so `intl` number and
  date formatters localize without threading a locale through every call site.
- **Default at first launch:** device locale if it is Bengali, otherwise English. An explicit user
  choice always wins and is remembered.

### 4.3 Number & date localization
- `Money.format` / `Money.compact` / `Money.compactCount` already use `NumberFormat` with no explicit
  locale, so they pick up `Intl.defaultLocale` → Bengali digits and South-Asian (lakh/crore) grouping
  automatically once it is set. No signature changes.
- `DateFormat(...)` calls (dashboard, history) likewise localize via `Intl.defaultLocale` → Bengali
  weekday/month names + digits.
- `Qty.format` uses raw `toStringAsFixed`/`toString` (always Western digits) — update it to render
  through `NumberFormat.decimalPattern()` so counts localize too.
- The compact magnitude suffix (`K`/`M` path in `_compactMagnitude`) is Latin; localize its digits and
  keep `K`/`M` for MVP. (A future refinement could swap to হাজার/লাখ/কোটি; not required now.)

### 4.4 Fonts
- The app's display font is Inter (via `google_fonts`), which has **no Bengali glyphs**. Bundle a
  Bengali-capable font — **Hind Siliguri** (or Noto Sans Bengali) — as a local asset and register it
  as `fontFamilyFallback` on the text theme, so Bengali renders consistently across devices rather
  than relying on each phone's system fallback. Latin text keeps using Inter; Bengali glyphs fall
  through to the bundled Bengali face.

### 4.5 Settings toggle
- New "Language / ভাষা" section in `settings_screen.dart`, a `SegmentedButton<Locale>` with
  English | বাংলা, mirroring the existing `_ThemeModeSelector`. Writes through `localeProvider`.

## 5. Components / boundaries

| Unit | Responsibility | Depends on |
|---|---|---|
| `lib/l10n/*.arb` + generated `AppLocalizations` | String catalog + typed lookup | gen-l10n |
| `context.l10n` extension | Ergonomic access in widgets | AppLocalizations |
| `localeProvider` | Current locale, persistence, `Intl.defaultLocale` sync | SharedPreferences, intl |
| `MaterialApp.router` wiring | Applies locale + delegates app-wide | localeProvider |
| `format.dart` (`Qty`) | Localized counts | intl |
| Bengali font asset + theme fallback | Correct Bengali glyph rendering | theme.dart |
| Settings language selector | User-facing switch | localeProvider |
| Per-screen string replacement | Swap hardcoded English → `l10n` keys | AppLocalizations |

## 6. Implementation phases (for the plan)

1. **Infrastructure:** deps, gen-l10n config, empty `en`/`bn` ARBs, `context.l10n`, MaterialApp wiring,
   `localeProvider` + persistence + `Intl.defaultLocale` sync.
2. **Formatting + font:** `Qty.format` localization, bundle Bengali font + fallback, verify digits/dates.
3. **Settings toggle:** language section; confirm live switching end to end.
4. **String extraction by feature** (incremental, screen group at a time): settings → dashboard →
   inventory → cart → scan → transactions → analytics/insights/trends → auth/onboarding → shared
   widgets. Each screen: move English into both ARBs, replace with `l10n` keys.

Phases 1–3 make the switch functional on a first screen; phase 4 rolls coverage across the app so
partial progress is always shippable (untranslated strings simply stay English).

## 7. Error handling / edge cases
- Missing `bn` key → gen-l10n falls back to the `en` template string (no crash, visible-English signal
  for "not yet translated").
- Unknown currency code → existing `Money` fallback path is untouched.
- Long Bengali strings: Bengali runs longer than English; keep existing `maxLines`/`ellipsis`/`FittedBox`
  guards and spot-check dense rows (cart line, hero stats, nav labels).

## 8. Testing
- Unit: `app_en.arb` and `app_bn.arb` expose the **same key set** (guard against missing translations).
- Unit: `Qty.format` and `Money.*` emit Bengali digits when `Intl.defaultLocale == 'bn'`.
- Widget: toggling `localeProvider` swaps visible strings and digits on a sample screen; choice
  survives a provider rebuild (persistence).
- Manual: on-device pass in Bengali across the core screens (per the mockup) for layout/overflow.

## 9. Non-goals
- Right-to-left layout (Bengali is LTR — no directionality work).
- Translating stored user data or the AI/vision outputs.
- Additional languages (structure supports adding more later, but only en/bn now).
