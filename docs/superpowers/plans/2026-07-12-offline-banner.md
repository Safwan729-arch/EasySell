# App-wide "No internet" Banner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a persistent, localized "No internet connection" banner on every screen (including the sign-in page) whenever the device is offline, instead of surfacing generic errors.

**Architecture:** A `connectivity_plus`-backed `StreamProvider<bool>` (`isOnlineProvider`) reports device network-interface state. A pure mapping function converts the plugin's `List<ConnectivityResult>` to a boolean so it can be unit-tested without the platform channel. An `OfflineBanner` widget watches the provider and animates a slim bar in/out. It is wired once into the `MaterialApp.router` `builder`, so it covers all routes. The login screen suppresses its now-redundant network-error snackbar.

**Tech Stack:** Flutter, Riverpod (`flutter_riverpod`), `connectivity_plus`, Flutter gen-l10n (ARB).

**Spec:** `docs/superpowers/specs/2026-07-12-offline-banner-design.md`

**Conventions to match:**
- Package name is `ai_shopkeeper` (imports use `package:ai_shopkeeper/...`).
- Providers live in `lib/shared/providers/`; shared widgets in `lib/core/widgets/`.
- Localized strings accessed via `context.l10n.<key>` (extension in `lib/core/l10n/l10n_ext.dart`).
- Motion tokens in `lib/core/config/motion.dart` (`AppMotion.fast`, `AppMotion.easeOut`).
- Tests live flat under `test/` or `test/widgets/`; use `package:ai_shopkeeper/...` imports and `setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);` when a widget pulls the theme.

---

### Task 1: Add the `connectivity_plus` dependency

**Files:**
- Modify: `pubspec.yaml` (dependencies section)

- [ ] **Step 1: Add the package**

Run: `flutter pub add connectivity_plus`

Expected: `pubspec.yaml` gains a `connectivity_plus:` line under `dependencies:` and `flutter pub get` runs automatically.

- [ ] **Step 2: Verify it resolved**

Run: `flutter pub get`
Expected: `Got dependencies!` with no version-solve errors.

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: add connectivity_plus for offline detection"
```

---

### Task 2: Localized "No internet connection" string

**Files:**
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_bn.arb`
- Test: `test/l10n_parity_test.dart` (already exists — guards key parity)

- [ ] **Step 1: Add the English key**

In `lib/l10n/app_en.arb`, add this line next to the other `common_` entries (e.g. right after `"common_somethingWrong": ...`):

```json
  "common_noInternet": "No internet connection",
```

- [ ] **Step 2: Add the Bengali key**

In `lib/l10n/app_bn.arb`, add the matching line next to its `common_` entries:

```json
  "common_noInternet": "ইন্টারনেট সংযোগ নেই",
```

- [ ] **Step 3: Regenerate localizations**

Run: `flutter gen-l10n`
Expected: no errors; `AppLocalizations` now exposes a `common_noInternet` getter.

- [ ] **Step 4: Verify key parity**

Run: `flutter test test/l10n_parity_test.dart`
Expected: PASS (both ARB files expose identical key sets).

- [ ] **Step 5: Commit**

```bash
git add lib/l10n/app_en.arb lib/l10n/app_bn.arb
git commit -m "feat(l10n): add common_noInternet string (en + bn)"
```

---

### Task 3: Connectivity provider with a pure, testable mapping

**Files:**
- Create: `lib/shared/providers/connectivity_provider.dart`
- Test: `test/connectivity_mapping_test.dart`

The plugin emits `List<ConnectivityResult>`. We keep the online/offline decision
in a pure top-level function so it is unit-testable without the platform channel;
the provider just wires the stream to that function.

- [ ] **Step 1: Write the failing test**

Create `test/connectivity_mapping_test.dart`:

```dart
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_shopkeeper/shared/providers/connectivity_provider.dart';

void main() {
  group('isOnlineFromResults', () {
    test('wifi is online', () {
      expect(isOnlineFromResults([ConnectivityResult.wifi]), isTrue);
    });

    test('mobile is online', () {
      expect(isOnlineFromResults([ConnectivityResult.mobile]), isTrue);
    });

    test('none-only is offline', () {
      expect(isOnlineFromResults([ConnectivityResult.none]), isFalse);
    });

    test('empty list is offline', () {
      expect(isOnlineFromResults([]), isFalse);
    });

    test('mixed none + wifi is online', () {
      expect(
        isOnlineFromResults([ConnectivityResult.none, ConnectivityResult.wifi]),
        isTrue,
      );
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/connectivity_mapping_test.dart`
Expected: FAIL — `isOnlineFromResults` / the import is undefined.

- [ ] **Step 3: Write the provider + mapping**

Create `lib/shared/providers/connectivity_provider.dart`:

```dart
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Pure mapping from the plugin's connectivity results to an online boolean.
///
/// `connectivity_plus` (v6+) reports a *list* of active interfaces. We treat the
/// device as **offline** only when there is no usable interface — an empty list
/// or a list whose sole entry is [ConnectivityResult.none]. Any other interface
/// (wifi, mobile, ethernet, vpn, …) counts as online. This reflects interface
/// state, not real internet reachability — see the design's Known limitation.
bool isOnlineFromResults(List<ConnectivityResult> results) {
  final usable = results.where((r) => r != ConnectivityResult.none);
  return usable.isNotEmpty;
}

/// Emits `true` while the device has a usable network interface, `false` when it
/// has none. Seeds from an initial `checkConnectivity()` reading, then follows
/// `onConnectivityChanged`. Fails **open** (online) while loading or on error so
/// the offline banner never shows spuriously before the first real reading.
final isOnlineProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  yield isOnlineFromResults(await connectivity.checkConnectivity());
  yield* connectivity.onConnectivityChanged.map(isOnlineFromResults);
});
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/connectivity_mapping_test.dart`
Expected: PASS (all 5 cases).

- [ ] **Step 5: Commit**

```bash
git add lib/shared/providers/connectivity_provider.dart test/connectivity_mapping_test.dart
git commit -m "feat: connectivity provider with pure online/offline mapping"
```

---

### Task 4: OfflineBanner widget

**Files:**
- Create: `lib/core/widgets/offline_banner.dart`
- Test: `test/widgets/offline_banner_test.dart`

Renders nothing when online; a slim animated bar with an icon + localized text
when offline. Uses `isOnlineProvider`. Fails open: while the provider is loading
or errored (`.value` is null), treat as online and show nothing.

- [ ] **Step 1: Write the failing test**

Create `test/widgets/offline_banner_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ai_shopkeeper/core/widgets/offline_banner.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:ai_shopkeeper/shared/providers/connectivity_provider.dart';

Widget _harness({required bool online}) {
  return ProviderScope(
    overrides: [
      isOnlineProvider.overrideWith((ref) => Stream.value(online)),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: OfflineBanner()),
    ),
  );
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('shows the no-internet text when offline', (tester) async {
    await tester.pumpWidget(_harness(online: false));
    await tester.pumpAndSettle();
    expect(find.text('No internet connection'), findsOneWidget);
  });

  testWidgets('renders nothing when online', (tester) async {
    await tester.pumpWidget(_harness(online: true));
    await tester.pumpAndSettle();
    expect(find.text('No internet connection'), findsNothing);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/widgets/offline_banner_test.dart`
Expected: FAIL — `OfflineBanner` is undefined.

- [ ] **Step 3: Implement the widget**

Create `lib/core/widgets/offline_banner.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/providers/connectivity_provider.dart';
import '../config/motion.dart';

/// A slim, full-width bar that appears whenever the device is offline and
/// animates away when connectivity returns. Meant to sit at the top of the app,
/// above the routed content. Renders nothing (zero height) while online.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Fail open: only treat as offline once we have a concrete `false` reading.
    final isOnline = ref.watch(isOnlineProvider).value ?? true;
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return AnimatedSwitcher(
      duration: AppMotion.fast,
      switchInCurve: AppMotion.easeOut,
      switchOutCurve: AppMotion.easeOut,
      transitionBuilder: (child, animation) => SizeTransition(
        sizeFactor: animation,
        axisAlignment: -1,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: isOnline
          ? const SizedBox.shrink()
          : Material(
              key: const ValueKey('offline-banner'),
              color: scheme.errorContainer,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.wifi_off_rounded,
                        size: 18,
                        color: scheme.onErrorContainer,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          l10n.common_noInternet,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: scheme.onErrorContainer),
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

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/widgets/offline_banner_test.dart`
Expected: PASS (both cases).

- [ ] **Step 5: Commit**

```bash
git add lib/core/widgets/offline_banner.dart test/widgets/offline_banner_test.dart
git commit -m "feat: OfflineBanner widget driven by isOnlineProvider"
```

---

### Task 5: Wire the banner into the app shell

**Files:**
- Modify: `lib/app.dart`

The `MaterialApp.router` `builder` already wraps every route in an
`AnnotatedRegion` + `MediaQuery.withClampedTextScaling`. Add the banner as a top
strip above the routed `child` there, so it appears on all screens including
sign-in. `child` may be null in the builder, so guard it (existing code already
uses `child!`).

- [ ] **Step 1: Add the import**

In `lib/app.dart`, add to the imports:

```dart
import 'core/widgets/offline_banner.dart';
```

- [ ] **Step 2: Insert the banner in the builder**

In `lib/app.dart`, replace the inner `MediaQuery.withClampedTextScaling(...)` child so the banner sits above the routed content. Change:

```dart
          child: MediaQuery.withClampedTextScaling(
            minScaleFactor: 1.0,
            maxScaleFactor: 1.0,
            child: child!,
          ),
```

to:

```dart
          child: MediaQuery.withClampedTextScaling(
            minScaleFactor: 1.0,
            maxScaleFactor: 1.0,
            child: Column(
              children: [
                const OfflineBanner(),
                Expanded(child: child!),
              ],
            ),
          ),
```

- [ ] **Step 3: Static analysis**

Run: `flutter analyze lib/app.dart lib/core/widgets/offline_banner.dart`
Expected: `No issues found!`

- [ ] **Step 4: Full test + analyze sanity pass**

Run: `flutter test`
Expected: all tests PASS (existing suite + the two new tests).

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/app.dart
git commit -m "feat: show OfflineBanner above all routes"
```

---

### Task 6: Suppress the redundant network-error snackbar on sign-in

**Files:**
- Modify: `lib/features/auth/presentation/login_screen.dart` (the `ref.listen` failure handler, ~lines 93–103)

With the banner now telling the user they are offline, the login screen's
snackbar should not also fire for a `NetworkFailure`. Other failures still
snackbar as before.

- [ ] **Step 1: Confirm the import is present**

`lib/features/auth/presentation/login_screen.dart` already imports the failure types:

```dart
import '../../../core/error/failure.dart';
```

No change needed if it is already there (it is, as of this writing).

- [ ] **Step 2: Guard the snackbar against NetworkFailure**

In `lib/features/auth/presentation/login_screen.dart`, change the failure handler from:

```dart
    ref.listen<AsyncValue<void>>(authControllerProvider, (_, next) {
      if (next is AsyncError) {
        final message = switch (next.error) {
          Failure(:final message) => message,
          _ => l10n.common_somethingWrong,
        };
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      }
    });
```

to:

```dart
    ref.listen<AsyncValue<void>>(authControllerProvider, (_, next) {
      if (next is AsyncError) {
        // The persistent offline banner already communicates no-internet, so we
        // skip the redundant snackbar for network failures.
        if (next.error is NetworkFailure) return;
        final message = switch (next.error) {
          Failure(:final message) => message,
          _ => l10n.common_somethingWrong,
        };
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      }
    });
```

- [ ] **Step 3: Static analysis**

Run: `flutter analyze lib/features/auth/presentation/login_screen.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/features/auth/presentation/login_screen.dart
git commit -m "feat(auth): defer to offline banner instead of network-error snackbar"
```

---

### Task 7: Manual device verification

**Files:** none (manual QA on the physical S22 per project memory).

- [ ] **Step 1: Run the app**

Run: `flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`

- [ ] **Step 2: Verify offline on sign-in**

Sign out (or launch signed-out). Toggle airplane mode ON.
Expected: the "No internet connection" banner appears at the top of the sign-in
page within ~1s. Tapping Sign in does **not** show a duplicate error snackbar.

- [ ] **Step 3: Verify offline in the app**

Sign in (toggle airplane mode OFF to sign in, then back ON while on a main tab).
Expected: the banner appears above the dashboard/tab content.

- [ ] **Step 4: Verify recovery**

Toggle airplane mode OFF.
Expected: the banner animates away within ~1s on whatever screen is showing.

---

## Notes for the implementer

- **connectivity_plus platform setup:** Android needs no extra permission for
  `connectivity_plus` beyond `INTERNET`/`ACCESS_NETWORK_STATE`; the plugin
  declares `ACCESS_NETWORK_STATE` itself via manifest merge. No manual manifest
  edit expected — if `flutter analyze`/build complains, add
  `<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>`
  to `android/app/src/main/AndroidManifest.xml`.
- **Fail-open is deliberate:** never show the banner on a null/loading/error
  reading — only on a concrete offline reading — so a cold start never flashes
  the banner before the first connectivity check completes.
- **Scope:** do not rewrite per-screen "Could not load…" states; the banner is
  the offline signal (per the spec's Out of scope section).
