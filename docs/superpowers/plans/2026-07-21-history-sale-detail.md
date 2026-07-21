# Sale Detail Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a full-screen "Sale details" view that opens when a shopkeeper taps a sold item in the History tab, showing that one sale's frozen-snapshot numbers.

**Architecture:** A new stateless `SaleDetailScreen` receives the tapped `Transaction` through go_router's `extra` (no new DB query). It resolves the product name/unit live from `productsStreamProvider` and the currency from `myShopProvider`. History rows push the route: single-sale rows open detail directly; multi-item receipts keep their expand behavior and each expanded line becomes tappable.

**Tech Stack:** Flutter (Material 3), Riverpod 3, go_router 17, intl, flutter_gen l10n (en + bn), flutter_test.

## Global Constraints

- State management: Riverpod only. Widgets stay dumb; no business logic in widgets. (CLAUDE.md §6)
- Every new l10n key MUST exist in BOTH `lib/l10n/app_en.arb` and `lib/l10n/app_bn.arb` with identical key sets — enforced by `test/l10n_parity_test.dart`.
- Money via `Money.format(amount, currencyCode: currency)`; quantities via `Qty.format(...)` (`lib/shared/extensions/format.dart`).
- Profit color via the theme extension: `Theme.of(context).extension<AppColors>()!.positive` / `.negative` (`lib/core/config/theme.dart`).
- Prices/profit come ONLY from the transaction's frozen snapshot (`buyingPrice`/`sellingPrice`); never recompute from current product prices. (CLAUDE.md §4)
- Full-screen routes live on the root navigator (`parentNavigatorKey: _rootKey`) with `_transitionPage(...)`, matching existing routes in `lib/core/router/app_router.dart`.
- Localized strings accessed via `context.l10n` (`lib/core/l10n/l10n_ext.dart`); shared enum/label helpers live in `lib/core/l10n/enum_labels.dart`.

---

### Task 1: Localized strings + sale-source label helper

**Files:**
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_bn.arb`
- Modify: `lib/core/l10n/enum_labels.dart`
- Test: `test/sale_source_label_test.dart` (create)

**Interfaces:**
- Produces: generated getters `l10n.saleDetail_title`, `saleDetail_soldOn`, `saleDetail_quantity`, `saleDetail_priceEach`, `saleDetail_total`, `saleDetail_cost`, `saleDetail_profit`, `saleDetail_enteredBy`, `saleDetail_frozenNote`, `saleDetail_notFound`, `saleDetail_sourceManual`, `saleDetail_sourceVoice`, `saleDetail_sourcePhoto`.
- Produces: `String saleSourceLabel(AppLocalizations l10n, String? source)` in `enum_labels.dart` — maps `'voice'→voice`, `'image'→photo`, `'manual'→manual`, anything else (incl. null) → `'—'`.

- [ ] **Step 1: Add the English keys**

In `lib/l10n/app_en.arb`, after the `history_colAmount` entry (line ~215), add:

```json
  "saleDetail_title": "Sale details",
  "saleDetail_soldOn": "Sold on",
  "saleDetail_quantity": "Quantity",
  "saleDetail_priceEach": "Price each",
  "saleDetail_total": "Total",
  "saleDetail_cost": "Cost",
  "saleDetail_profit": "Profit",
  "saleDetail_enteredBy": "Entered by",
  "saleDetail_frozenNote": "Prices are locked in from the moment of sale.",
  "saleDetail_notFound": "Sale not found.",
  "saleDetail_sourceManual": "Manual",
  "saleDetail_sourceVoice": "Voice",
  "saleDetail_sourcePhoto": "Photo scan",
```

- [ ] **Step 2: Add the Bengali keys**

In `lib/l10n/app_bn.arb`, at the matching location, add the same keys with Bengali values:

```json
  "saleDetail_title": "বিক্রির বিবরণ",
  "saleDetail_soldOn": "বিক্রির সময়",
  "saleDetail_quantity": "পরিমাণ",
  "saleDetail_priceEach": "প্রতি একক দাম",
  "saleDetail_total": "মোট",
  "saleDetail_cost": "খরচ",
  "saleDetail_profit": "লাভ",
  "saleDetail_enteredBy": "যেভাবে এন্ট্রি হয়েছে",
  "saleDetail_frozenNote": "দাম বিক্রির মুহূর্তেই স্থির হয়ে যায়।",
  "saleDetail_notFound": "বিক্রি খুঁজে পাওয়া যায়নি।",
  "saleDetail_sourceManual": "ম্যানুয়াল",
  "saleDetail_sourceVoice": "ভয়েস",
  "saleDetail_sourcePhoto": "ছবি স্ক্যান",
```

- [ ] **Step 3: Regenerate localizations**

Run: `flutter gen-l10n`
Expected: regenerates `lib/l10n/app_localizations*.dart` with the new getters, no errors.

- [ ] **Step 4: Write the failing test for the source-label helper**

Create `test/sale_source_label_test.dart`:

```dart
import 'package:ai_shopkeeper/core/l10n/enum_labels.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:ai_shopkeeper/l10n/app_localizations_en.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final AppLocalizations l10n = AppLocalizationsEn();

  test('maps known sources to their localized labels', () {
    expect(saleSourceLabel(l10n, 'manual'), 'Manual');
    expect(saleSourceLabel(l10n, 'voice'), 'Voice');
    expect(saleSourceLabel(l10n, 'image'), 'Photo scan');
  });

  test('null and unknown sources fall back to an em dash', () {
    expect(saleSourceLabel(l10n, null), '—');
    expect(saleSourceLabel(l10n, 'something-else'), '—');
  });
}
```

- [ ] **Step 5: Run it to confirm it fails**

Run: `flutter test test/sale_source_label_test.dart`
Expected: FAIL — `saleSourceLabel` is not defined.

- [ ] **Step 6: Add the helper**

Append to `lib/core/l10n/enum_labels.dart`:

```dart
/// Localized label for a transaction's `source` ('voice' | 'image' | 'manual').
/// Unknown or null sources render as an em dash — older rows may have no source.
String saleSourceLabel(AppLocalizations l10n, String? source) => switch (source) {
  'voice' => l10n.saleDetail_sourceVoice,
  'image' => l10n.saleDetail_sourcePhoto,
  'manual' => l10n.saleDetail_sourceManual,
  _ => '—',
};
```

- [ ] **Step 7: Run the tests + parity check**

Run: `flutter test test/sale_source_label_test.dart test/l10n_parity_test.dart`
Expected: PASS (both files).

- [ ] **Step 8: Commit**

```bash
git add lib/l10n/app_en.arb lib/l10n/app_bn.arb lib/l10n/app_localizations*.dart lib/core/l10n/enum_labels.dart test/sale_source_label_test.dart
git commit -m "feat(history): sale-detail l10n strings and source-label helper"
```

---

### Task 2: SaleDetailScreen widget

**Files:**
- Create: `lib/features/transactions/presentation/sale_detail_screen.dart`
- Test: `test/widgets/sale_detail_screen_test.dart` (create)

**Interfaces:**
- Consumes: `saleSourceLabel(AppLocalizations, String?)` (Task 1); `Transaction` (`lib/features/transactions/domain/transaction.dart`) with getters `revenue`, `cost`, `profit`; `productsStreamProvider` (`lib/features/inventory/presentation/inventory_controller.dart`), `myShopProvider` (`lib/features/auth/data/auth_repository.dart`); `Money`/`Qty` (`lib/shared/extensions/format.dart`); `AppColors` theme extension (`lib/core/config/theme.dart`); `context.l10n` (`lib/core/l10n/l10n_ext.dart`).
- Produces: `class SaleDetailScreen extends ConsumerWidget` with `const SaleDetailScreen({super.key, required this.sale})` where `final Transaction? sale`.

- [ ] **Step 1: Write the failing widget test**

Create `test/widgets/sale_detail_screen_test.dart`:

```dart
import 'package:ai_shopkeeper/core/config/theme.dart';
import 'package:ai_shopkeeper/features/auth/data/auth_repository.dart';
import 'package:ai_shopkeeper/features/auth/domain/shop.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/inventory/presentation/inventory_controller.dart';
import 'package:ai_shopkeeper/features/transactions/domain/transaction.dart';
import 'package:ai_shopkeeper/features/transactions/presentation/sale_detail_screen.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

const _product = Product(
  id: 'p1',
  shopId: 's',
  name: 'Soyabean Oil',
  unitType: UnitType.volume,
  unit: ProductUnit.litre,
  buyingPrice: 700,
  sellingPrice: 850,
  quantity: 12,
);

Transaction _sale({double buying = 700, double selling = 850}) => Transaction(
  id: 't1',
  shopId: 's',
  productId: 'p1',
  type: 'sale',
  quantity: 0.5,
  buyingPrice: buying,
  sellingPrice: selling,
  source: 'manual',
  createdAt: DateTime(2026, 7, 21, 20, 44),
);

Widget _harness(Transaction? sale, {List<Product> products = const [_product]}) =>
    ProviderScope(
      overrides: [
        myShopProvider.overrideWith(
          (ref) => const Shop(id: 's', ownerId: 'o', name: 'Shop', currency: 'USD'),
        ),
        productsStreamProvider.overrideWith((ref) => Stream.value(products)),
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
        home: SaleDetailScreen(sale: sale),
      ),
    );

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('renders the sale story: name, qty+unit, total, profit, source',
      (tester) async {
    await tester.pumpWidget(_harness(_sale()));
    await tester.pumpAndSettle();

    expect(find.text('Soyabean Oil'), findsOneWidget);
    expect(find.text('0.5 litre'), findsOneWidget);
    // total = 850 * 0.5 = 425 ; profit = (850-700)*0.5 = 75
    expect(find.textContaining('425'), findsWidgets);
    expect(find.textContaining('75'), findsWidgets);
    expect(find.text('Manual'), findsOneWidget);
  });

  testWidgets('deleted product falls back to "Sale" and a plain quantity',
      (tester) async {
    await tester.pumpWidget(_harness(_sale(), products: const []));
    await tester.pumpAndSettle();

    expect(find.text('Sale'), findsWidgets);
    expect(find.text('0.5'), findsOneWidget); // no unit label
  });

  testWidgets('null sale shows the not-found state', (tester) async {
    await tester.pumpWidget(_harness(null));
    await tester.pumpAndSettle();
    expect(find.text('Sale not found.'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `flutter test test/widgets/sale_detail_screen_test.dart`
Expected: FAIL — `sale_detail_screen.dart` / `SaleDetailScreen` does not exist.

- [ ] **Step 3: Implement the screen**

Create `lib/features/transactions/presentation/sale_detail_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/config/theme.dart';
import '../../../core/l10n/enum_labels.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../shared/extensions/format.dart';
import '../../auth/data/auth_repository.dart';
import '../../inventory/domain/product.dart';
import '../../inventory/presentation/inventory_controller.dart';
import '../domain/transaction.dart';

/// Full-screen "story" of a single past sale. Receives the tapped [Transaction]
/// via go_router `extra`; all money/profit figures are the FROZEN snapshot on
/// the row (never recomputed from current prices — CLAUDE.md §4). The product
/// name/unit is resolved live from [productsStreamProvider], falling back
/// gracefully when the product was later deleted.
class SaleDetailScreen extends ConsumerWidget {
  const SaleDetailScreen({super.key, required this.sale});

  final Transaction? sale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    if (sale == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.saleDetail_title)),
        body: Center(child: Text(l10n.saleDetail_notFound)),
      );
    }
    final t = sale!;

    final currency = ref.watch(myShopProvider).value?.currency ?? 'USD';
    final products =
        ref.watch(productsStreamProvider).value ?? const <Product>[];
    Product? product;
    for (final p in products) {
      if (p.id == t.productId) {
        product = p;
        break;
      }
    }
    final name = (product?.name.isNotEmpty ?? false)
        ? product!.name
        : l10n.history_saleFallback;
    final qtyLabel = product != null
        ? '${Qty.format(t.quantity)} ${product.unit.label}'
        : Qty.format(t.quantity);

    final dt = (t.createdAt ?? DateTime.now()).toLocal();
    // AM/PM stays Latin (universally read on Bangladeshi tills); DateFormat
    // localizes the digits via Intl.defaultLocale — matches history_screen.
    final soldOn =
        '${DateFormat('EEE, d MMM y').format(dt)} · '
        '${DateFormat('h:mm').format(dt)}${dt.hour < 12 ? 'AM' : 'PM'}';

    final colors = theme.extension<AppColors>()!;
    final profitColor = t.profit >= 0 ? colors.positive : colors.negative;

    String money(double v) => Money.format(v, currencyCode: currency);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.saleDetail_title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Row(
            children: [
              _Avatar(letter: name.isNotEmpty ? name[0].toUpperCase() : '?'),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            l10n.saleDetail_soldOn,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(soldOn, style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          const Divider(),
          _DetailRow(label: l10n.saleDetail_quantity, value: qtyLabel),
          _DetailRow(label: l10n.saleDetail_priceEach, value: money(t.sellingPrice)),
          _DetailRow(
            label: l10n.saleDetail_total,
            value: money(t.revenue),
            emphasize: true,
          ),
          _DetailRow(label: l10n.saleDetail_cost, value: money(t.cost)),
          _DetailRow(
            label: l10n.saleDetail_profit,
            value: money(t.profit),
            valueColor: profitColor,
            emphasize: true,
          ),
          _DetailRow(
            label: l10n.saleDetail_enteredBy,
            value: saleSourceLabel(l10n, t.source),
          ),
          const Divider(),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.saleDetail_frozenNote,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.letter});
  final String letter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        letter,
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: (emphasize
                    ? theme.textTheme.titleMedium
                    : theme.textTheme.bodyLarge)
                ?.copyWith(
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
              color: valueColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run the widget test to confirm it passes**

Run: `flutter test test/widgets/sale_detail_screen_test.dart`
Expected: PASS (all three tests).

- [ ] **Step 5: Analyze**

Run: `flutter analyze lib/features/transactions/presentation/sale_detail_screen.dart`
Expected: No issues found.

- [ ] **Step 6: Commit**

```bash
git add lib/features/transactions/presentation/sale_detail_screen.dart test/widgets/sale_detail_screen_test.dart
git commit -m "feat(history): sale detail screen"
```

---

### Task 3: Route + History tap wiring

**Files:**
- Modify: `lib/core/router/app_router.dart`
- Modify: `lib/features/transactions/presentation/history_screen.dart`
- Test: `test/widgets/history_sale_tap_test.dart` (create)

**Interfaces:**
- Consumes: `SaleDetailScreen` (Task 2); `Transaction` (`../domain/transaction.dart`).
- Produces: route constant `AppRoutes.saleDetail = '/history/sale'`; go_router route `'/history/sale/:id'` on `_rootKey` that reads `state.extra as Transaction?`. History rows call `context.push('${AppRoutes.saleDetail}/${t.id}', extra: t)`.

- [ ] **Step 1: Add the route constant and route**

In `lib/core/router/app_router.dart`:

Add the imports near the other feature imports (top of file):

```dart
import '../../features/transactions/domain/transaction.dart';
import '../../features/transactions/presentation/sale_detail_screen.dart';
```

Add the constant in `AppRoutes` (after `customers`):

```dart
  static const String saleDetail = '/history/sale';
```

Add the route among the full-screen root-navigator routes (e.g. right after the `/customers/:id` route):

```dart
      GoRoute(
        path: '/history/sale/:id',
        parentNavigatorKey: _rootKey,
        pageBuilder: (_, state) => _transitionPage(
          SaleDetailScreen(sale: state.extra as Transaction?),
        ),
      ),
```

- [ ] **Step 2: Wire the taps in history_screen.dart**

In `lib/features/transactions/presentation/history_screen.dart`, add the imports (after the existing `intl` import at the top):

```dart
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
```

In `_ReceiptTileState`, add a navigation helper method (anywhere inside the class, e.g. after `_lineQty`):

```dart
  void _openDetail(Transaction line) =>
      context.push('${AppRoutes.saleDetail}/${line.id}', extra: line);
```

Change the summary-row `InkWell` `onTap` (currently `canExpand ? () => setState(...) : null`) so a single sale opens its detail:

```dart
          onTap: canExpand
              ? () => setState(() => _expanded = !_expanded)
              : () => _openDetail(widget.row.receipt.lines.single),
```

Make each expanded line tappable. Wrap the existing per-line `Padding(...)` (the one inside `for (final line in row.receipt.lines)`) in an `InkWell`:

```dart
                for (final line in row.receipt.lines)
                  InkWell(
                    onTap: () => _openDetail(line),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 5, 12, 5),
                      child: Row(
                        // ...existing line Row children unchanged...
                      ),
                    ),
                  ),
```

(Only the `InkWell` wrapper and its `onTap` are new — the inner `Padding`/`Row` content is exactly as before.)

- [ ] **Step 3: Write the failing navigation test**

Create `test/widgets/history_sale_tap_test.dart`:

```dart
import 'package:ai_shopkeeper/features/auth/data/auth_repository.dart';
import 'package:ai_shopkeeper/features/auth/domain/shop.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/inventory/presentation/inventory_controller.dart';
import 'package:ai_shopkeeper/features/transactions/domain/transaction.dart';
import 'package:ai_shopkeeper/features/transactions/presentation/history_screen.dart';
import 'package:ai_shopkeeper/features/transactions/presentation/sale_detail_screen.dart';
import 'package:ai_shopkeeper/features/transactions/presentation/sales_providers.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

const _product = Product(
  id: 'p1',
  shopId: 's',
  name: 'Soyabean Oil',
  unitType: UnitType.volume,
  unit: ProductUnit.litre,
  buyingPrice: 700,
  sellingPrice: 850,
  quantity: 12,
);

final _sale = Transaction(
  id: 't1',
  shopId: 's',
  productId: 'p1',
  type: 'sale',
  quantity: 0.5,
  buyingPrice: 700,
  sellingPrice: 850,
  source: 'manual',
  createdAt: DateTime(2026, 7, 21, 20, 44),
);

GoRouter _router() => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, _) => const HistoryScreen()),
    GoRoute(
      path: '/history/sale/:id',
      builder: (_, state) =>
          SaleDetailScreen(sale: state.extra as Transaction?),
    ),
  ],
);

Widget _harness() => ProviderScope(
  overrides: [
    myShopProvider.overrideWith(
      (ref) => const Shop(id: 's', ownerId: 'o', name: 'Shop', currency: 'USD'),
    ),
    productsStreamProvider.overrideWith((ref) => Stream.value(const [_product])),
    recentSalesProvider.overrideWith((ref) async => [_sale]),
    earliestSaleDateProvider.overrideWith((ref) async => null),
  ],
  child: MaterialApp.router(
    routerConfig: _router(),
    locale: const Locale('en'),
    supportedLocales: supportedAppLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
  ),
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('tapping a single sale row opens its detail screen',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    // The row shows the product name; the detail screen title does not exist yet.
    expect(find.text('Sale details'), findsNothing);

    await tester.tap(find.text('Soyabean Oil'));
    await tester.pumpAndSettle();

    // Now on the detail screen.
    expect(find.text('Sale details'), findsOneWidget);
    expect(find.text('0.5 litre'), findsOneWidget);
  });
}
```

- [ ] **Step 4: Run the test**

Run: `flutter test test/widgets/history_sale_tap_test.dart`
Expected: PASS. (If Steps 1–2 were not yet applied it FAILS at the tap — confirming the wiring is what makes it pass.)

- [ ] **Step 5: Full analyze + test sweep**

Run: `flutter analyze` then `flutter test`
Expected: analyze clean; all tests green (existing suite + 3 new files).

- [ ] **Step 6: Commit**

```bash
git add lib/core/router/app_router.dart lib/features/transactions/presentation/history_screen.dart test/widgets/history_sale_tap_test.dart
git commit -m "feat(history): tap a sold item to open its sale detail"
```

---

## Self-Review

**Spec coverage:**
- Navigation/entry points (single sale + expanded receipt lines) → Task 3.
- Route via `extra`, no DB query, name resolved from `productsStreamProvider`, deleted-product fallback, missing-`extra` not-found state → Task 2 (screen) + Task 3 (route).
- Screen content rows (qty+unit, price each, total, cost, profit color, entered-by, frozen note) → Task 2.
- Frozen-snapshot rule → Task 2 uses `t.revenue`/`t.cost`/`t.profit` (snapshot getters) only.
- l10n in en + bn, parity test → Task 1.
- Source labels helper (reuse-or-create) → Task 1 creates `saleSourceLabel` (confirmed none existed).
- Testing (render correctness, profit path, navigation, parity, analyze) → Tasks 1–3.

**Placeholder scan:** none — every code step contains full code and exact commands.

**Type consistency:** `SaleDetailScreen({required Transaction? sale})` used identically in Tasks 2 and 3; `saleSourceLabel(AppLocalizations, String?)` defined in Task 1 and consumed in Task 2; route constant `AppRoutes.saleDetail` defined and used consistently; provider override signatures match their definitions (`recentSalesProvider` FutureProvider, `productsStreamProvider` StreamProvider, `earliestSaleDateProvider` FutureProvider, `myShopProvider` FutureProvider).
