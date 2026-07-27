# First-Time Onboarding Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single profile-setup step with a two-step first-run wizard on one `/onboarding` route — a compulsory language choice (applied live) followed by shop setup in that language with a required BDT/USD currency picker saved to the shop.

**Architecture:** One `OnboardingScreen` (Riverpod `ConsumerStatefulWidget`) hosts a `NeverScrollableScrollPhysics` `PageView` with two child widgets (`LanguageStep`, `ShopSetupStep`); movement is only via the step-1 Continue button (enabled after a language is tapped) and a back arrow on step 2. The existing `shop == null` router redirect is reused as the "brand-new account" gate. Currency is a tiny `ShopCurrency` enum saved through the existing `createShop` → `shops.currency` path.

**Tech Stack:** Flutter, Riverpod (`AsyncNotifier`/`Notifier`), go_router, gen-l10n (ARB), intl.

---

## File Structure

- **Create** `lib/features/onboarding/domain/currency_option.dart` — `ShopCurrency` enum (code + symbol) — the currency source of truth.
- **Create** `lib/features/onboarding/presentation/language_step.dart` — step 1 UI + compulsory-pick logic.
- **Create** `lib/features/onboarding/presentation/shop_setup_step.dart` — step 2 shop form + currency picker (absorbs the old profile-setup logic).
- **Create** `lib/features/onboarding/presentation/onboarding_screen.dart` — the wizard shell (PageView, progress, app bar).
- **Create** `test/currency_option_test.dart`, `test/widgets/onboarding_screen_test.dart`.
- **Modify** `lib/l10n/app_en.arb`, `lib/l10n/app_bn.arb` — new keys.
- **Modify** `lib/features/auth/data/auth_repository.dart`, `lib/features/auth/presentation/auth_controller.dart` — add `currency` to `createShop`.
- **Modify** `lib/core/router/app_router.dart` — rename route to `/onboarding`, point at `OnboardingScreen`.
- **Remove** `lib/features/auth/presentation/profile_setup_screen.dart`.

---

### Task 1: Add onboarding localization keys

**Files:**
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_bn.arb`
- Test: `test/l10n_parity_test.dart` (existing)

- [ ] **Step 1: Add English keys**

In `lib/l10n/app_en.arb`, change the last entry `"welcome_getStarted": "Get started"` (currently followed by `}`) to add the new keys after it:

```json
  "welcome_getStarted": "Get started",
  "common_continue": "Continue",
  "onboarding_languageTitle": "Choose your language",
  "onboarding_languageSubtitle": "You can change this anytime in Settings.",
  "onboarding_step": "Step {current} of {total}",
  "@onboarding_step": { "placeholders": { "current": { "type": "int" }, "total": { "type": "int" } } },
  "onboarding_defaultCurrency": "Default currency *"
}
```

- [ ] **Step 2: Add Bengali keys**

In `lib/l10n/app_bn.arb`, change the last entry `"welcome_getStarted": "শুরু করুন"` (currently followed by `}`) to:

```json
  "welcome_getStarted": "শুরু করুন",
  "common_continue": "চালিয়ে যান",
  "onboarding_languageTitle": "আপনার ভাষা বেছে নিন",
  "onboarding_languageSubtitle": "পরে যেকোনো সময় সেটিংসে এটি বদলাতে পারবেন।",
  "onboarding_step": "ধাপ {current}/{total}",
  "@onboarding_step": { "placeholders": { "current": { "type": "int" }, "total": { "type": "int" } } },
  "onboarding_defaultCurrency": "ডিফল্ট মুদ্রা *"
}
```

- [ ] **Step 3: Regenerate localizations**

Run: `flutter gen-l10n`
Expected: completes with no error/warning output (only the "l10n.yaml exists" note).

- [ ] **Step 4: Verify EN/BN parity**

Run: `flutter test test/l10n_parity_test.dart`
Expected: PASS ("app_en.arb and app_bn.arb expose identical key sets").

- [ ] **Step 5: Commit**

```bash
git add lib/l10n/
git commit -m "feat(l10n): onboarding keys (language step, currency label, step progress)"
```

---

### Task 2: ShopCurrency source of truth (TDD)

**Files:**
- Create: `lib/features/onboarding/domain/currency_option.dart`
- Test: `test/currency_option_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/currency_option_test.dart`:

```dart
import 'package:ai_shopkeeper/features/onboarding/domain/currency_option.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('BDT is the first (default) option and carries the ৳ symbol', () {
    expect(ShopCurrency.values.first, ShopCurrency.bdt);
    expect(ShopCurrency.bdt.code, 'BDT');
    expect(ShopCurrency.bdt.symbol, '৳');
  });

  test('USD carries the \$ symbol', () {
    expect(ShopCurrency.usd.code, 'USD');
    expect(ShopCurrency.usd.symbol, '\$');
  });

  test('fromCode maps a stored code back, falling back to BDT', () {
    expect(ShopCurrency.fromCode('USD'), ShopCurrency.usd);
    expect(ShopCurrency.fromCode('BDT'), ShopCurrency.bdt);
    expect(ShopCurrency.fromCode('EUR'), ShopCurrency.bdt); // unknown → default
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/currency_option_test.dart`
Expected: FAIL — `currency_option.dart` / `ShopCurrency` does not exist (compile error).

- [ ] **Step 3: Write the implementation**

Create `lib/features/onboarding/domain/currency_option.dart`:

```dart
/// The currencies a shop can be created with, in display order (BDT first =
/// the pre-selected default). Symbols are the literal glyphs the app shows on
/// money elsewhere (matching `Money.format`), hardcoded here so the picker never
/// depends on locale-specific currency-symbol resolution (e.g. "US\$").
enum ShopCurrency {
  bdt('BDT', '৳'),
  usd('USD', '\$');

  const ShopCurrency(this.code, this.symbol);

  /// ISO code stored in `shops.currency` (e.g. 'BDT').
  final String code;

  /// Display glyph (৳ / \$).
  final String symbol;

  /// Resolves a stored code back to an option; unknown codes fall back to the
  /// BDT default so a bad/legacy value never crashes the picker.
  static ShopCurrency fromCode(String code) =>
      values.firstWhere((c) => c.code == code, orElse: () => ShopCurrency.bdt);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/currency_option_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/onboarding/domain/currency_option.dart test/currency_option_test.dart
git commit -m "feat(onboarding): ShopCurrency option enum (BDT default, USD)"
```

---

### Task 3: Thread currency through createShop

**Files:**
- Modify: `lib/features/auth/data/auth_repository.dart:107-130`
- Modify: `lib/features/auth/presentation/auth_controller.dart:62-80`

The parameter is optional with a `'BDT'` default so the still-present
`ProfileSetupScreen` (removed in Task 7) keeps compiling during the transition;
the onboarding UI always passes an explicit value.

- [ ] **Step 1: Add currency to the repository**

In `lib/features/auth/data/auth_repository.dart`, replace the `createShop` method signature and payload build:

```dart
  Future<Result<Shop>> createShop({
    required String name,
    String? address,
    String? phone,
    String currency = 'BDT',
  }) async {
    final user = currentUser;
    if (user == null) {
      return const Result.failure(AuthFailure('You must be signed in.'));
    }
    try {
      final payload = Shop(
        id: '',
        ownerId: user.id,
        name: name,
        address: address,
        phone: phone,
        currency: currency,
      ).toInsert(ownerId: user.id);

      final row = await _client.from('shops').insert(payload).select().single();
      return Result.success(Shop.fromMap(row));
    } catch (e) {
      return Result.failure(_map(e));
    }
  }
```

- [ ] **Step 2: Add currency to the controller**

In `lib/features/auth/presentation/auth_controller.dart`, replace the `createShop` method:

```dart
  /// Creates the user's shop, then refreshes [myShopProvider] so the router
  /// moves them off the onboarding step.
  Future<void> createShop({
    required String name,
    String? address,
    String? phone,
    String currency = 'BDT',
  }) async {
    state = const AsyncLoading();
    final result = await _repo.createShop(
      name: name.trim(),
      address: address?.trim(),
      phone: phone?.trim(),
      currency: currency,
    );
    state = result.when(
      success: (_) {
        ref.invalidate(myShopProvider);
        return const AsyncData(null);
      },
      failure: (f) => AsyncError(f, StackTrace.current),
    );
  }
```

- [ ] **Step 3: Verify it still compiles**

Run: `flutter analyze lib/features/auth`
Expected: "No issues found!"

- [ ] **Step 4: Commit**

```bash
git add lib/features/auth/data/auth_repository.dart lib/features/auth/presentation/auth_controller.dart
git commit -m "feat(auth): accept currency when creating a shop"
```

---

### Task 4: LanguageStep widget (step 1)

**Files:**
- Create: `lib/features/onboarding/presentation/language_step.dart`

- [ ] **Step 1: Write the widget**

Create `lib/features/onboarding/presentation/language_step.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../shared/providers/locale_provider.dart';

/// Step 1 of onboarding: a compulsory language choice. Tapping a card applies
/// the locale live (the whole app — this screen included — switches) and enables
/// [onContinue]; until a card is tapped, Continue stays disabled so the choice
/// cannot be skipped. Language names are endonyms, shown the same in both modes.
class LanguageStep extends ConsumerStatefulWidget {
  const LanguageStep({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  ConsumerState<LanguageStep> createState() => _LanguageStepState();
}

class _LanguageStepState extends ConsumerState<LanguageStep> {
  Locale? _picked;

  void _pick(Locale locale) {
    ref.read(localeProvider.notifier).setLocale(locale);
    setState(() => _picked = locale);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.onboarding_languageTitle,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.onboarding_languageSubtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          _LanguageCard(
            label: 'English',
            selected: _picked == const Locale('en'),
            onTap: () => _pick(const Locale('en')),
          ),
          const SizedBox(height: 12),
          _LanguageCard(
            label: 'বাংলা',
            selected: _picked == const Locale('bn'),
            onTap: () => _pick(const Locale('bn')),
          ),
          const Spacer(),
          FilledButton(
            onPressed: _picked == null ? null : widget.onContinue,
            child: Text(l10n.common_continue),
          ),
        ],
      ),
    );
  }
}

class _LanguageCard extends StatelessWidget {
  const _LanguageCard({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.10)
              : scheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              color: selected ? scheme.primary : scheme.outlineVariant,
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/features/onboarding/presentation/language_step.dart`
Expected: "No issues found!"

- [ ] **Step 3: Commit**

```bash
git add lib/features/onboarding/presentation/language_step.dart
git commit -m "feat(onboarding): LanguageStep with compulsory live-applied language pick"
```

---

### Task 5: ShopSetupStep widget (step 2)

**Files:**
- Create: `lib/features/onboarding/presentation/shop_setup_step.dart`

- [ ] **Step 1: Write the widget**

Create `lib/features/onboarding/presentation/shop_setup_step.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/currency_option.dart';

/// Step 2 of onboarding: create the shop, rendered in the language chosen on
/// step 1. Includes the required default-currency picker (BDT default). On
/// success `createShop` flips `myShopProvider` and the router moves the user to
/// the dashboard — so this widget needs no explicit navigation.
class ShopSetupStep extends ConsumerStatefulWidget {
  const ShopSetupStep({super.key});

  @override
  ConsumerState<ShopSetupStep> createState() => _ShopSetupStepState();
}

class _ShopSetupStepState extends ConsumerState<ShopSetupStep> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  ShopCurrency _currency = ShopCurrency.bdt;

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    ref
        .read(authControllerProvider.notifier)
        .createShop(
          name: _nameController.text,
          address: _addressController.text,
          phone: _phoneController.text,
          currency: _currency.code,
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final isLoading = ref.watch(authControllerProvider).isLoading;

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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.profile_tellUs, style: theme.textTheme.titleMedium),
            const SizedBox(height: 24),
            TextFormField(
              controller: _nameController,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: l10n.profile_shopName,
                prefixIcon: const Icon(Icons.storefront_outlined),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? l10n.profile_shopNameRequired
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _addressController,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: l10n.profile_address,
                prefixIcon: const Icon(Icons.location_on_outlined),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: l10n.profile_phone,
                prefixIcon: const Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              l10n.onboarding_defaultCurrency,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            SegmentedButton<ShopCurrency>(
              segments: [
                for (final c in ShopCurrency.values)
                  ButtonSegment(
                    value: c,
                    label: Text('${c.symbol} ${c.code}'),
                  ),
              ],
              selected: {_currency},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _currency = s.first),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: isLoading ? null : _submit,
              child: isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.profile_createShop),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/features/onboarding/presentation/shop_setup_step.dart`
Expected: "No issues found!"

- [ ] **Step 3: Commit**

```bash
git add lib/features/onboarding/presentation/shop_setup_step.dart
git commit -m "feat(onboarding): ShopSetupStep with required BDT/USD currency picker"
```

---

### Task 6: OnboardingScreen wizard shell

**Files:**
- Create: `lib/features/onboarding/presentation/onboarding_screen.dart`

- [ ] **Step 1: Write the widget**

Create `lib/features/onboarding/presentation/onboarding_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/motion.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../auth/presentation/auth_controller.dart';
import 'language_step.dart';
import 'shop_setup_step.dart';

/// First-run setup wizard for a signed-in user who has no shop yet. Two steps
/// on one route: (1) compulsory language choice, (2) shop setup in that
/// language. A `NeverScrollableScrollPhysics` PageView makes it structurally
/// impossible to reach step 2 without completing step 1 — movement is only via
/// the step-1 Continue button and the step-2 back arrow. A Sign-out action is
/// kept as an escape hatch.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _step = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _go(int step) {
    setState(() => _step = step);
    _pageController.animateToPage(
      step,
      duration: AppMotion.page,
      curve: AppMotion.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final isLoading = ref.watch(authControllerProvider).isLoading;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: _step == 1 ? BackButton(onPressed: () => _go(0)) : null,
        title: Text(
          l10n.onboarding_step(_step + 1, 2),
          style: theme.textTheme.labelLarge,
        ),
        actions: [
          TextButton(
            onPressed: isLoading
                ? null
                : () => ref.read(authControllerProvider.notifier).signOut(),
            child: Text(l10n.common_signOut),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            LinearProgressIndicator(
              value: (_step + 1) / 2,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  LanguageStep(onContinue: () => _go(1)),
                  const ShopSetupStep(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/features/onboarding/presentation/onboarding_screen.dart`
Expected: "No issues found!"

- [ ] **Step 3: Commit**

```bash
git add lib/features/onboarding/presentation/onboarding_screen.dart
git commit -m "feat(onboarding): two-step wizard shell (progress + locked PageView)"
```

---

### Task 7: Wire the router to onboarding, remove ProfileSetupScreen

**Files:**
- Modify: `lib/core/router/app_router.dart`
- Remove: `lib/features/auth/presentation/profile_setup_screen.dart`

- [ ] **Step 1: Swap the import**

In `lib/core/router/app_router.dart`, replace the profile-setup import line:

```dart
import '../../features/auth/presentation/profile_setup_screen.dart';
```

with:

```dart
import '../../features/onboarding/presentation/onboarding_screen.dart';
```

(There is an existing `import '../../features/onboarding/presentation/welcome_screen.dart';` — add the new line next to it and delete the profile-setup one.)

- [ ] **Step 2: Rename the route constant**

In `lib/core/router/app_router.dart`, in `class AppRoutes`, replace:

```dart
  static const String profileSetup = '/profile-setup';
```

with:

```dart
  static const String onboarding = '/onboarding';
```

- [ ] **Step 3: Update the redirect logic**

In the `redirect:` callback, replace this block:

```dart
      return ref
          .read(myShopProvider)
          .maybeWhen(
            data: (shop) {
              final atSetup = loc == AppRoutes.profileSetup;
              if (shop == null) return atSetup ? null : AppRoutes.profileSetup;
              if (atSetup || preAuthLoc) return AppRoutes.dashboard;
              return null;
            },
            orElse: () => preAuthLoc ? AppRoutes.dashboard : null,
          );
```

with:

```dart
      return ref
          .read(myShopProvider)
          .maybeWhen(
            data: (shop) {
              final atOnboarding = loc == AppRoutes.onboarding;
              if (shop == null) {
                return atOnboarding ? null : AppRoutes.onboarding;
              }
              if (atOnboarding || preAuthLoc) return AppRoutes.dashboard;
              return null;
            },
            orElse: () => preAuthLoc ? AppRoutes.dashboard : null,
          );
```

- [ ] **Step 4: Update the route definition**

Replace the profile-setup `GoRoute`:

```dart
      GoRoute(
        path: AppRoutes.profileSetup,
        pageBuilder: (_, _) =>
            _transitionPage(const ProfileSetupScreen(), slide: false),
      ),
```

with:

```dart
      GoRoute(
        path: AppRoutes.onboarding,
        pageBuilder: (_, _) =>
            _transitionPage(const OnboardingScreen(), slide: false),
      ),
```

- [ ] **Step 5: Delete the old screen**

Run: `git rm lib/features/auth/presentation/profile_setup_screen.dart`
Expected: file staged for deletion.

- [ ] **Step 6: Verify nothing else references the removed symbols**

Run: `grep -rn "profileSetup\|ProfileSetupScreen\|profile-setup" lib/`
Expected: no matches (empty output).

- [ ] **Step 7: Verify the app compiles**

Run: `flutter analyze lib`
Expected: "No issues found!"

- [ ] **Step 8: Commit**

```bash
git add lib/core/router/app_router.dart
git commit -m "feat(onboarding): route shop-less users to /onboarding; remove ProfileSetupScreen"
```

---

### Task 8: Onboarding flow widget tests

**Files:**
- Create: `test/widgets/onboarding_screen_test.dart`

- [ ] **Step 1: Write the tests**

Create `test/widgets/onboarding_screen_test.dart`:

```dart
import 'package:ai_shopkeeper/features/auth/presentation/auth_controller.dart';
import 'package:ai_shopkeeper/features/onboarding/presentation/onboarding_screen.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:ai_shopkeeper/shared/providers/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Captures createShop args instead of hitting Supabase, and reports success so
/// the UI proceeds. The optional `currency` default mirrors the real controller.
class _RecordingAuthController extends AuthController {
  String? capturedName;
  String? capturedCurrency;

  @override
  Future<void> createShop({
    required String name,
    String? address,
    String? phone,
    String currency = 'BDT',
  }) async {
    capturedName = name;
    capturedCurrency = currency;
    state = const AsyncData(null);
  }
}

/// Mirrors app.dart: MaterialApp.locale is driven by localeProvider so a
/// setLocale() during the test actually re-localizes the tree.
class _TestApp extends ConsumerWidget {
  const _TestApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      home: const OnboardingScreen(),
    );
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('language step gates the shop step until a language is picked', (
    tester,
  ) async {
    late _RecordingAuthController rec;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(() {
            rec = _RecordingAuthController();
            return rec;
          }),
        ],
        child: const _TestApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Step 1 is showing; the shop form is not reachable yet.
    expect(find.text('Choose your language'), findsOneWidget);
    expect(find.text('Create shop'), findsNothing);

    // Continue is disabled until a card is tapped.
    final continueBtn = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Continue'),
    );
    expect(continueBtn.onPressed, isNull);
  });

  testWidgets('English → Continue → create shop with USD records USD', (
    tester,
  ) async {
    late _RecordingAuthController rec;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(() {
            rec = _RecordingAuthController();
            return rec;
          }),
        ],
        child: const _TestApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    // Step 2 is now visible.
    expect(find.text('Create shop'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Shop name *'),
      'Rahim Store',
    );
    await tester.tap(find.text('\$ USD'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create shop'));
    await tester.pumpAndSettle();

    expect(rec.capturedName, 'Rahim Store');
    expect(rec.capturedCurrency, 'USD');
  });

  testWidgets('tapping বাংলা switches the UI to Bengali live', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_RecordingAuthController.new),
        ],
        child: const _TestApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Choose your language'), findsOneWidget);
    await tester.tap(find.text('বাংলা'));
    await tester.pumpAndSettle();

    // The step-1 title is now Bengali.
    expect(find.text('আপনার ভাষা বেছে নিন'), findsOneWidget);
    expect(find.text('Choose your language'), findsNothing);
  });
}
```

- [ ] **Step 2: Run the tests**

Run: `flutter test test/widgets/onboarding_screen_test.dart`
Expected: PASS (3 tests). If the currency segment tap can't find `$ USD`, confirm the segment label in `shop_setup_step.dart` is `'${c.symbol} ${c.code}'` (renders `$ USD`).

- [ ] **Step 3: Commit**

```bash
git add test/widgets/onboarding_screen_test.dart
git commit -m "test(onboarding): gate, English→USD create, live Bengali switch"
```

---

### Task 9: Full verification

**Files:** none (verification only)

- [ ] **Step 1: Analyze the whole project**

Run: `flutter analyze`
Expected: "No issues found!"

- [ ] **Step 2: Run the full test suite**

Run: `flutter test`
Expected: All tests pass (previous 79 + 3 currency + 3 onboarding = 85), 0 failures.

- [ ] **Step 3: If anything fails, fix inline and re-run**

Re-run the failing file with `-v`, fix, then re-run `flutter test` until green. Do not proceed until all pass.

- [ ] **Step 4: Final commit (only if fixes were made)**

```bash
git add -A
git commit -m "chore(onboarding): finalize first-run wizard (analyze + tests green)"
```

---

## Self-Review

**Spec coverage:**
- First-time-only gate → Task 7 (redirect on `shop == null`). ✓
- Language before shop → Task 6 (`NeverScrollableScrollPhysics` PageView, page 0 first) + Task 8 gate test. ✓
- Language applied live & saved → Task 4 (`setLocale` on tap) + Task 8 live-switch test. ✓
- Language selection compulsory → Task 4 (Continue disabled until `_picked != null`) + Task 8 gate test. ✓
- Shop step in chosen language → Tasks 5/6 (l10n via `context.l10n`, MaterialApp watches locale) + Task 8. ✓
- Required currency saved to shop & used app-wide → Tasks 2/3/5 (`ShopCurrency` → `createShop(currency:)` → `shops.currency`) + Task 8 USD assertion. ✓
- Validate required fields → Task 5 (name validator; currency always set). ✓
- Clean/modern/mobile, existing patterns → reuses SegmentedButton/card/form patterns. ✓
- Out of scope honored → no Settings currency edit, no default flip, WelcomeScreen untouched. ✓

**Deviation from spec (intentional):** the spec listed `currency_bdt` / `currency_usd` ARB label keys. The plan instead renders compact, universal segment labels `৳ BDT` / `$ USD` (symbol+ISO code need no translation) to avoid two-segment overflow on narrow phones, and keeps only the localized field label `onboarding_defaultCurrency`. This satisfies the same requirement with less surface area.

**Placeholder scan:** none — every code step contains full code.

**Type consistency:** `ShopCurrency` (`.code`, `.symbol`, `.fromCode`, `.bdt`, `.usd`) is defined in Task 2 and used identically in Tasks 5 and 8. `createShop(..., String currency = 'BDT')` signature matches across Task 3 (repo + controller) and the Task 8 fake override. `AppRoutes.onboarding` / `OnboardingScreen` names match across Tasks 6 and 7.
