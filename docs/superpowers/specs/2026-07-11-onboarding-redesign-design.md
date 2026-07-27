# First-Time Onboarding Redesign — Design

**Date:** 2026-07-11
**Branch:** `feat/bengali-localization`
**Status:** Approved design → ready for implementation plan

## Goal

Give brand-new users a clean two-step first-run setup:

1. **Choose language** (English / বাংলা) — applied and saved the instant they pick it.
2. **Set up shop** — shown entirely in the chosen language, and now including a
   **required default-currency** choice that is saved with the shop and used for
   every money value in the app.

The flow appears **only the first time**, language selection is **compulsory and
always before** shop setup, and the choices persist after onboarding ends.

## Current State (what already exists)

- **Router** (`lib/core/router/app_router.dart`): a signed-in user whose
  `myShopProvider` resolves to `null` is redirected to `/profile-setup`
  (`ProfileSetupScreen`). Once a shop exists, they go to the dashboard. This
  `shop == null` condition is effectively the "brand-new account" signal.
- **`ProfileSetupScreen`** (`lib/features/auth/presentation/profile_setup_screen.dart`):
  a form (name required, address/phone optional) that calls
  `AuthController.createShop`. Already fully localized (`profile_*` keys).
- **`localeProvider`** (`lib/shared/providers/locale_provider.dart`):
  `setLocale()` applies the locale, syncs `Intl.defaultLocale`, and persists to
  SharedPreferences. `MaterialApp.router` already watches it, so a locale change
  live-rebuilds the whole app.
- **Currency**: stored per-shop in `shops.currency` (DB column already exists).
  `Shop.toInsert` already serialises it. Screens read
  `myShopProvider.value?.currency ?? 'USD'`. `Money.format`/`Money.compact` render
  the symbol via `intl` — verified: BDT → `৳12,450` (en) / `১২,৪৫০৳` (bn), USD → `$`.
- **`WelcomeScreen`** (pre-login marketing hero, gated device-level by
  `onboardingSeenProvider`) — **unchanged by this work.**

## New Flow & Routing

- **Replace** the `/profile-setup` route with a single **`/onboarding`** route that
  hosts a two-step wizard (`OnboardingScreen`).
- **Redirect rule** (in `app_router.dart`): signed-in **&&** `shop == null` **&&**
  current location ≠ `/onboarding` → redirect to `/onboarding`. Shop created →
  dashboard (unchanged). Rename `AppRoutes.profileSetup` → `AppRoutes.onboarding`
  (`/onboarding`).
- One route + a `PageView` guarantees "language always before shop" by page
  order — there is no navigable path to step 2 that bypasses step 1. This is why
  the single-page wizard was chosen over two separate routes.

## Screens & UX

New feature files under `lib/features/onboarding/presentation/`:

- **`onboarding_screen.dart`** — `ConsumerStatefulWidget`. Owns a `PageController`
  and the current step index; renders a slim "Step 1 of 2 / ধাপ ১/২" progress
  indicator above a two-page `PageView`. The `PageView` uses
  `NeverScrollableScrollPhysics` (no manual swiping in either direction) —
  movement happens **only** via the enabled Continue button (forward) and a back
  arrow on step 2 (back to step 1). This makes it structurally impossible to
  reach the shop step without first choosing a language. The screen's `State`
  survives the locale-driven `MaterialApp` rebuild, so the page position is
  preserved when the language flips.
- **`LanguageStep`** — two large tap cards labelled in their own script
  (**English** / **বাংলা**). No card is pre-selected. Tapping a card calls
  `localeProvider.setLocale()` immediately (whole app switches live) and marks it
  selected. A **Continue** button stays **disabled until a card is tapped**
  (enforces compulsory selection); pressing it animates to step 2.
- **`ShopSetupStep`** — the existing profile-setup form (name required,
  address/phone optional) **plus a required "Default currency" `SegmentedButton`**
  with two segments: **৳ BDT** (pre-selected) / **$ USD** — mirroring the Settings
  language/theme toggle pattern. "Create shop" validates (name non-empty; currency
  always has a value) and calls `createShop(..., currency: selected)`.

`ProfileSetupScreen` is retired; its shop-creation logic moves into
`ShopSetupStep`. The "Sign out" affordance in its app bar is preserved on the
onboarding screen.

## Data & Persistence

- **Language:** `localeProvider.setLocale()` already applies + persists. Nothing new.
- **Currency:** add a `String currency` parameter to `AuthController.createShop`
  and `AuthRepository.createShop`; build the `Shop` payload with it (`toInsert`
  already writes `currency`). No migration and **no DB-default change** — onboarding
  always writes an explicit value.
- **Currency source of truth:** a tiny const list `['BDT', 'USD']` (BDT first =
  default) with a helper mapping code → symbol (via `intl`) and localized label.

## Localization

Reuses existing `profile_*` / `auth_*` keys. New keys added to **both**
`app_en.arb` and `app_bn.arb` (parity test enforces lockstep):

- `onboarding_languageTitle`, `onboarding_languageSubtitle`
- `common_continue` (Continue / চালিয়ে যান)
- `onboarding_stepProgress` — "Step {current} of {total}" with placeholders
- `onboarding_defaultCurrency` — field label ("Default currency *" / "ডিফল্ট মুদ্রা *")
- `currency_bdt` — "৳ Taka (BDT)" / "৳ টাকা (BDT)"
- `currency_usd` — "$ Dollar (USD)" / "$ ডলার (USD)"

The language-step's own title/subtitle render in the current locale before a
choice is made (the card labels are script-native so they're unambiguous either
way).

## Requirements Coverage

| Requirement | How it's met |
|---|---|
| Shown only first time after account creation | `shop == null` redirect gate; disappears once shop exists |
| Language screen always before shop screen | Single `PageView`, page 0 = language, forward-locked |
| Language applied immediately & saved | `setLocale()` (live + SharedPreferences) on card tap |
| Language selection compulsory | Continue disabled until a card is tapped |
| Shop screen fully in chosen language | `MaterialApp.router` watches `localeProvider`; step 2 rebuilds localized |
| Required currency, saved to shop | `SegmentedButton` (BDT default) → `createShop(currency:)` → `shops.currency` |
| Currency used app-wide | Existing `shop.currency` reads across all screens |
| Validate required fields | Name non-empty (existing validator); currency always set |
| Clean/modern/mobile, existing patterns | Reuses card / SegmentedButton / form patterns already in app |

## Testing

- **Widget** (`test/widgets/onboarding_screen_test.dart`): language step renders
  first; tapping **বাংলা** flips a visible English string to Bengali and enables
  Continue; Continue reveals the shop step; the currency toggle shows ৳ BDT / $ USD;
  submitting a name with USD selected calls `createShop` with `currency: 'USD'`
  (repository overridden with a fake).
- **Unit** (`test/currency_option_test.dart`): code → symbol/label helper returns
  `৳`/`$` and the right labels for `BDT`/`USD`.
- Existing 79 tests stay green; `flutter analyze` clean; l10n parity test passes.

## Out of Scope (explicitly)

- No currency editing in Settings; the existing USD test shop is left as-is.
- No app-wide/DB currency default change (stays `USD`; onboarding writes explicit).
- No changes to the pre-login `WelcomeScreen`.
- No new "onboarding seen" flag — the `shop == null` gate is reused.

## File-Level Change Summary

- **New:** `lib/features/onboarding/presentation/onboarding_screen.dart`,
  `language_step.dart`, `shop_setup_step.dart`; a small currency-option helper
  (e.g. `lib/features/onboarding/domain/currency_option.dart`);
  `test/widgets/onboarding_screen_test.dart`, `test/currency_option_test.dart`.
- **Edit:** `app_router.dart` (route + redirect rename), `auth_repository.dart` &
  `auth_controller.dart` (`currency` param), `app_en.arb` / `app_bn.arb` (new keys).
- **Remove:** `profile_setup_screen.dart` (logic absorbed into `shop_setup_step.dart`).
