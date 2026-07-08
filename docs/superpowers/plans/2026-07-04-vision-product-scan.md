# Vision Product Scan Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a flag-gated "Scan Product" flow: photograph an item, a vision LLM (Gemini/OpenAI, behind a Supabase Edge Function) picks the matching product from the shop's own list, and the app opens the existing Sell confirmation sheet pre-filled; loose/unbranded items fall back to a manual product picker.

**Architecture:** Pure Dart decision core (testable, no I/O) + a thin repository calling a Supabase Edge Function that holds the API keys and switches provider server-side. All new files are additive and gated behind `VISION_SCAN_ENABLED` (default off). No embeddings/pgvector/photo storage.

**Tech Stack:** Flutter, Riverpod, `supabase_flutter` (`functions.invoke`), `image_picker`, Supabase Edge Functions (Deno/TypeScript), Gemini & OpenAI vision APIs.

**Branch:** `feat/vision-product-scan` · **Rollback:** `git checkout checkpoint-pre-vision-scan`

---

## File Structure

- `lib/core/config/feature_flags.dart` — compile-time `visionScanEnabled` flag.
- `lib/features/scan/domain/recognition_result.dart` — DTOs + manual `fromJson` (plain Dart, no codegen, so parsing is directly unit-testable).
- `lib/features/scan/domain/scan_decision.dart` — pure decision logic (confidence → UI action).
- `lib/features/scan/domain/scan_candidates.dart` — pure helper: products → candidate maps.
- `lib/features/scan/data/vision_scan_repository.dart` — calls `functions.invoke('recognize-product')`.
- `lib/features/scan/presentation/scan_controller.dart` — orchestrates capture → recognize → decide.
- `lib/features/scan/presentation/scan_screen.dart` — entry screen: capture + progress + routing.
- `lib/features/scan/presentation/product_picker_sheet.dart` — shared searchable picker (used for "Did you mean?" and manual pick).
- `supabase/functions/recognize-product/index.ts` — Edge Function with Gemini + OpenAI adapters.
- Tests: `test/scan_recognition_parse_test.dart`, `test/scan_decision_test.dart`, `test/scan_candidates_test.dart`.
- Modified (additive only): `lib/core/router/app_router.dart` (add `/scan` route), `lib/features/inventory/presentation/inventory_list_screen.dart` (flag-gated Scan button), `pubspec.yaml` + `android/app/src/main/AndroidManifest.xml` (image_picker).

---

# PHASE 1 — Decision core + contract (fully behind the flag, no external deps)

## Task 1: Feature flag

**Files:**
- Create: `lib/core/config/feature_flags.dart`

- [ ] **Step 1: Create the flag**

```dart
/// Compile-time feature flags via `--dart-define`. Default OFF so unfinished
/// features stay invisible in normal builds and releases.
class FeatureFlags {
  const FeatureFlags._();

  /// Enables the camera "Scan Product" flow. Turn on with
  /// `--dart-define=VISION_SCAN_ENABLED=true`.
  static const bool visionScanEnabled =
      bool.fromEnvironment('VISION_SCAN_ENABLED', defaultValue: false);
}
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/core/config/feature_flags.dart`
Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add lib/core/config/feature_flags.dart
git commit -m "feat(scan): add VISION_SCAN_ENABLED feature flag (default off)"
```

---

## Task 2: Recognition DTOs + parsing (TDD)

**Files:**
- Create: `lib/features/scan/domain/recognition_result.dart`
- Test: `test/scan_recognition_parse_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:ai_shopkeeper/features/scan/domain/recognition_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RecognitionResult.fromJson', () {
    test('parses a strong single match', () {
      final r = RecognitionResult.fromJson({
        'status': 'match',
        'read_brand': 'Pepsi',
        'read_name': 'Pepsi',
        'read_size': '500ml',
        'matches': [
          {'product_id': 'a1', 'confidence': 0.94},
        ],
      });
      expect(r.status, RecognitionStatus.match);
      expect(r.readBrand, 'Pepsi');
      expect(r.matches.single.productId, 'a1');
      expect(r.matches.single.confidence, closeTo(0.94, 1e-9));
    });

    test('parses none with empty matches', () {
      final r = RecognitionResult.fromJson({'status': 'none', 'matches': []});
      expect(r.status, RecognitionStatus.none);
      expect(r.matches, isEmpty);
      expect(r.readBrand, isNull);
    });

    test('unknown/missing status falls back to none', () {
      final r = RecognitionResult.fromJson({'matches': []});
      expect(r.status, RecognitionStatus.none);
    });

    test('integer confidence is coerced to double', () {
      final r = RecognitionResult.fromJson({
        'status': 'multiple',
        'matches': [
          {'product_id': 'a1', 'confidence': 1},
          {'product_id': 'a2', 'confidence': 0},
        ],
      });
      expect(r.matches.first.confidence, 1.0);
      expect(r.matches.last.confidence, 0.0);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/scan_recognition_parse_test.dart`
Expected: FAIL — `recognition_result.dart` / `RecognitionResult` not found.

- [ ] **Step 3: Write the implementation**

```dart
/// The outcome of a vision recognition request. Plain Dart (no codegen) so the
/// JSON parsing is small, explicit, and directly unit-testable.

enum RecognitionStatus { match, multiple, none }

/// One candidate the model matched, by the shop's own product id.
class ProductMatch {
  const ProductMatch({required this.productId, required this.confidence});

  final String productId;
  final double confidence;

  factory ProductMatch.fromJson(Map<String, dynamic> json) => ProductMatch(
    productId: json['product_id'] as String,
    confidence: (json['confidence'] as num).toDouble(),
  );
}

/// Normalized result returned by the `recognize-product` Edge Function.
class RecognitionResult {
  const RecognitionResult({
    required this.status,
    this.matches = const <ProductMatch>[],
    this.readBrand,
    this.readName,
    this.readSize,
  });

  final RecognitionStatus status;
  final List<ProductMatch> matches;
  final String? readBrand;
  final String? readName;
  final String? readSize;

  factory RecognitionResult.fromJson(Map<String, dynamic> json) {
    final rawMatches = (json['matches'] as List?) ?? const [];
    return RecognitionResult(
      status: _statusFrom(json['status']),
      matches: [
        for (final m in rawMatches)
          ProductMatch.fromJson(Map<String, dynamic>.from(m as Map)),
      ],
      readBrand: json['read_brand'] as String?,
      readName: json['read_name'] as String?,
      readSize: json['read_size'] as String?,
    );
  }

  static RecognitionStatus _statusFrom(Object? raw) => switch (raw) {
    'match' => RecognitionStatus.match,
    'multiple' => RecognitionStatus.multiple,
    _ => RecognitionStatus.none,
  };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/scan_recognition_parse_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/scan/domain/recognition_result.dart test/scan_recognition_parse_test.dart
git commit -m "feat(scan): RecognitionResult DTOs + JSON parsing"
```

---

## Task 3: Decision logic (TDD) — the heart of the feature

**Files:**
- Create: `lib/features/scan/domain/scan_decision.dart`
- Test: `test/scan_decision_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:ai_shopkeeper/features/scan/domain/recognition_result.dart';
import 'package:ai_shopkeeper/features/scan/domain/scan_decision.dart';
import 'package:flutter_test/flutter_test.dart';

RecognitionResult _result(List<(String, double)> m, {RecognitionStatus s = RecognitionStatus.match}) =>
    RecognitionResult(
      status: s,
      matches: [for (final e in m) ProductMatch(productId: e.$1, confidence: e.$2)],
    );

void main() {
  group('decideScanAction', () {
    test('strong top-1 with clear margin -> autoSell', () {
      final d = decideScanAction(_result([('a', 0.92), ('b', 0.40)]));
      expect(d.action, ScanAction.autoSell);
      expect(d.matches.single.productId, 'a');
    });

    test('strong top-1 but close runner-up -> chooser', () {
      final d = decideScanAction(_result([('a', 0.90), ('b', 0.85)]));
      expect(d.action, ScanAction.chooseFromMatches);
      expect(d.matches.map((m) => m.productId), ['a', 'b']);
    });

    test('no strong match but some above ambiguous -> chooser', () {
      final d = decideScanAction(_result([('a', 0.60), ('b', 0.55), ('c', 0.10)]));
      expect(d.action, ScanAction.chooseFromMatches);
      expect(d.matches.map((m) => m.productId), ['a', 'b']);
    });

    test('all below ambiguous -> noMatch', () {
      final d = decideScanAction(_result([('a', 0.30)]));
      expect(d.action, ScanAction.noMatch);
      expect(d.matches, isEmpty);
    });

    test('empty matches -> noMatch', () {
      final d = decideScanAction(_result([], s: RecognitionStatus.none));
      expect(d.action, ScanAction.noMatch);
    });

    test('unsorted input is ranked before deciding', () {
      final d = decideScanAction(_result([('b', 0.40), ('a', 0.92)]));
      expect(d.action, ScanAction.autoSell);
      expect(d.matches.single.productId, 'a');
    });

    test('chooser caps at 5 candidates', () {
      final d = decideScanAction(_result([
        ('a', 0.60), ('b', 0.59), ('c', 0.58), ('d', 0.57), ('e', 0.56), ('f', 0.55),
      ]));
      expect(d.action, ScanAction.chooseFromMatches);
      expect(d.matches.length, 5);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/scan_decision_test.dart`
Expected: FAIL — `scan_decision.dart` not found.

- [ ] **Step 3: Write the implementation**

```dart
import 'recognition_result.dart';

/// What the UI should do after a recognition result comes back.
enum ScanAction { autoSell, chooseFromMatches, noMatch }

/// Tunable thresholds mapping model confidences to a UI action. Calibrate on
/// real photos once a provider is chosen (spec §6).
class ScanThresholds {
  const ScanThresholds({
    this.strong = 0.80,
    this.margin = 0.15,
    this.ambiguous = 0.50,
    this.maxChoices = 5,
  });

  /// Top-1 must reach this confidence to auto-open the sell sheet…
  final double strong;

  /// …and lead the runner-up by at least this margin.
  final double margin;

  /// Any match at/above this can appear in the chooser.
  final double ambiguous;

  /// Cap on candidates shown in the "Did you mean?" chooser.
  final int maxChoices;
}

/// The action to take plus the matches it applies to.
class ScanDecision {
  const ScanDecision(this.action, this.matches);
  final ScanAction action;
  final List<ProductMatch> matches;
}

/// Pure decision: given a [RecognitionResult], decide the UI action and which
/// matches to act on. No I/O — fully unit-testable.
ScanDecision decideScanAction(
  RecognitionResult result, {
  ScanThresholds thresholds = const ScanThresholds(),
}) {
  final ranked = [...result.matches]
    ..sort((a, b) => b.confidence.compareTo(a.confidence));
  if (ranked.isEmpty) return const ScanDecision(ScanAction.noMatch, []);

  final top = ranked.first;
  final second = ranked.length > 1 ? ranked[1] : null;
  final leadsClearly =
      second == null || (top.confidence - second.confidence) >= thresholds.margin;

  if (top.confidence >= thresholds.strong && leadsClearly) {
    return ScanDecision(ScanAction.autoSell, [top]);
  }

  final ambiguous =
      ranked.where((m) => m.confidence >= thresholds.ambiguous).toList();
  if (ambiguous.isNotEmpty) {
    return ScanDecision(
      ScanAction.chooseFromMatches,
      ambiguous.take(thresholds.maxChoices).toList(),
    );
  }
  return const ScanDecision(ScanAction.noMatch, []);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/scan_decision_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/scan/domain/scan_decision.dart test/scan_decision_test.dart
git commit -m "feat(scan): pure confidence->action decision logic"
```

---

## Task 4: Candidate builder (TDD)

**Files:**
- Create: `lib/features/scan/domain/scan_candidates.dart`
- Test: `test/scan_candidates_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/scan/domain/scan_candidates.dart';
import 'package:flutter_test/flutter_test.dart';

Product _p(String id, String name, {String? brand, String? variant}) => Product(
  id: id, shopId: 's', name: name, brand: brand, variant: variant,
);

void main() {
  test('buildCandidates maps id/name/brand/variant and drops nulls', () {
    final out = buildCandidates([
      _p('a', 'Pepsi 500ml', brand: 'Pepsi', variant: '500ml'),
      _p('b', 'Loose rice'),
    ]);
    expect(out, [
      {'id': 'a', 'name': 'Pepsi 500ml', 'brand': 'Pepsi', 'variant': '500ml'},
      {'id': 'b', 'name': 'Loose rice'},
    ]);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/scan_candidates_test.dart`
Expected: FAIL — `scan_candidates.dart` not found.

- [ ] **Step 3: Write the implementation**

```dart
import '../../inventory/domain/product.dart';

/// Turns the shop's products into the compact candidate list sent to the vision
/// model. Only id/name are guaranteed; brand/variant are included when present
/// (they sharpen label matching). Loose items simply carry no brand/variant.
List<Map<String, dynamic>> buildCandidates(List<Product> products) => [
  for (final p in products)
    {
      'id': p.id,
      'name': p.name,
      if (p.brand != null && p.brand!.isNotEmpty) 'brand': p.brand,
      if (p.variant != null && p.variant!.isNotEmpty) 'variant': p.variant,
    },
];
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/scan_candidates_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/scan/domain/scan_candidates.dart test/scan_candidates_test.dart
git commit -m "feat(scan): pure product->candidate builder"
```

---

## Task 5: Vision scan repository

**Files:**
- Create: `lib/features/scan/data/vision_scan_repository.dart`

No unit test (network I/O; codebase tests only pure helpers). Verified by `flutter analyze`.

- [ ] **Step 1: Write the repository**

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../domain/recognition_result.dart';

/// Calls the `recognize-product` Edge Function, which holds the API keys and
/// picks the vision provider server-side. Returns a normalized result.
class VisionScanRepository {
  VisionScanRepository(this._client);

  final SupabaseClient _client;

  Future<Result<RecognitionResult>> recognize({
    required Uint8List imageBytes,
    required List<Map<String, dynamic>> candidates,
  }) async {
    try {
      final res = await _client.functions.invoke(
        'recognize-product',
        body: {
          'image_base64': base64Encode(imageBytes),
          'candidates': candidates,
        },
      );
      final data = res.data;
      final map = data is String ? jsonDecode(data) : data;
      return Result.success(
        RecognitionResult.fromJson(Map<String, dynamic>.from(map as Map)),
      );
    } catch (e) {
      return Result.failure(_map(e));
    }
  }

  Failure _map(Object e) {
    if (e is FunctionException) {
      return const DatabaseFailure(
        'Could not recognize the product. Please try again.',
      );
    }
    if (e is SocketException) {
      return const NetworkFailure('No internet connection. Please try again.');
    }
    return const UnexpectedFailure('Something went wrong. Please try again.');
  }
}

final visionScanRepositoryProvider = Provider<VisionScanRepository>((ref) {
  return VisionScanRepository(ref.watch(supabaseClientProvider));
});
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/features/scan/data/vision_scan_repository.dart`
Expected: No issues found. (If `FunctionException` is not exported by the installed `supabase_flutter`, replace the `if (e is FunctionException)` branch with `if (e is PostgrestException || e.toString().contains('Function')) {` — keep the same message.)

- [ ] **Step 3: Commit**

```bash
git add lib/features/scan/data/vision_scan_repository.dart
git commit -m "feat(scan): VisionScanRepository over functions.invoke"
```

---

## Task 6: Stub Edge Function (contract placeholder)

**Files:**
- Create: `supabase/functions/recognize-product/index.ts`

A canned response so the contract exists and can be deployed for early manual testing. Replaced by the real adapters in Task 11. Not compiled by Flutter.

- [ ] **Step 1: Write the stub**

```ts
// Supabase Edge Function: recognize-product (STUB — replaced in Task 11).
// MEMBER B owns the real vision prompt/call; this returns a canned response so
// the Flutter contract can be exercised before the providers are wired.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

Deno.serve(async (req) => {
  const { candidates } = await req.json().catch(() => ({ candidates: [] }));
  const first = Array.isArray(candidates) && candidates.length > 0 ? candidates[0] : null;
  const body = first
    ? { status: "match", read_brand: first.brand ?? null, read_name: first.name ?? null,
        read_size: first.variant ?? null, matches: [{ product_id: first.id, confidence: 0.95 }] }
    : { status: "none", matches: [] };
  return new Response(JSON.stringify(body), {
    headers: { "Content-Type": "application/json" },
  });
});
```

- [ ] **Step 2: Commit**

```bash
git add supabase/functions/recognize-product/index.ts
git commit -m "feat(scan): stub recognize-product Edge Function (canned response)"
```

---

## Phase 1 checkpoint

- [ ] **Run the full suite and analyzer**

Run: `flutter test` and `flutter analyze`
Expected: all tests pass (incl. the 3 new scan test files); analyzer clean. The feature is present but invisible (flag off, no entry point yet).

---

# PHASE 2 — Capture, UI, real Edge Function (compiles; deploy/run is user-side)

## Task 7: Add image_picker + camera permission

**Files:**
- Modify: `pubspec.yaml`
- Modify: `android/app/src/main/AndroidManifest.xml`

- [ ] **Step 1: Add the dependency**

In `pubspec.yaml`, under `dependencies:` (alphabetical among the existing entries), add:

```yaml
  image_picker: ^1.1.2
```

- [ ] **Step 2: Install**

Run: `flutter pub get`
Expected: resolves successfully.

- [ ] **Step 3: Add Android camera permission**

In `android/app/src/main/AndroidManifest.xml`, alongside the existing
`<uses-permission android:name="android.permission.INTERNET"/>`, add:

```xml
    <uses-permission android:name="android.permission.CAMERA"/>
```

(iOS: `NSCameraUsageDescription` must be added to `ios/Runner/Info.plist` before an iOS build — note this in the run doc; not required for the Android/S22 test target.)

- [ ] **Step 4: Verify**

Run: `flutter analyze`
Expected: No issues found.

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock android/app/src/main/AndroidManifest.xml
git commit -m "chore(scan): add image_picker + Android camera permission"
```

---

## Task 8: Scan controller (capture → recognize → decide)

**Files:**
- Create: `lib/features/scan/presentation/scan_controller.dart`

Orchestration + I/O; verified by `flutter analyze`. Pure pieces it uses (parsing, decision, candidates) are already tested.

- [ ] **Step 1: Write the controller**

```dart
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../inventory/domain/product.dart';
import '../../inventory/presentation/inventory_controller.dart';
import '../data/vision_scan_repository.dart';
import '../domain/recognition_result.dart';
import '../domain/scan_candidates.dart';
import '../domain/scan_decision.dart';

/// The resolved outcome the scan screen renders: an action plus the concrete
/// products it maps to (already resolved from match ids to Product objects).
class ScanOutcome {
  const ScanOutcome({required this.action, required this.products});
  final ScanAction action;
  final List<Product> products;
}

/// Captures a photo, recognizes it against the shop's catalog, and resolves the
/// decision into concrete products. Returns null if the user cancels capture.
class ScanController {
  ScanController(this._ref);

  final Ref _ref;
  final ImagePicker _picker = ImagePicker();

  Future<ScanOutcome?> captureAndRecognize() async {
    // MEMBER C: camera capture. image_picker is the stub seam.
    final XFile? shot = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1024,
      imageQuality: 70,
    );
    if (shot == null) return null;
    final Uint8List bytes = await shot.readAsBytes();

    final products =
        _ref.read(productsStreamProvider).value ?? const <Product>[];
    final result = await _ref
        .read(visionScanRepositoryProvider)
        .recognize(imageBytes: bytes, candidates: buildCandidates(products));

    return result.when(
      success: (recognition) {
        final decision = decideScanAction(recognition);
        final byId = {for (final p in products) p.id: p};
        final resolved = [
          for (final m in decision.matches)
            if (byId[m.productId] != null) byId[m.productId]!,
        ];
        return ScanOutcome(action: decision.action, products: resolved);
      },
      failure: (f) => throw f,
    );
  }
}

final scanControllerProvider = Provider<ScanController>((ref) => ScanController(ref));
```

- [ ] **Step 2: Verify**

Run: `flutter analyze lib/features/scan/presentation/scan_controller.dart`
Expected: No issues found. (Confirm `productsStreamProvider` is exported from `inventory_controller.dart` — it is used the same way in `history_screen.dart`.)

- [ ] **Step 3: Commit**

```bash
git add lib/features/scan/presentation/scan_controller.dart
git commit -m "feat(scan): ScanController orchestrating capture->recognize->decide"
```

---

## Task 9: Shared product picker sheet

**Files:**
- Create: `lib/features/scan/presentation/product_picker_sheet.dart`

Used for both "Did you mean?" (pre-filtered matches) and manual pick (full catalog). Verified by `flutter analyze`.

- [ ] **Step 1: Write the picker**

```dart
import 'package:flutter/material.dart';

import '../../inventory/domain/product.dart';

/// Bottom sheet listing [products] with a name search; returns the chosen
/// product, or null if dismissed. Reused for the match chooser and manual pick.
Future<Product?> showProductPickerSheet(
  BuildContext context, {
  required List<Product> products,
  required String title,
}) {
  return showModalBottomSheet<Product>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (_) => _ProductPickerSheet(products: products, title: title),
  );
}

class _ProductPickerSheet extends StatefulWidget {
  const _ProductPickerSheet({required this.products, required this.title});

  final List<Product> products;
  final String title;

  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = _q.trim().toLowerCase();
    final list = q.isEmpty
        ? widget.products
        : widget.products
              .where((p) => p.name.toLowerCase().contains(q))
              .toList();
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            autofocus: false,
            onChanged: (v) => setState(() => _q = v),
            decoration: const InputDecoration(
              hintText: 'Search products',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: list.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final p = list[i];
                final subtitle = [
                  p.brand,
                  p.variant,
                ].where((s) => s != null && s.isNotEmpty).join(' · ');
                return ListTile(
                  title: Text(p.name),
                  subtitle: subtitle.isEmpty ? null : Text(subtitle),
                  onTap: () => Navigator.of(context).pop(p),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Verify**

Run: `flutter analyze lib/features/scan/presentation/product_picker_sheet.dart`
Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add lib/features/scan/presentation/product_picker_sheet.dart
git commit -m "feat(scan): shared searchable product picker sheet"
```

---

## Task 10: Scan screen (routing) + route + flag-gated entry

**Files:**
- Create: `lib/features/scan/presentation/scan_screen.dart`
- Modify: `lib/core/router/app_router.dart` (add `/scan` route)
- Modify: `lib/features/inventory/presentation/inventory_list_screen.dart` (flag-gated Scan button)

- [ ] **Step 1: Write the scan screen**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/failure.dart';
import '../../inventory/domain/product.dart';
import '../../transactions/presentation/transaction_confirmation_sheet.dart';
import '../domain/scan_decision.dart';
import 'product_picker_sheet.dart';
import 'scan_controller.dart';

/// Drives the scan flow: opens the camera immediately, recognizes, then routes
/// to the sell sheet / chooser / manual pick. All sales still go through the
/// existing confirmation sheet (never auto-committed).
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final outcome = await ref.read(scanControllerProvider).captureAndRecognize();
      if (!mounted) return;
      if (outcome == null) {
        context.pop(); // user cancelled the camera
        return;
      }
      await _route(outcome);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is Failure ? e.message : 'Scan failed. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _route(ScanOutcome outcome) async {
    switch (outcome.action) {
      case ScanAction.autoSell:
        await _sell(outcome.products.first);
      case ScanAction.chooseFromMatches:
        final picked = await showProductPickerSheet(
          context,
          products: outcome.products,
          title: 'Did you mean?',
        );
        if (picked != null) await _sell(picked);
        if (mounted) context.pop();
      case ScanAction.noMatch:
        await _noMatch();
    }
  }

  Future<void> _sell(Product product) async {
    await showSaleConfirmationSheet(context, product: product, source: 'image');
    if (mounted) context.pop();
  }

  Future<void> _noMatch() async {
    // Manual fallback pulls the full catalog from the inventory stream.
    final all = ref.read(_allProductsForPicker);
    final picked = await showProductPickerSheet(
      context,
      products: all,
      title: 'No match — pick the product',
    );
    if (picked != null) {
      await _sell(picked);
    } else if (mounted) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan product')),
      body: Center(
        child: _error != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _run, child: const Text('Retry')),
                ],
              )
            : _busy
            ? const CircularProgressIndicator()
            : const SizedBox.shrink(),
      ),
    );
  }
}
```

Then add this provider at the bottom of the same file (reads the inventory stream for the manual picker):

```dart
import '../../inventory/presentation/inventory_controller.dart';

final _allProductsForPicker = Provider<List<Product>>(
  (ref) => ref.watch(productsStreamProvider).value ?? const <Product>[],
);
```

(Place the two extra imports — `inventory_controller.dart` — with the other imports at the top; the provider declaration goes after the class.)

- [ ] **Step 2: Add the `/scan` route**

In `lib/core/router/app_router.dart`, add an import at the top:

```dart
import '../../features/scan/presentation/scan_screen.dart';
```

and add this `GoRoute` alongside the other top-level routes (e.g. near `/inventory/new`):

```dart
      GoRoute(
        path: '/scan',
        builder: (context, state) => const ScanScreen(),
      ),
```

- [ ] **Step 3: Add the flag-gated entry button**

In `lib/features/inventory/presentation/inventory_list_screen.dart`, add imports:

```dart
import 'package:go_router/go_router.dart';
import '../../../core/config/feature_flags.dart';
```

Find the header row that holds the existing Add button (the `IconButton.filled(... '/inventory/new' ...)` added earlier) and insert, immediately before it:

```dart
                  if (FeatureFlags.visionScanEnabled) ...[
                    IconButton.filled(
                      onPressed: () => context.push('/scan'),
                      icon: const Icon(Icons.qr_code_scanner),
                      tooltip: 'Scan product',
                    ),
                    const SizedBox(width: 8),
                  ],
```

(If `go_router`'s `context.push` is already imported in this file, don't duplicate the import.)

- [ ] **Step 4: Verify**

Run: `flutter analyze`
Expected: No issues found. Fix any unused-import or ordering warnings the analyzer flags.

- [ ] **Step 5: Commit**

```bash
git add lib/features/scan/presentation/scan_screen.dart lib/core/router/app_router.dart lib/features/inventory/presentation/inventory_list_screen.dart
git commit -m "feat(scan): scan screen, /scan route, flag-gated entry button"
```

---

## Task 11: Real Edge Function (Gemini + OpenAI adapters)

**Files:**
- Modify: `supabase/functions/recognize-product/index.ts` (replace the stub)

Not compiled by Flutter. Reviewed for correctness; exercised at deploy time. **MEMBER B** owns the prompt/model choice — this is the working seam.

- [ ] **Step 1: Replace the stub with the real function**

```ts
// Supabase Edge Function: recognize-product
// Given an item photo + the shop's product candidates, asks a vision LLM which
// candidate is in the photo and returns a normalized JSON result.
// Provider is chosen server-side via VISION_PROVIDER; keys stay in secrets.
// MEMBER B owns the prompt/model tuning.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

interface Candidate { id: string; name: string; brand?: string; variant?: string }

const PROVIDER = (Deno.env.get("VISION_PROVIDER") ?? "gemini").toLowerCase();
const GEMINI_KEY = Deno.env.get("GEMINI_API_KEY") ?? "";
const OPENAI_KEY = Deno.env.get("OPENAI_API_KEY") ?? "";
const GEMINI_MODEL = Deno.env.get("GEMINI_MODEL") ?? "gemini-2.5-flash";
const OPENAI_MODEL = Deno.env.get("OPENAI_MODEL") ?? "gpt-4o-mini";

const instruction = (candidates: Candidate[]) =>
  `You are identifying a retail product from a photo for a shop's point-of-sale.
Below is the shop's product list (JSON). Decide which listed product(s) appear in the image.
Match the brand/name/size you can read on the packaging to the candidates.
Return ONLY minified JSON of this exact shape:
{"status":"match|multiple|none","read_brand":string|null,"read_name":string|null,"read_size":string|null,"matches":[{"product_id":"<id from the list>","confidence":<0..1>}]}
Rank matches by confidence (highest first). If nothing matches, use status "none" and an empty matches array. Never invent an id that is not in the list.
Product list: ${JSON.stringify(candidates)}`;

function extractJson(text: string): Record<string, unknown> {
  const cleaned = text.trim().replace(/^```json/i, "").replace(/```$/, "").trim();
  const start = cleaned.indexOf("{");
  const end = cleaned.lastIndexOf("}");
  return JSON.parse(start >= 0 ? cleaned.slice(start, end + 1) : cleaned);
}

async function gemini(imageB64: string, candidates: Candidate[]) {
  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_KEY}`;
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{
        parts: [
          { text: instruction(candidates) },
          { inline_data: { mime_type: "image/jpeg", data: imageB64 } },
        ],
      }],
      generationConfig: { responseMimeType: "application/json", temperature: 0 },
    }),
  });
  const json = await res.json();
  const text = json?.candidates?.[0]?.content?.parts?.[0]?.text ?? "{}";
  return extractJson(text);
}

async function openai(imageB64: string, candidates: Candidate[]) {
  const res = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${OPENAI_KEY}`,
    },
    body: JSON.stringify({
      model: OPENAI_MODEL,
      temperature: 0,
      response_format: { type: "json_object" },
      messages: [{
        role: "user",
        content: [
          { type: "text", text: instruction(candidates) },
          { type: "image_url", image_url: { url: `data:image/jpeg;base64,${imageB64}` } },
        ],
      }],
    }),
  });
  const json = await res.json();
  return extractJson(json?.choices?.[0]?.message?.content ?? "{}");
}

function normalize(raw: Record<string, unknown>, candidates: Candidate[]) {
  const ids = new Set(candidates.map((c) => c.id));
  const matches = Array.isArray(raw.matches) ? raw.matches : [];
  const clean = matches
    .filter((m: Record<string, unknown>) => ids.has(m?.product_id as string))
    .map((m: Record<string, unknown>) => ({
      product_id: m.product_id,
      confidence: Math.max(0, Math.min(1, Number(m.confidence) || 0)),
    }));
  const status = clean.length === 0 ? "none" : (raw.status as string) ?? "match";
  return {
    status,
    read_brand: raw.read_brand ?? null,
    read_name: raw.read_name ?? null,
    read_size: raw.read_size ?? null,
    matches: clean,
  };
}

Deno.serve(async (req) => {
  try {
    const { image_base64, candidates } = await req.json();
    if (!image_base64 || !Array.isArray(candidates)) {
      return new Response(JSON.stringify({ status: "none", matches: [] }), {
        headers: { "Content-Type": "application/json" },
      });
    }
    const raw = PROVIDER === "openai"
      ? await openai(image_base64, candidates)
      : await gemini(image_base64, candidates);
    return new Response(JSON.stringify(normalize(raw, candidates)), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (_e) {
    return new Response(JSON.stringify({ status: "none", matches: [] }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }
});
```

- [ ] **Step 2: Commit**

```bash
git add supabase/functions/recognize-product/index.ts
git commit -m "feat(scan): real recognize-product Edge Function (Gemini+OpenAI, provider switch)"
```

---

## Task 12: Final verification + run doc

**Files:**
- Create: `supabase/functions/recognize-product/README.md`

- [ ] **Step 1: Analyze + test the whole project**

Run: `flutter analyze` then `flutter test`
Expected: analyzer clean; all tests pass (scan parse/decision/candidates + existing suite). The app builds with the feature invisible unless `--dart-define=VISION_SCAN_ENABLED=true`.

- [ ] **Step 2: Write the deploy/run instructions**

```markdown
# recognize-product — deploy & run

## One-time setup
1. Install the Supabase CLI and log in: `supabase login`
2. Link the project: `supabase link --project-ref <your-ref>`
3. Set secrets (at least one key; pick a provider):
   ```
   supabase secrets set GEMINI_API_KEY=xxxxx
   supabase secrets set OPENAI_API_KEY=xxxxx      # optional
   supabase secrets set VISION_PROVIDER=gemini    # or openai
   ```
4. Deploy: `supabase functions deploy recognize-product`

## Run the app with scanning enabled
```
flutter run \
  --dart-define=SUPABASE_URL=... \
  --dart-define=SUPABASE_ANON_KEY=... \
  --dart-define=VISION_SCAN_ENABLED=true
```

## Switch to Gemini-only later
`supabase secrets set VISION_PROVIDER=gemini` (and optionally delete the OpenAI
adapter from index.ts).

## Rollback the whole feature
`git checkout checkpoint-pre-vision-scan`
```

- [ ] **Step 3: Manual smoke test (device, after deploy)**

With the function deployed and the flag on, on the inventory screen tap the new
Scan button:
- a labeled product that exists in inventory → sell sheet opens on it,
- two look-alikes → "Did you mean?" chooser,
- a loose/unlabeled item → "No match — pick the product" manual picker.

- [ ] **Step 4: Commit**

```bash
git add supabase/functions/recognize-product/README.md
git commit -m "docs(scan): deploy/run instructions for recognize-product"
```

---

## Self-Review Notes

- **Spec coverage:** capture (Task 8) · closed-set match via Edge Function (Tasks 5,6,11) · dual provider + switch (Task 11) · keys server-side (Task 11 + README) · decision/threshold UX auto/choose/none (Tasks 3,10) · manual fallback for loose items (Tasks 9,10) · reuse of existing sell sheet unchanged (Task 10) · feature flag + additive + rollback (Tasks 1,10 + README) · tests (Tasks 2,3,4,12). All spec sections mapped.
- **Type consistency:** `RecognitionResult`/`ProductMatch` (Task 2) are consumed unchanged by `decideScanAction` (Task 3), `ScanController` (Task 8), and parsed from the flat wire shape the Edge Function emits (Tasks 6,11). `ScanAction` values (autoSell/chooseFromMatches/noMatch) match between Task 3 and Task 10. `buildCandidates` output shape (Task 4) equals what the Edge Function reads (Task 11) and what `VisionScanRepository.recognize` sends (Task 5,8).
- **Deploy-dependent:** Phase 2 UI compiles and tests pass without deployment; live scanning requires the user's Supabase CLI deploy + secrets (Task 12 README) — called out as a prerequisite, not a code gap.
