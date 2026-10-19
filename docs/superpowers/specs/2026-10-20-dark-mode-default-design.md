# Dark mode is the default (2026-10-20)

A fresh install now opens in dark mode. Light is still one tap away in
Settings → Appearance, and the choice is remembered as before.

## Why

The owner asked for it before the hackathon submission. The dark "neon glass"
look is the one shown in the deck, the technical documentation and every
screenshot, so judges installing the APK should see the same app.

## Decisions

- **Only the unset case changed.** `loadThemeMode()` now returns Light only for
  an explicit stored `light`; unset (fresh install) and the legacy `system`
  value give Dark. Anyone who already picked Light keeps it.
- **The provider's fallback is Dark too** (`initialThemeModeProvider`), so a hot
  reload, which skips `main()`'s override, matches what users see.
- **The Android launch screen is now the dark navy `#07112E`**
  (`AppPalette.dark.bg`) instead of white, in both `launch_background.xml`
  files, and `NormalTheme` uses the same drawable. Without this a dark-default
  app flashes white on every cold start. A user on Light sees a brief navy
  frame instead, which was judged the smaller problem.

Tests: `test/theme_mode_default_test.dart` (fresh install → dark, stored light
→ light, stored dark → dark, legacy system → dark, provider fallback → dark).
