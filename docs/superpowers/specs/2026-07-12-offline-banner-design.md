# Design: App-wide "No internet" banner

**Date:** 2026-07-12
**Feature branch:** feat/bengali-localization (or a new branch)
**Owner:** Member A (Flutter + Supabase)
**Related:** [[2026-08-05-voice-wait-ux-design]] §9 — the voice banner shares
this one's mounting point in `app.dart`'s builder, which sits *above* the
router. Anything there has no `Navigator` ancestor, so **if this banner ever
becomes tappable it cannot push a route from its own context** — it must go
through `rootNavigatorKey` the same way. Read §9 before adding a tap here.

## Problem

When the device has no internet connection, network requests fail and the app
surfaces them as generic errors — a disappearing snackbar on the sign-in page,
and per-screen "Could not load…" text elsewhere. None of these tell the user the
real cause. We want a clear, persistent **"No internet connection"** indicator
that appears app-wide, including on the sign-in page.

## Approach

Proactive detection via `connectivity_plus`: watch the device's network
interface state and show a persistent banner whenever it reports offline,
auto-hiding when connectivity returns. One global integration point covers every
screen (sign-in included).

This reliably catches the "no connection" case the user described (airplane
mode, wifi off, no signal). **Known limitation:** interface-level connectivity
does not guarantee real internet reachability — a device connected to a wifi
network with no working uplink will read as online. Handling that reliably would
require active reachability probing; it is out of scope for the MVP.

## Components

### 1. Connectivity provider
`lib/shared/providers/connectivity_provider.dart`

- Exposes `isOnlineProvider`, a `StreamProvider<bool>` (`true` = online).
- Seeds from an initial `Connectivity().checkConnectivity()` call, then listens
  to `Connectivity().onConnectivityChanged`.
- `connectivity_plus` (v6+) emits `List<ConnectivityResult>`. Treat as **offline**
  when the list is empty or contains only `ConnectivityResult.none`; otherwise
  online.
- On stream error or while loading the initial value, default to **online**
  (fail-open) so the banner never shows spuriously before the first reading.

### 2. Offline banner widget
`lib/core/widgets/offline_banner.dart`

- Watches `isOnlineProvider`. Renders `SizedBox.shrink()` when online.
- When offline: a slim full-width bar using the theme's warning/error container
  color, with a `Icons.wifi_off` (or `Icons.cloud_off`) icon and the localized
  "No internet connection" text.
- Animates in/out with a combined slide + fade (reuse existing motion durations
  from `core/config/motion.dart` where applicable) so it does not pop abruptly.
- No tap/InkWell behavior required; a plain colored container is sufficient
  (avoids needing a Material ancestor).

### 3. Global wiring
`lib/app.dart`

- Inject the banner once inside the `MaterialApp.router` `builder`, as a top
  strip above the routed `child` and below the status bar, respecting the
  existing `SafeArea`/system-bar handling.
- Because the builder wraps all routes, the banner appears on every screen,
  including the sign-in page — satisfying both "in the app" and "in the sign-in
  page" with a single integration point.
- The banner sits inside the existing `MediaQuery.withClampedTextScaling` /
  `AnnotatedRegion` wrapper already present in the builder.

### 4. Localization
`lib/l10n/app_en.arb`, `lib/l10n/app_bn.arb`

- Add `common_noInternet`:
  - en: `"No internet connection"`
  - bn: Bengali equivalent.
- Run codegen so `AppLocalizations` exposes the new getter.

### 5. Sign-in snackbar cleanup
`lib/features/auth/presentation/login_screen.dart` (lines ~93–103)

- In the `ref.listen` failure handler: when `next.error` is a `NetworkFailure`,
  skip showing the snackbar (the persistent banner already communicates offline
  state). All other failures snackbar as before.

## Out of scope

- Rewriting per-screen error states (dashboard "Could not load…", etc.) — the
  persistent banner is the offline signal.
- Active internet-reachability probing (see Known limitation above).
- Queuing/retrying failed requests once connectivity returns; existing screens
  already refetch on their own triggers.

## Testing

- **Provider unit test:** map sample `List<ConnectivityResult>` inputs to the
  expected online/offline boolean (`[none]` → offline, `[wifi]` → online,
  `[]` → offline, `[none, wifi]` → online).
- **Widget test:** `OfflineBanner` renders the localized text when the provider
  is overridden to offline, and renders nothing when online.
- **Manual:** toggle airplane mode on the physical S22 and confirm the banner
  appears/disappears on both the sign-in page and a main tab screen, and that
  the sign-in snackbar no longer double-reports offline.

## Files touched

| File | Change |
|---|---|
| `pubspec.yaml` | add `connectivity_plus` |
| `lib/shared/providers/connectivity_provider.dart` | new: `isOnlineProvider` |
| `lib/core/widgets/offline_banner.dart` | new: banner widget |
| `lib/app.dart` | wire banner into `MaterialApp.router` builder |
| `lib/l10n/app_en.arb`, `lib/l10n/app_bn.arb` | add `common_noInternet` |
| `lib/features/auth/presentation/login_screen.dart` | suppress redundant NetworkFailure snackbar |
