# Fast Scan Session Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the serial camera→wait→sheet scan loop with a session: a live viewfinder that never closes, recognition running in the background, and one review tray that commits the whole basket at once.

**Architecture:** Capture is decoupled from recognition. `ScanSessionController` owns a list of `ScanItem` chips; each shutter press appends a `recognizing` chip and queues a recognition (max 3 in flight). Chips resolve out of order and **merge by product**, so three shutter presses on the same bottle become one chip at ×3. Nothing reaches the cart until "Add", which funnels through the existing `CartController.addOrIncrement`.

**Tech Stack:** Flutter, Riverpod 3 (`Notifier`), `camera` package (new), Supabase Edge Functions (Deno/TypeScript), `flutter gen-l10n`.

**Spec:** [2026-08-10-fast-scan-session-design.md](../specs/2026-08-10-fast-scan-session-design.md)

## Global Constraints

- Branch `feat/fast-scan`, already created, stacked on `feat/cart-discount`.
- **Never run `dart format .` repo-wide** — it reflows ~50 committed files. Format only paths you touched, and only if that file was already formatted at HEAD.
- `flutter analyze` clean and the full `flutter test` suite green before every commit.
- **Never hardcode Supabase keys.** Edge Function source is committed here; the user deploys.
- Cart commits only via `record_sale_cart` at checkout. This plan never records a sale — it only stages cart lines.
- Quantities clamp through the existing `clampCartQuantity` / `remainingStockForLines`; never write bespoke stock maths.
- Every new user-facing string needs a key in **both** `lib/l10n/app_en.arb` and `lib/l10n/app_bn.arb` — `test/l10n_parity_test.dart` fails the build otherwise.
- Do not leave stray files in the repo root (no `test_output.txt`).
- `ProductUnit` values are `pcs | kg | g | litre | ml`. `Product.unitType.allowsDecimal` decides whether fractional quantities are legal.

---

## File Structure

| File | Responsibility |
|---|---|
| `lib/features/scan/domain/scan_candidates.dart` | **Modify** — emit indexed candidates + resolve the echoed identifier back to a product id |
| `lib/features/scan/domain/scan_item.dart` | **Create** — one tray chip: status, product, quantity, held frame |
| `lib/features/scan/data/scan_camera.dart` | **Create** — camera interface + fake, so session logic is testable |
| `lib/features/scan/data/real_scan_camera.dart` | **Create** — `camera` package wrapper, lifecycle, permission |
| `lib/features/scan/presentation/scan_session_controller.dart` | **Create** — the session: queue, merge, clamp, add-all |
| `lib/features/scan/presentation/scan_session_screen.dart` | **Create** — viewfinder + tray + Add bar |
| `lib/features/scan/presentation/scan_tray.dart` | **Create** — the chip strip |
| `lib/features/scan/presentation/top_sellers_strip.dart` | **Create** — one-tap best sellers row |
| `lib/features/scan/presentation/scan_screen.dart` | **Delete** at Task 5 — replaced |
| `supabase/functions/recognize-product/index.ts` | **Modify** — accept `id` or `i` |
| `supabase/functions/parse-sale/index.ts` | **Modify (Task 8 only)** — accept `id` or `i` |

---

## Task 1: Indexed candidate payload + Edge Function dual-shape

Cuts ~40% of tokens per scan by dropping the UUID the model never needs to understand, only echo. Ships the Edge Function's backward-compatible half in the same task so the two are reviewed together.

**Files:**
- Modify: `lib/features/scan/domain/scan_candidates.dart`
- Modify: `lib/features/scan/presentation/scan_controller.dart:60-80`
- Modify: `supabase/functions/recognize-product/index.ts:13`, `:146`
- Test: `test/scan_candidates_test.dart`

**Interfaces:**
- Consumes: `Product` (`id`, `name`, `brand`, `variant`, `unit`).
- Produces: `class CandidatePayload { List<Map<String, dynamic>> candidates; String? resolve(String returned); }` and `CandidatePayload buildCandidatePayload(List<Product>, {bool includeUnit = false, Map<String, double>? recentUnits})`. Tasks 3 and 8 depend on both names.

- [ ] **Step 1: Write the failing test**

Replace the whole body of `test/scan_candidates_test.dart` (keep the `_p` helper at the top exactly as it is):

```dart
void main() {
  test('candidates carry a list index, never the uuid', () {
    final payload = buildCandidatePayload([
      _p('uuid-a', 'Pepsi 500ml', brand: 'Pepsi', variant: '500ml'),
      _p('uuid-b', 'Loose rice'),
    ]);
    expect(payload.candidates, [
      {'i': 0, 'name': 'Pepsi 500ml', 'brand': 'Pepsi', 'variant': '500ml'},
      {'i': 1, 'name': 'Loose rice'},
    ]);
    // The whole point: a 36-char uuid is ~20 tokens of noise per candidate.
    expect(payload.candidates.first.containsKey('id'), isFalse);
  });

  test('resolve maps the echoed index back to the real product id', () {
    final payload = buildCandidatePayload([
      _p('uuid-a', 'Pepsi'),
      _p('uuid-b', 'Rice'),
    ]);
    expect(payload.resolve('0'), 'uuid-a');
    expect(payload.resolve('1'), 'uuid-b');
  });

  test('an invented identifier resolves to null, never a wrong product', () {
    final payload = buildCandidatePayload([_p('uuid-a', 'Pepsi')]);
    expect(payload.resolve('7'), isNull, reason: 'out of range');
    expect(payload.resolve('-1'), isNull);
    expect(payload.resolve('uuid-a'), isNull, reason: 'not an index');
    expect(payload.resolve(''), isNull);
  });

  test('scan omits unit by default; voice opts in', () {
    final scan = buildCandidatePayload([
      _p('a', 'Milk', unit: ProductUnit.litre),
    ]).candidates.single;
    expect(scan.containsKey('unit'), isFalse);

    final voice = buildCandidatePayload([
      _p('a', 'Milk', unit: ProductUnit.litre),
    ], includeUnit: true).candidates.single;
    expect(voice['unit'], 'litre');
  });

  test('recent units are keyed by product id, not index', () {
    final c = buildCandidatePayload(
      [_p('uuid-a', 'Pepsi'), _p('uuid-b', 'Rice')],
      recentUnits: {'uuid-b': 12.4},
    ).candidates;
    expect(c[0].containsKey('recent'), isFalse);
    expect(c[1]['recent'], 12);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/scan_candidates_test.dart`
Expected: FAIL — `buildCandidatePayload` is not defined.

- [ ] **Step 3: Implement the payload**

Replace the whole of `lib/features/scan/domain/scan_candidates.dart`:

```dart
import '../../inventory/domain/product.dart';

/// The candidate list sent to a model, plus the mapping needed to turn the
/// identifier the model echoes back into a real product id.
///
/// Candidates are keyed by **list index**, not product uuid. The catalog is
/// re-sent inside the prompt on every single scan (see the Edge Function's
/// `instruction()`), so at ~100 products it is roughly 90% of the request --
/// and a 36-char uuid costs ~20 tokens per candidate while carrying no meaning
/// the model can use. It only has to echo an identifier back; a small integer
/// does that job for a fraction of the tokens.
class CandidatePayload {
  const CandidatePayload({
    required this.candidates,
    required List<String> productIds,
  }) : _productIds = productIds;

  final List<Map<String, dynamic>> candidates;
  final List<String> _productIds;

  /// Resolves the identifier a model returned back to the shop's product id.
  /// Null for anything the model invented -- out of range, negative, or not a
  /// number at all -- so a hallucinated id can never land on a real product.
  String? resolve(String returned) {
    final i = int.tryParse(returned);
    if (i == null || i < 0 || i >= _productIds.length) return null;
    return _productIds[i];
  }
}

/// Builds the compact candidate list. Only index/name are guaranteed;
/// brand/variant are included when present (they sharpen matching). Loose items
/// simply carry no brand/variant.
///
/// [includeUnit] is opt-in: the voice flow enables it because spoken sizes
/// ("1 litre") match far better when the model can see each product's unit.
///
/// [recentUnits] optionally supplies units-sold-recently **keyed by product
/// id** (see `recentUnitsSoldProvider`). Products with a positive count carry a
/// `recent` field the model can use to break a tie the speech left open, so the
/// payload does not grow for a shop that has just started.
CandidatePayload buildCandidatePayload(
  List<Product> products, {
  bool includeUnit = false,
  Map<String, double>? recentUnits,
}) {
  final candidates = <Map<String, dynamic>>[];
  final productIds = <String>[];
  for (var i = 0; i < products.length; i++) {
    final p = products[i];
    candidates.add({
      'i': i,
      'name': p.name,
      if (p.brand != null && p.brand!.isNotEmpty) 'brand': p.brand,
      if (p.variant != null && p.variant!.isNotEmpty) 'variant': p.variant,
      if (includeUnit) 'unit': p.unit.name,
      // Rounded: the model only needs the order of magnitude to rank, and whole
      // numbers keep the prompt compact. Tested on the rounded value so a
      // fractional trickle (0.4 kg in a month) never emits a bare `recent: 0`
      // that reads as a real signal.
      if ((recentUnits?[p.id] ?? 0).round() > 0)
        'recent': recentUnits![p.id]!.round(),
    });
    productIds.add(p.id);
  }
  return CandidatePayload(candidates: candidates, productIds: productIds);
}
```

- [ ] **Step 4: Point the scan controller at it**

In `lib/features/scan/presentation/scan_controller.dart`, replace the body of `captureAndRecognize` from the `final products =` line to the closing `);` of the `return result.when(...)`:

```dart
    final products =
        _ref.read(productsStreamProvider).value ?? const <Product>[];
    final payload = buildCandidatePayload(products);
    final result = await _ref
        .read(visionScanRepositoryProvider)
        .recognize(imageBytes: bytes, candidates: payload.candidates);

    return result.when(
      success: (recognition) {
        final decision = decideScanAction(recognition);
        final byId = {for (final p in products) p.id: p};
        final resolved = <Product>[
          for (final m in decision.matches)
            if (byId[payload.resolve(m.productId)] case final Product p) p,
        ];
        return ScanOutcome(
          action: decision.action,
          products: resolved,
          readBrand: recognition.readBrand,
          readName: recognition.readName,
          readSize: recognition.readSize,
        );
      },
      failure: (f) => throw f,
    );
```

- [ ] **Step 5: Teach the Edge Function both shapes**

In `supabase/functions/recognize-product/index.ts`, change the interface at line 13:

```ts
// `id` is the legacy shape (product uuid). `i` is the current one: a list index,
// because the catalog is re-sent in the prompt on every scan and a uuid costs
// ~20 tokens per candidate to carry no meaning. BOTH are accepted so this
// function can be deployed while an older app is still installed -- see the
// deploy-order note in supabase/README.md.
interface Candidate {
  id?: string;
  i?: number;
  name: string;
  brand?: string;
  variant?: string;
  unit?: string;
  recent?: number;
}
```

Then replace line 146 inside `normalize`:

```ts
  const ids = new Set(
    candidates.map((c) => c.id ?? String(c.i)).filter((k) => k !== "undefined"),
  );
```

The function echoes `product_id` through untouched — whichever identifier it was given. The app resolves it.

- [ ] **Step 6: Run the tests**

Run: `flutter test test/scan_candidates_test.dart test/scan_decision_test.dart test/scan_read_label_test.dart && flutter analyze`
Expected: PASS, analyze clean.

- [ ] **Step 7: Run the full suite**

Run: `flutter test`
Expected: all green. `voice_controller.dart` still calls the old `buildCandidates`, so **if it fails to compile, stop** — Task 8 migrates voice; for now add a thin shim only if needed:

```dart
// Kept until Task 8 migrates the voice flow off uuid candidates.
List<Map<String, dynamic>> buildCandidates(
  List<Product> products, {
  bool includeUnit = false,
  Map<String, double>? recentUnits,
}) => [
  for (final p in products)
    {
      'id': p.id,
      'name': p.name,
      if (p.brand != null && p.brand!.isNotEmpty) 'brand': p.brand,
      if (p.variant != null && p.variant!.isNotEmpty) 'variant': p.variant,
      if (includeUnit) 'unit': p.unit.name,
      if ((recentUnits?[p.id] ?? 0).round() > 0)
        'recent': recentUnits![p.id]!.round(),
    },
];
```

- [ ] **Step 8: Commit**

```bash
git add lib/features/scan/domain/scan_candidates.dart lib/features/scan/presentation/scan_controller.dart supabase/functions/recognize-product/index.ts test/scan_candidates_test.dart
git commit -m "perf(scan): send candidates by index, not uuid

The catalog is JSON.stringified into the prompt on every scan, so at
~100 products it is ~90% of the request -- the photo is nearly free by
comparison. A 36-char uuid is ~20 tokens per candidate carrying nothing
the model understands; it only echoes an identifier back. A list index
does that for a fraction of the cost.

recognize-product accepts either shape, so it is safe to deploy while an
older app is still installed. Deploy the function FIRST: the reverse
mismatch filters every match out and degrades silently to \"no match\".

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 2: Camera interface + fake

Real cameras do not exist in `flutter test`. Everything risky in this feature — queueing, merging, clamping — must sit behind this seam or it ships untested.

**Files:**
- Create: `lib/features/scan/data/scan_camera.dart`
- Test: `test/scan_camera_fake_test.dart`

**Interfaces:**
- Produces: `abstract interface class ScanCamera { Future<void> initialize(); Widget buildPreview(BuildContext); Future<Uint8List> capture(); Future<void> dispose(); }`, `class CameraPermissionDenied implements Exception {}`, `class FakeScanCamera implements ScanCamera`, and `final scanCameraProvider = Provider<ScanCamera>(...)`. Tasks 3, 4 and 5 depend on all four.

- [ ] **Step 1: Write the failing test**

Create `test/scan_camera_fake_test.dart`:

```dart
import 'dart:typed_data';

import 'package:ai_shopkeeper/features/scan/data/scan_camera.dart';
import 'package:flutter_test/flutter_test.dart';

/// The fake is the whole reason the session logic is testable, so its own
/// contract is pinned: capture must hand back distinct, non-empty bytes so a
/// test can tell one frame from another.
void main() {
  test('capture yields distinct non-empty frames', () async {
    final cam = FakeScanCamera();
    await cam.initialize();
    final a = await cam.capture();
    final b = await cam.capture();
    expect(a, isA<Uint8List>());
    expect(a.isNotEmpty, isTrue);
    expect(a, isNot(equals(b)));
    expect(cam.captureCount, 2);
    await cam.dispose();
  });

  test('capture before initialize throws rather than returning junk', () {
    expect(FakeScanCamera().capture(), throwsStateError);
  });

  test('a denied camera surfaces CameraPermissionDenied', () {
    expect(
      FakeScanCamera(permissionGranted: false).initialize(),
      throwsA(isA<CameraPermissionDenied>()),
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/scan_camera_fake_test.dart`
Expected: FAIL — `scan_camera.dart` does not exist.

- [ ] **Step 3: Implement the interface and fake**

Create `lib/features/scan/data/scan_camera.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Thrown when the user refuses camera access. Distinct from a generic failure
/// because the recovery is different: no amount of retrying helps, the user has
/// to change a system setting.
class CameraPermissionDenied implements Exception {
  const CameraPermissionDenied();
  @override
  String toString() => 'CameraPermissionDenied';
}

/// The scan session's view of a camera.
///
/// Deliberately narrow, and deliberately includes [buildPreview] even though
/// that mixes a widget into a `data/` type: a real camera preview is a platform
/// texture only the plugin can construct. Paying that small layering cost buys
/// a fake, and the fake is what makes the session controller, the merge rules
/// and the whole tray testable -- none of which a real camera permits inside
/// `flutter test`.
abstract interface class ScanCamera {
  /// Throws [CameraPermissionDenied] if the user refuses access.
  Future<void> initialize();

  Widget buildPreview(BuildContext context);

  /// JPEG bytes of the current frame. Throws [StateError] before [initialize].
  Future<Uint8List> capture();

  Future<void> dispose();
}

/// In-memory camera for tests. Each [capture] returns different bytes so a test
/// can assert which frame a chip is holding.
class FakeScanCamera implements ScanCamera {
  FakeScanCamera({this.permissionGranted = true});

  final bool permissionGranted;
  bool _ready = false;
  int captureCount = 0;
  bool disposed = false;

  @override
  Future<void> initialize() async {
    if (!permissionGranted) throw const CameraPermissionDenied();
    _ready = true;
  }

  @override
  Widget buildPreview(BuildContext context) =>
      const ColoredBox(color: Color(0xFF202020));

  @override
  Future<Uint8List> capture() async {
    if (!_ready) throw StateError('capture() before initialize()');
    captureCount++;
    return Uint8List.fromList([captureCount, 0, 0, 0]);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    _ready = false;
  }
}

/// Overridden in tests with a [FakeScanCamera]; Task 4 supplies the real one.
final scanCameraProvider = Provider<ScanCamera>(
  (ref) => throw UnimplementedError('scanCameraProvider must be overridden'),
);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/scan_camera_fake_test.dart && flutter analyze`
Expected: PASS, analyze clean.

- [ ] **Step 5: Commit**

```bash
git add lib/features/scan/data/scan_camera.dart test/scan_camera_fake_test.dart
git commit -m "feat(scan): camera behind a fakeable interface

Real cameras do not exist in flutter test. Putting the camera behind a
four-method seam means the queueing, merging and clamping rules of the
scan session are all testable, leaving only the thin plugin wrapper
needing a device.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 3: The scan session controller

The heart of the feature. Pure logic, no widgets, fully tested.

**Files:**
- Create: `lib/features/scan/domain/scan_item.dart`
- Create: `lib/features/scan/presentation/scan_session_controller.dart`
- Test: `test/scan_session_controller_test.dart`

**Interfaces:**
- Consumes: `CandidatePayload`/`buildCandidatePayload` (Task 1), `ScanCamera`/`scanCameraProvider` (Task 2), `visionScanRepositoryProvider`, `productsStreamProvider`, `cartControllerProvider`, `decideScanAction`, `clampCartQuantity`, `stepForUnit`, `remainingStockForLines`.
- Produces: `enum ScanItemStatus`, `class ScanItem`, `class ScanSessionController extends Notifier<List<ScanItem>>` with `Future<void> capture()`, `void choose(String itemId, Product)`, `void setQuantity(String itemId, double)`, `void remove(String itemId)`, `Future<void> retry(String itemId)`, `void addAllToCart()`, `int get pendingCount`, and `final scanSessionProvider`. Tasks 5 and 6 depend on all of these.

- [ ] **Step 1: Write `ScanItem`**

Create `lib/features/scan/domain/scan_item.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../inventory/domain/product.dart';

/// Where one tray chip is in its life.
enum ScanItemStatus {
  /// Queued or in flight. The camera does not wait for this.
  recognizing,

  /// One product, confidently. Counts toward "Add N items".
  resolved,

  /// Several plausible products; the shopkeeper taps to pick.
  ambiguous,

  /// Recognized nothing in the catalog; tap to pick manually.
  unmatched,

  /// The call failed (offline, 502). The frame is held so retry needs no
  /// re-shoot.
  failed,
}

/// One chip in the review tray.
@immutable
class ScanItem {
  const ScanItem({
    required this.id,
    required this.status,
    this.product,
    this.choices = const <Product>[],
    this.readLabel,
    this.quantity = 0,
    this.frame,
  });

  /// Local, stable key. Never a product id -- two chips can hold the same
  /// product briefly, before the merge in [ScanSessionController] folds them.
  final String id;
  final ScanItemStatus status;
  final Product? product;
  final List<Product> choices;

  /// What the model reported reading off the packaging, e.g. "Pepsi · 1L".
  final String? readLabel;
  final double quantity;

  /// Held only while the chip may still need re-sending; dropped on success so
  /// a long session does not accumulate JPEGs.
  final Uint8List? frame;

  bool get isPending => status == ScanItemStatus.recognizing;
  bool get isAddable => status == ScanItemStatus.resolved && quantity > 0;

  ScanItem copyWith({
    ScanItemStatus? status,
    Product? product,
    List<Product>? choices,
    String? readLabel,
    double? quantity,
    bool clearFrame = false,
  }) => ScanItem(
    id: id,
    status: status ?? this.status,
    product: product ?? this.product,
    choices: choices ?? this.choices,
    readLabel: readLabel ?? this.readLabel,
    quantity: quantity ?? this.quantity,
    frame: clearFrame ? null : frame,
  );
}
```

- [ ] **Step 2: Write the failing tests**

Create `test/scan_session_controller_test.dart`:

```dart
import 'dart:typed_data';

import 'package:ai_shopkeeper/core/error/failure.dart';
import 'package:ai_shopkeeper/core/error/result.dart';
import 'package:ai_shopkeeper/features/cart/presentation/cart_controller.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/inventory/presentation/inventory_controller.dart';
import 'package:ai_shopkeeper/features/scan/data/scan_camera.dart';
import 'package:ai_shopkeeper/features/scan/data/vision_scan_repository.dart';
import 'package:ai_shopkeeper/features/scan/domain/recognition_result.dart';
import 'package:ai_shopkeeper/features/scan/domain/scan_item.dart';
import 'package:ai_shopkeeper/features/scan/presentation/scan_session_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _pepsi = Product(
  id: 'p-pepsi', shopId: 's1', name: 'Pepsi', sellingPrice: 50,
  quantity: 10, unit: ProductUnit.pcs,
);
const _rice = Product(
  id: 'p-rice', shopId: 's1', name: 'Rice', sellingPrice: 80,
  quantity: 20, unit: ProductUnit.kg, unitType: UnitType.weight,
);
const _catalog = [_pepsi, _rice];

/// Recognition the test drives by hand: each call parks on a completer so the
/// test controls exactly when (and in what order) answers land.
class _ScriptedRepo implements VisionScanRepository {
  final pending = <Completer<Result<RecognitionResult>>>[];
  int calls = 0;

  @override
  Future<Result<RecognitionResult>> recognize({
    required Uint8List imageBytes,
    required List<Map<String, dynamic>> candidates,
  }) {
    calls++;
    final c = Completer<Result<RecognitionResult>>();
    pending.add(c);
    return c.future;
  }
}

Result<RecognitionResult> _match(int index, {double confidence = 0.95}) =>
    Result.success(RecognitionResult(
      status: RecognitionStatus.match,
      matches: [ProductMatch(productId: '$index', confidence: confidence)],
      readName: 'read-$index',
    ));

ProviderContainer _container(_ScriptedRepo repo, FakeScanCamera cam) {
  final c = ProviderContainer(overrides: [
    visionScanRepositoryProvider.overrideWithValue(repo),
    scanCameraProvider.overrideWithValue(cam),
    productsStreamProvider.overrideWith((ref) => Stream.value(_catalog)),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  late _ScriptedRepo repo;
  late FakeScanCamera cam;
  late ProviderContainer c;

  setUp(() async {
    repo = _ScriptedRepo();
    cam = FakeScanCamera();
    await cam.initialize();
    c = _container(repo, cam);
    await c.read(productsStreamProvider.future);
  });

  ScanSessionController ctl() => c.read(scanSessionProvider.notifier);
  List<ScanItem> items() => c.read(scanSessionProvider);

  test('a capture appends a pending chip without waiting for the answer', () async {
    await ctl().capture();
    expect(items().single.status, ScanItemStatus.recognizing);
    expect(repo.calls, 1, reason: 'recognition started, but capture returned');
  });

  test('three captures of the same product become ONE chip at x3', () async {
    await ctl().capture();
    await ctl().capture();
    await ctl().capture();
    for (final p in repo.pending) {
      p.complete(_match(0)); // index 0 == Pepsi
    }
    await Future<void>.delayed(Duration.zero);

    expect(items().length, 1, reason: 'merged on resolve, not three chips');
    expect(items().single.product?.id, 'p-pepsi');
    expect(items().single.quantity, 3);
  });

  test('answers landing out of order still merge correctly', () async {
    await ctl().capture();
    await ctl().capture();
    repo.pending[1].complete(_match(0));
    await Future<void>.delayed(Duration.zero);
    repo.pending[0].complete(_match(0));
    await Future<void>.delayed(Duration.zero);

    expect(items().length, 1);
    expect(items().single.quantity, 2);
  });

  test('never more than 3 recognitions in flight', () async {
    for (var i = 0; i < 10; i++) {
      await ctl().capture();
    }
    expect(repo.calls, 3, reason: 'the other 7 are queued');
    expect(items().length, 10, reason: 'every chip is visible immediately');

    repo.pending[0].complete(_match(0));
    await Future<void>.delayed(Duration.zero);
    expect(repo.calls, 4, reason: 'finishing one dispatches the next');
  });

  test('quantity clamps to remaining stock, honouring what is already in the cart', () async {
    c.read(cartControllerProvider.notifier).addOrIncrement(_pepsi, 9);
    await ctl().capture();
    repo.pending[0].complete(_match(0));
    await Future<void>.delayed(Duration.zero);

    ctl().setQuantity(items().single.id, 5);
    expect(items().single.quantity, 1, reason: '10 stock - 9 staged = 1');
  });

  test('a whole-unit product cannot be set to a fraction', () async {
    await ctl().capture();
    repo.pending[0].complete(_match(0));
    await Future<void>.delayed(Duration.zero);
    ctl().setQuantity(items().single.id, 2.7);
    expect(items().single.quantity, 2, reason: 'pcs floors');
  });

  test('a failure marks only its own chip and keeps the frame for retry', () async {
    await ctl().capture();
    await ctl().capture();
    repo.pending[0].complete(
      const Result.failure(NetworkFailure('offline')),
    );
    repo.pending[1].complete(_match(0));
    await Future<void>.delayed(Duration.zero);

    final failed = items().firstWhere((i) => i.status == ScanItemStatus.failed);
    expect(failed.frame, isNotNull, reason: 'retry must not need a re-shoot');
    expect(
      items().any((i) => i.status == ScanItemStatus.resolved),
      isTrue,
      reason: 'one bad chip must never kill the session',
    );

    await ctl().retry(failed.id);
    expect(repo.calls, 3, reason: 'resent the held frame');
  });

  test('a resolved chip drops its frame', () async {
    await ctl().capture();
    repo.pending[0].complete(_match(0));
    await Future<void>.delayed(Duration.zero);
    expect(items().single.frame, isNull);
  });

  test('an invented index resolves to nothing, not a wrong product', () async {
    await ctl().capture();
    repo.pending[0].complete(_match(99));
    await Future<void>.delayed(Duration.zero);
    expect(items().single.status, ScanItemStatus.unmatched);
    expect(items().single.product, isNull);
  });

  test('choosing resolves an ambiguous chip and merges it', () async {
    await ctl().capture();
    repo.pending[0].complete(Result.success(const RecognitionResult(
      status: RecognitionStatus.multiple,
      matches: [
        ProductMatch(productId: '0', confidence: 0.6),
        ProductMatch(productId: '1', confidence: 0.55),
      ],
    )));
    await Future<void>.delayed(Duration.zero);
    expect(items().single.status, ScanItemStatus.ambiguous);
    expect(items().single.choices.length, 2);

    ctl().choose(items().single.id, _rice);
    expect(items().single.status, ScanItemStatus.resolved);
    expect(items().single.product?.id, 'p-rice');
    expect(items().single.quantity, 0.5, reason: 'kg steps by 0.5');
  });

  test('addAllToCart stages resolved chips and empties the tray', () async {
    await ctl().capture();
    await ctl().capture();
    repo.pending[0].complete(_match(0));
    repo.pending[1].complete(_match(1));
    await Future<void>.delayed(Duration.zero);

    ctl().addAllToCart();
    final cart = c.read(cartControllerProvider);
    expect(cart.length, 2);
    expect(cart.firstWhere((l) => l.product.id == 'p-pepsi').quantity, 1);
    expect(items(), isEmpty);
  });

  test('addAllToCart ignores chips that never resolved', () async {
    await ctl().capture();
    repo.pending[0].complete(_match(99)); // unmatched
    await Future<void>.delayed(Duration.zero);
    ctl().addAllToCart();
    expect(c.read(cartControllerProvider), isEmpty);
  });

  test('pendingCount tracks what is still in flight', () async {
    await ctl().capture();
    await ctl().capture();
    expect(ctl().pendingCount, 2);
    repo.pending[0].complete(_match(0));
    await Future<void>.delayed(Duration.zero);
    expect(ctl().pendingCount, 1);
  });
}
```

Add `import 'dart:async';` at the top of the test file.

- [ ] **Step 3: Run tests to verify they fail**

Run: `flutter test test/scan_session_controller_test.dart`
Expected: FAIL — `scan_session_controller.dart` does not exist.

- [ ] **Step 4: Implement the controller**

Create `lib/features/scan/presentation/scan_session_controller.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../cart/domain/cart_math.dart';
import '../../cart/presentation/cart_controller.dart';
import '../../inventory/domain/product.dart';
import '../../inventory/presentation/inventory_controller.dart';
import '../data/scan_camera.dart';
import '../data/vision_scan_repository.dart';
import '../domain/scan_candidates.dart';
import '../domain/scan_decision.dart';
import '../domain/scan_item.dart';

/// How many recognitions may be in flight at once.
///
/// A person cannot press a shutter much faster than once a second and each call
/// takes ~3s, so three-in-flight is roughly the natural steady state anyway:
/// higher buys no wall-clock improvement and invites rate-limit rejections,
/// lower re-serialises the very thing this session exists to parallelise.
const maxScanInFlight = 3;

/// The scan session: captures are instant, recognition happens behind them, and
/// nothing reaches the cart until [addAllToCart].
class ScanSessionController extends Notifier<List<ScanItem>> {
  @override
  List<ScanItem> build() => const <ScanItem>[];

  final _frames = <String, Uint8List>{};
  final _queue = <String>[];
  int _active = 0;
  int _seq = 0;

  int get pendingCount => state.where((i) => i.isPending).length;

  /// Grabs a frame and returns immediately. The recognition it starts resolves
  /// later, into whichever chip is still holding this id.
  Future<void> capture() async {
    final bytes = await ref.read(scanCameraProvider).capture();
    final id = 'chip-${_seq++}';
    _frames[id] = bytes;
    state = [
      ...state,
      ScanItem(id: id, status: ScanItemStatus.recognizing, frame: bytes),
    ];
    _queue.add(id);
    _pump();
  }

  /// Re-sends a failed chip's held frame -- no re-shoot required.
  Future<void> retry(String itemId) async {
    if (!_frames.containsKey(itemId)) return;
    _patch(itemId, (it) => it.copyWith(status: ScanItemStatus.recognizing));
    _queue.add(itemId);
    _pump();
  }

  void _pump() {
    while (_active < maxScanInFlight && _queue.isNotEmpty) {
      final id = _queue.removeAt(0);
      // A chip removed while queued must not consume a slot.
      if (!state.any((it) => it.id == id)) continue;
      _active++;
      _recognize(id);
    }
  }

  Future<void> _recognize(String id) async {
    final bytes = _frames[id];
    if (bytes == null) {
      _active--;
      return;
    }
    final products =
        ref.read(productsStreamProvider).value ?? const <Product>[];
    final payload = buildCandidatePayload(products);
    final result = await ref
        .read(visionScanRepositoryProvider)
        .recognize(imageBytes: bytes, candidates: payload.candidates);
    _active--;

    // The chip may have been removed while the call was in flight.
    if (state.any((it) => it.id == id)) {
      result.when(
        success: (recognition) {
          final byId = {for (final p in products) p.id: p};
          final decision = decideScanAction(recognition);
          final matched = <Product>[
            for (final m in decision.matches)
              if (byId[payload.resolve(m.productId)] case final Product p) p,
          ];
          final label = _readLabel(recognition.readBrand, recognition.readName,
              recognition.readSize);
          if (decision.action == ScanAction.autoSell && matched.isNotEmpty) {
            _resolve(id, matched.first, label);
          } else if (matched.length > 1) {
            _patch(
              id,
              (it) => it.copyWith(
                status: ScanItemStatus.ambiguous,
                choices: matched,
                readLabel: label,
              ),
            );
          } else if (matched.length == 1) {
            _resolve(id, matched.first, label);
          } else {
            _patch(
              id,
              (it) => it.copyWith(
                status: ScanItemStatus.unmatched,
                readLabel: label,
              ),
            );
          }
        },
        failure: (_) =>
            _patch(id, (it) => it.copyWith(status: ScanItemStatus.failed)),
      );
    }
    _pump();
  }

  /// Settles [id] onto [product], folding into an existing chip for the same
  /// product if there is one.
  ///
  /// The fold happens HERE, at resolve time, not at capture time: a pending chip
  /// has no product yet and answers arrive out of order, so capture cannot know
  /// what it is merging into. This is what makes "tap the shutter three times
  /// for three bottles" show as one chip at x3.
  void _resolve(String id, Product product, String? readLabel) {
    final step = stepForUnit(product.unit);
    final twin = state.indexWhere(
      (it) =>
          it.id != id &&
          it.status == ScanItemStatus.resolved &&
          it.product?.id == product.id,
    );
    _frames.remove(id);

    if (twin != -1) {
      final target = state[twin];
      final bumped = _clamp(product, target.quantity + step);
      final next = [...state];
      next[twin] = target.copyWith(quantity: bumped);
      state = next.where((it) => it.id != id).toList();
      return;
    }
    _patch(
      id,
      (it) => it.copyWith(
        status: ScanItemStatus.resolved,
        product: product,
        readLabel: readLabel,
        quantity: _clamp(product, step),
        choices: const <Product>[],
        clearFrame: true,
      ),
    );
  }

  /// Settles an ambiguous or unmatched chip onto a product the shopkeeper
  /// picked. Merges by the same rule as a recognition.
  void choose(String itemId, Product product) {
    final it = state.where((i) => i.id == itemId).firstOrNull;
    _resolve(itemId, product, it?.readLabel);
  }

  void setQuantity(String itemId, double quantity) {
    final it = state.where((i) => i.id == itemId).firstOrNull;
    final product = it?.product;
    if (product == null) return;
    final clamped = _clamp(product, quantity);
    if (clamped <= 0) return remove(itemId);
    _patch(itemId, (i) => i.copyWith(quantity: clamped));
  }

  void remove(String itemId) {
    _frames.remove(itemId);
    _queue.remove(itemId);
    state = state.where((i) => i.id != itemId).toList();
  }

  /// Stages every resolved chip into the cart and clears the tray. Chips that
  /// never resolved are dropped -- the screen confirms that with the user first.
  void addAllToCart() {
    final cart = ref.read(cartControllerProvider.notifier);
    for (final it in state) {
      if (it.isAddable) cart.addOrIncrement(it.product!, it.quantity);
    }
    state = const <ScanItem>[];
    _frames.clear();
    _queue.clear();
  }

  void clear() {
    state = const <ScanItem>[];
    _frames.clear();
    _queue.clear();
  }

  /// Clamps against stock the CART has not already claimed. The tray is not in
  /// the cart yet, and chips are merged one-per-product, so the cart's remaining
  /// figure is the correct ceiling.
  double _clamp(Product product, double value) => clampCartQuantity(
    value: value,
    remaining: ref.read(cartControllerProvider.notifier).remainingStockFor(product),
    allowsDecimal: product.unitType.allowsDecimal,
  );

  void _patch(String id, ScanItem Function(ScanItem) f) {
    state = [
      for (final it in state)
        if (it.id == id) f(it) else it,
    ];
  }

  static String? _readLabel(String? brand, String? name, String? size) {
    final parts = [brand, name, size]
        .where((s) => s != null && s.trim().isNotEmpty)
        .map((s) => s!.trim());
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

final scanSessionProvider =
    NotifierProvider<ScanSessionController, List<ScanItem>>(
      ScanSessionController.new,
    );
```

- [ ] **Step 5: Run the tests**

Run: `flutter test test/scan_session_controller_test.dart -r expanded`
Expected: PASS, all 13 tests.

- [ ] **Step 6: Full suite and analyze**

Run: `flutter test && flutter analyze`
Expected: green, clean.

- [ ] **Step 7: Commit**

```bash
git add lib/features/scan/domain/scan_item.dart lib/features/scan/presentation/scan_session_controller.dart test/scan_session_controller_test.dart
git commit -m "feat(scan): background recognition session with a review tray

Captures no longer wait for recognition. Each shutter press appends a
chip and queues a call (3 in flight); answers land out of order and fold
by product, so three presses on one bottle show as a single chip at x3.

The fold is at resolve time, not capture time -- a pending chip has no
product yet, so capture cannot know what it would merge into.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 4: The real camera

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/features/scan/data/real_scan_camera.dart`
- Modify: `lib/features/scan/data/scan_camera.dart` (point the provider at the real one)

**Interfaces:**
- Consumes: `ScanCamera`, `CameraPermissionDenied` (Task 2).
- Produces: `class RealScanCamera implements ScanCamera`, and `scanCameraProvider` now returning it.

- [ ] **Step 1: Add the dependency**

Run: `flutter pub add camera`
Then confirm `pubspec.yaml` gained `camera:` under `dependencies` and commit nothing yet.

`android/app/src/main/AndroidManifest.xml` **already declares `android.permission.CAMERA`** — no manifest change is needed. Verify with:

Run: `grep -c "permission.CAMERA" android/app/src/main/AndroidManifest.xml`
Expected: `1`

- [ ] **Step 2: Implement the wrapper**

Create `lib/features/scan/data/real_scan_camera.dart`:

```dart
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'scan_camera.dart';

/// The `camera` package behind the [ScanCamera] seam.
///
/// Resolution is deliberately [ResolutionPreset.medium] (640x480). The old
/// `image_picker` path shot at maxWidth 768 / quality 60 because a smaller
/// payload noticeably cut scan latency on slow shop connections, and `medium`
/// is the closest preset. This is the one number in the feature NOT backed by
/// evidence: if small print on packaging reads worse than it used to, move to
/// [ResolutionPreset.high] (1280x720) and accept the larger upload.
class RealScanCamera implements ScanCamera {
  CameraController? _controller;

  @override
  Future<void> initialize() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw const CameraPermissionDenied();
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      _controller = controller;
    } on CameraException catch (e) {
      // The plugin reports a refusal as an access-denied code rather than a
      // typed error; anything else is a real device fault worth rethrowing.
      if (e.code == 'CameraAccessDenied' ||
          e.code == 'CameraAccessDeniedWithoutPrompt' ||
          e.code == 'CameraAccessRestricted') {
        throw const CameraPermissionDenied();
      }
      rethrow;
    }
  }

  @override
  Widget buildPreview(BuildContext context) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }
    return CameraPreview(c);
  }

  @override
  Future<Uint8List> capture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      throw StateError('capture() before initialize()');
    }
    final shot = await c.takePicture();
    return shot.readAsBytes();
  }

  @override
  Future<void> dispose() async {
    final c = _controller;
    _controller = null;
    await c?.dispose();
  }
}
```

- [ ] **Step 3: Point the provider at it**

In `lib/features/scan/data/scan_camera.dart`, add `import 'real_scan_camera.dart';` and replace the provider:

```dart
/// Overridden with a [FakeScanCamera] in tests.
final scanCameraProvider = Provider<ScanCamera>((ref) => RealScanCamera());
```

- [ ] **Step 4: Verify nothing broke**

Run: `flutter test && flutter analyze`
Expected: green, clean. (No test constructs `RealScanCamera`; every test overrides the provider.)

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/features/scan/data/real_scan_camera.dart lib/features/scan/data/scan_camera.dart
git commit -m "feat(scan): real camera behind the ScanCamera seam

ResolutionPreset.medium (640x480) matches the old image_picker maxWidth
768/quality 60 most closely; that sizing existed because a smaller
payload cut scan latency on slow connections. Flagged in the spec as the
one number needing on-device confirmation -- small print is where 640
could read worse.

CAMERA permission was already declared in the manifest.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 5: The session screen

Replaces the serial loop. Adds every l10n key the screen needs.

**Files:**
- Create: `lib/features/scan/presentation/scan_tray.dart`
- Create: `lib/features/scan/presentation/scan_session_screen.dart`
- Delete: `lib/features/scan/presentation/scan_screen.dart`
- Modify: `lib/core/router/app_router.dart:23` (import) and `:209` (the `/scan` route builder)
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_bn.arb`
- Test: `test/widgets/scan_session_screen_test.dart`

**Interfaces:**
- Consumes: `scanSessionProvider`, `ScanSessionController` (Task 3), `scanCameraProvider`, `CameraPermissionDenied` (Task 2), `showProductPickerSheet`.
- Produces: `class ScanSessionScreen extends ConsumerStatefulWidget` (const constructor, no args).

- [ ] **Step 1: Add the l10n keys**

Add to `lib/l10n/app_en.arb` (beside the existing `scan_*` block around line 220):

```json
  "scan_recognizing": "Recognizing {count}…",
  "@scan_recognizing": { "placeholders": { "count": { "type": "int" } } },
  "scan_addItems": "Add {count} items",
  "@scan_addItems": { "placeholders": { "count": { "type": "int" } } },
  "scan_nothingYet": "Scan something to begin",
  "scan_tapToPick": "Tap to pick",
  "scan_notIdentified": "Not identified",
  "scan_topSellers": "Top sellers",
  "scan_outOfStock": "Out of stock",
  "scan_cameraDenied": "Camera access is needed to scan. Enable it in Settings.",
  "scan_openSettings": "Open settings",
  "scan_leaveTitle": "Leave without adding?",
  "scan_leaveBody": "{count} scanned items have not been added to the cart.",
  "@scan_leaveBody": { "placeholders": { "count": { "type": "int" } } },
  "scan_discardTitle": "Add the rest?",
  "scan_discardBody": "{count} could not be identified and will be discarded.",
  "@scan_discardBody": { "placeholders": { "count": { "type": "int" } } },
  "common_discard": "Discard",
  "common_add": "Add",
```

Add to `lib/l10n/app_bn.arb`:

```json
  "scan_recognizing": "{count}টি শনাক্ত করা হচ্ছে…",
  "scan_addItems": "{count}টি যোগ করুন",
  "scan_nothingYet": "শুরু করতে স্ক্যান করুন",
  "scan_tapToPick": "বেছে নিতে চাপ দিন",
  "scan_notIdentified": "শনাক্ত করা যায়নি",
  "scan_topSellers": "সেরা বিক্রি",
  "scan_outOfStock": "স্টক নেই",
  "scan_cameraDenied": "স্ক্যান করতে ক্যামেরার অনুমতি দরকার। সেটিংসে গিয়ে চালু করুন।",
  "scan_openSettings": "সেটিংস খুলুন",
  "scan_leaveTitle": "যোগ না করেই চলে যাবেন?",
  "scan_leaveBody": "{count}টি স্ক্যান করা পণ্য এখনও কার্টে যোগ করা হয়নি।",
  "scan_discardTitle": "বাকিগুলো যোগ করবেন?",
  "scan_discardBody": "{count}টি শনাক্ত করা যায়নি, সেগুলো বাদ পড়বে।",
  "common_discard": "বাতিল করুন",
  "common_add": "যোগ করুন",
```

Run: `flutter gen-l10n && flutter test test/l10n_parity_test.dart`
Expected: PASS.

- [ ] **Step 2: Write the failing widget test**

Create `test/widgets/scan_session_screen_test.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:ai_shopkeeper/core/error/result.dart';
import 'package:ai_shopkeeper/features/cart/presentation/cart_controller.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/inventory/presentation/inventory_controller.dart';
import 'package:ai_shopkeeper/features/scan/data/scan_camera.dart';
import 'package:ai_shopkeeper/features/scan/data/vision_scan_repository.dart';
import 'package:ai_shopkeeper/features/scan/domain/recognition_result.dart';
import 'package:ai_shopkeeper/features/scan/presentation/scan_session_screen.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

const _pepsi = Product(
  id: 'p-pepsi', shopId: 's1', name: 'Pepsi', sellingPrice: 50,
  quantity: 10, unit: ProductUnit.pcs,
);

class _InstantRepo implements VisionScanRepository {
  @override
  Future<Result<RecognitionResult>> recognize({
    required Uint8List imageBytes,
    required List<Map<String, dynamic>> candidates,
  }) async => Result.success(const RecognitionResult(
        status: RecognitionStatus.match,
        matches: [ProductMatch(productId: '0', confidence: 0.95)],
      ));
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  ScanCamera? camera,
}) async {
  final c = ProviderContainer(overrides: [
    visionScanRepositoryProvider.overrideWithValue(_InstantRepo()),
    scanCameraProvider.overrideWithValue(camera ?? FakeScanCamera()),
    productsStreamProvider.overrideWith((ref) => Stream.value([_pepsi])),
  ]);
  addTearDown(c.dispose);
  await c.read(productsStreamProvider.future);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ScanSessionScreen(),
    ),
  ));
  await tester.pump();
  return c;
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('the shutter stays usable while a chip is still recognizing',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('scan-shutter')));
    await tester.pump();
    // The critical property: no modal, no spinner blocking the camera.
    expect(find.byType(ModalBarrier), findsNothing);
    expect(find.byKey(const Key('scan-shutter')), findsOneWidget);
  });

  testWidgets('three shutter taps of one product show a single x3 chip',
      (tester) async {
    await _pump(tester);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const Key('scan-shutter')));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('Pepsi'), findsOneWidget);
    expect(find.textContaining('3'), findsWidgets);
  });

  testWidgets('Add stages the tray into the cart and empties it',
      (tester) async {
    final c = await _pump(tester);
    await tester.tap(find.byKey(const Key('scan-shutter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan-add-all')));
    await tester.pumpAndSettle();

    expect(c.read(cartControllerProvider).length, 1);
    expect(c.read(cartControllerProvider).single.product.id, 'p-pepsi');
  });

  testWidgets('a denied camera explains itself instead of showing black',
      (tester) async {
    await _pump(tester, camera: FakeScanCamera(permissionGranted: false));
    await tester.pumpAndSettle();
    expect(find.textContaining('Camera access'), findsOneWidget);
    expect(find.text('Open settings'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `flutter test test/widgets/scan_session_screen_test.dart`
Expected: FAIL — `scan_session_screen.dart` does not exist.

- [ ] **Step 4: Build the tray**

Create `lib/features/scan/presentation/scan_tray.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../cart/domain/cart_math.dart';
import '../../inventory/domain/product.dart';
import '../domain/scan_item.dart';
import 'scan_session_controller.dart';

/// The horizontal strip of what has been scanned so far. This IS the
/// confirmation step -- it replaces the per-item modal sheet, so every state a
/// chip can be in has to be legible at a glance.
class ScanTray extends ConsumerWidget {
  const ScanTray({super.key, required this.onPick});

  /// Opens the product picker for an ambiguous or unmatched chip.
  final void Function(ScanItem item) onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(scanSessionProvider);
    final l10n = context.l10n;
    if (items.isEmpty) {
      return SizedBox(
        height: 84,
        child: Center(
          child: Text(l10n.scan_nothingYet,
              style: Theme.of(context).textTheme.bodySmall),
        ),
      );
    }
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) => _Chip(item: items[i], onPick: onPick),
      ),
    );
  }
}

class _Chip extends ConsumerWidget {
  const _Chip({required this.item, required this.onPick});

  final ScanItem item;
  final void Function(ScanItem) onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final ctl = ref.read(scanSessionProvider.notifier);

    return switch (item.status) {
      ScanItemStatus.recognizing => _Shell(
        child: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      ScanItemStatus.failed => _Shell(
        onTap: () => ctl.retry(item.id),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.refresh, size: 18),
            const SizedBox(width: 6),
            Text(l10n.common_retry),
          ],
        ),
      ),
      ScanItemStatus.ambiguous || ScanItemStatus.unmatched => _Shell(
        onTap: () => onPick(item),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.readLabel ?? l10n.scan_notIdentified,
                style: theme.textTheme.labelLarge),
            Text(l10n.scan_tapToPick, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
      ScanItemStatus.resolved => _Resolved(item: item),
    };
  }
}

class _Resolved extends ConsumerWidget {
  const _Resolved({required this.item});

  final ScanItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ctl = ref.read(scanSessionProvider.notifier);
    final product = item.product!;
    final step = stepForUnit(product.unit);
    return _Shell(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(product.name, style: theme.textTheme.labelLarge),
              Text(
                '${Product.trimNum(item.quantity)} ${product.unitLabel}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(width: 4),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => ctl.setQuantity(item.id, item.quantity - step),
            icon: const Icon(Icons.remove, size: 18),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => ctl.setQuantity(item.id, item.quantity + step),
            icon: const Icon(Icons.add, size: 18),
          ),
        ],
      ),
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(child: child),
      ),
    );
  }
}
```

- [ ] **Step 5: Build the screen**

Create `lib/features/scan/presentation/scan_session_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/haptics.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../inventory/domain/product.dart';
import '../../inventory/presentation/inventory_controller.dart';
import '../data/scan_camera.dart';
import '../domain/scan_item.dart';
import 'scan_session_controller.dart';
import 'scan_tray.dart';
import 'top_sellers_strip.dart';
import 'product_picker_sheet.dart';

/// The scan session. The viewfinder never closes and recognition happens behind
/// it, so a basket is shot in one continuous run instead of one modal per item.
/// Nothing reaches the cart until "Add" -- the tray, not a per-item sheet, is
/// where AI output gets confirmed.
class ScanSessionScreen extends ConsumerStatefulWidget {
  const ScanSessionScreen({super.key});

  @override
  ConsumerState<ScanSessionScreen> createState() => _ScanSessionScreenState();
}

class _ScanSessionScreenState extends ConsumerState<ScanSessionScreen>
    with WidgetsBindingObserver {
  bool _ready = false;
  bool _denied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  Future<void> _start() async {
    try {
      await ref.read(scanCameraProvider).initialize();
      if (mounted) setState(() => _ready = true);
    } on CameraPermissionDenied {
      if (mounted) setState(() => _denied = true);
    }
  }

  /// Android reclaims the camera when the app leaves the foreground. Without
  /// this the user returns to a frozen preview and a leaked handle -- the
  /// best-known trap in the `camera` package. The tray is untouched by it.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      ref.read(scanCameraProvider).dispose();
      if (mounted) setState(() => _ready = false);
    } else if (state == AppLifecycleState.resumed && !_denied) {
      _start();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ref.read(scanCameraProvider).dispose();
    super.dispose();
  }

  Future<void> _shutter() async {
    AppHaptics.tap();
    await ref.read(scanSessionProvider.notifier).capture();
  }

  Future<void> _pick(ScanItem item) async {
    final all = item.choices.isNotEmpty
        ? item.choices
        : (ref.read(productsStreamProvider).value ?? const <Product>[]);
    final picked = await showProductPickerSheet(
      context,
      products: all,
      title: context.l10n.scan_didYouMean,
      readLabel: item.readLabel,
    );
    if (picked != null) {
      ref.read(scanSessionProvider.notifier).choose(item.id, picked);
    }
  }

  Future<void> _addAll() async {
    final items = ref.read(scanSessionProvider);
    final unresolved = items.where((i) => !i.isAddable).length;
    if (unresolved > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.l10n.scan_discardTitle),
          content: Text(ctx.l10n.scan_discardBody(unresolved)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(ctx.l10n.common_cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(ctx.l10n.common_add),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    ref.read(scanSessionProvider.notifier).addAllToCart();
    AppHaptics.success();
    if (mounted) context.pop();
  }

  Future<bool> _confirmLeave() async {
    final staged = ref.read(scanSessionProvider).length;
    if (staged == 0) return true;
    final choice = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.scan_leaveTitle),
        content: Text(ctx.l10n.scan_leaveBody(staged)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.l10n.common_discard),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.l10n.common_add),
          ),
        ],
      ),
    );
    if (choice == true) {
      ref.read(scanSessionProvider.notifier).addAllToCart();
    } else {
      ref.read(scanSessionProvider.notifier).clear();
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final items = ref.watch(scanSessionProvider);
    final pending = items.where((i) => i.isPending).length;
    final addable = items.where((i) => i.isAddable).length;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && mounted) context.pop();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.inventory_scanProduct)),
        body: Column(
          children: [
            Expanded(child: _viewfinder(l10n)),
            const TopSellersStrip(),
            const Divider(height: 1),
            ScanTray(onPick: _pick),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: FilledButton(
                  key: const Key('scan-add-all'),
                  onPressed: (pending > 0 || addable == 0) ? null : _addAll,
                  child: Text(
                    pending > 0
                        ? l10n.scan_recognizing(pending)
                        : l10n.scan_addItems(addable),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _viewfinder(dynamic l10n) {
    if (_denied) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined, size: 48),
              const SizedBox(height: 12),
              Text(l10n.scan_cameraDenied, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _start,
                child: Text(l10n.scan_openSettings),
              ),
            ],
          ),
        ),
      );
    }
    if (!_ready) return const Center(child: CircularProgressIndicator());
    return Stack(
      fit: StackFit.expand,
      children: [
        ref.read(scanCameraProvider).buildPreview(context),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: FloatingActionButton.large(
              key: const Key('scan-shutter'),
              onPressed: _shutter,
              child: const Icon(Icons.camera_alt),
            ),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 6: Swap the route and delete the old screen**

In `lib/core/router/app_router.dart`, change the import at line 23 to `import '../../features/scan/presentation/scan_session_screen.dart';` and make the `/scan` route build `const ScanSessionScreen()`.

Run: `git rm lib/features/scan/presentation/scan_screen.dart`

`scan_controller.dart` is now unused by the session (it holds the old `image_picker` capture). Delete it too:

Run: `git rm lib/features/scan/presentation/scan_controller.dart`

`ScanOutcome.readLabel` moves into the session controller's `_readLabel`, so check whether `test/scan_read_label_test.dart` still compiles. If it referenced `ScanOutcome`, rewrite it against `ScanSessionController` behaviour or delete it — do not leave a test importing a deleted file.

- [ ] **Step 7: Run the tests**

Run: `flutter test && flutter analyze`
Expected: green, clean. `top_sellers_strip.dart` does not exist yet — create it as a stub returning `const SizedBox.shrink()` so this task compiles; Task 6 fills it in.

- [ ] **Step 8: Commit**

```bash
git add -A lib/features/scan lib/core/router/app_router.dart lib/l10n test/widgets/scan_session_screen_test.dart
git commit -m "feat(scan): live viewfinder session replaces the serial loop

The camera stays open and recognition runs behind it, so a ten-item
basket is ~11 taps and ~20s instead of ~40 taps and ~75s.

Confirmation moves from once-per-item to once-per-customer. That is a
deliberate weakening of a safety mechanism -- see the spec's section 8
for why it was accepted and what to change first if wrong items start
reaching real sales.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 6: Top-sellers strip

**Files:**
- Rewrite: `lib/features/scan/presentation/top_sellers_strip.dart` (stubbed in Task 5)
- Test: `test/widgets/top_sellers_strip_test.dart`

**Interfaces:**
- Consumes: `bestSellersProvider` (`AsyncValue<List<BestSeller>>`, each with `productId`/`name`/`units`), `productsStreamProvider`, `scanSessionProvider`.
- Produces: `class TopSellersStrip extends ConsumerWidget` (const constructor, no args).

- [ ] **Step 1: Write the failing test**

Create `test/widgets/top_sellers_strip_test.dart`:

```dart
import 'package:ai_shopkeeper/features/analytics/presentation/analytics_controller.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/inventory/presentation/inventory_controller.dart';
import 'package:ai_shopkeeper/features/scan/presentation/scan_session_controller.dart';
import 'package:ai_shopkeeper/features/scan/presentation/top_sellers_strip.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

const _pepsi = Product(
  id: 'p-pepsi', shopId: 's1', name: 'Pepsi', sellingPrice: 50,
  quantity: 10, unit: ProductUnit.pcs,
);
const _gone = Product(
  id: 'p-gone', shopId: 's1', name: 'Sold Out Soap', sellingPrice: 30,
  quantity: 0, unit: ProductUnit.pcs,
);

Future<ProviderContainer> _pump(
  WidgetTester tester,
  List<BestSeller> sellers,
) async {
  final c = ProviderContainer(overrides: [
    productsStreamProvider.overrideWith((ref) => Stream.value([_pepsi, _gone])),
    bestSellersProvider.overrideWithValue(AsyncValue.data(sellers)),
  ]);
  addTearDown(c.dispose);
  await c.read(productsStreamProvider.future);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: TopSellersStrip()),
    ),
  ));
  await tester.pumpAndSettle();
  return c;
}

BestSeller _s(String id, String name, double units) =>
    BestSeller(productId: id, name: name, categoryId: null, units: units, revenue: 0);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('a tap stages the product in the tray, with no AI call',
      (tester) async {
    final c = await _pump(tester, [_s('p-pepsi', 'Pepsi', 40)]);
    await tester.tap(find.text('Pepsi'));
    await tester.pump();

    final items = c.read(scanSessionProvider);
    expect(items.single.product?.id, 'p-pepsi');
    expect(items.single.quantity, 1);
  });

  testWidgets('tapping twice merges into one chip', (tester) async {
    final c = await _pump(tester, [_s('p-pepsi', 'Pepsi', 40)]);
    await tester.tap(find.text('Pepsi'));
    await tester.pump();
    await tester.tap(find.text('Pepsi'));
    await tester.pump();

    expect(c.read(scanSessionProvider).length, 1);
    expect(c.read(scanSessionProvider).single.quantity, 2);
  });

  testWidgets('out-of-stock sellers are not offered', (tester) async {
    await _pump(tester, [_s('p-gone', 'Sold Out Soap', 90)]);
    expect(find.text('Sold Out Soap'), findsNothing);
  });

  testWidgets('a shop with no sales history shows no strip', (tester) async {
    await _pump(tester, const []);
    expect(find.byType(SizedBox), findsWidgets);
    expect(find.text('Pepsi'), findsNothing);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/widgets/top_sellers_strip_test.dart`
Expected: FAIL — the stub renders nothing and stages nothing.

- [ ] **Step 3: Implement the strip**

Replace `lib/features/scan/presentation/top_sellers_strip.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/haptics.dart';
import '../../analytics/presentation/analytics_controller.dart';
import '../../inventory/domain/product.dart';
import '../../inventory/presentation/inventory_controller.dart';
import 'scan_session_controller.dart';

/// How many shortcuts fit before the row becomes a scroll nobody reads.
const _maxTopSellers = 12;

/// One-tap shortcuts for the products this shop actually sells all day.
///
/// Costs nothing new: `bestSellersProvider` already exists for the Reports tab,
/// derived from `TransactionRepository.recentSales()`. No migration, nothing to
/// deploy. Every tap here is a Gemini call that never happens, which is why
/// this is the cost feature as much as the speed one.
///
/// Hidden entirely when the shop has no sales history -- alphabetical filler
/// would just teach the shopkeeper to ignore the row.
class TopSellersStrip extends ConsumerWidget {
  const TopSellersStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(productsStreamProvider).value ?? const <Product>[];
    final byId = {for (final p in products) p.id: p};
    final sellers = ref.watch(bestSellersProvider).value ?? const <BestSeller>[];

    final shortcuts = <Product>[
      for (final s in sellers)
        if (byId[s.productId] case final Product p)
          if (p.quantity > 0) p,
    ].take(_maxTopSellers).toList();

    if (shortcuts.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: shortcuts.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final p = shortcuts[i];
          return ActionChip(
            avatar: Icon(Icons.bolt, size: 16, color: theme.colorScheme.primary),
            label: Text(p.name),
            onPressed: () {
              AppHaptics.tap();
              ref.read(scanSessionProvider.notifier).addShortcut(p);
            },
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 4: Add `addShortcut` to the session controller**

In `lib/features/scan/presentation/scan_session_controller.dart`, add after `capture()`:

```dart
  /// Stages [product] directly -- no camera, no recognition, no network. Merges
  /// by the same rule as a resolved scan, so tapping a shortcut twice gives one
  /// chip at x2.
  void addShortcut(Product product) {
    final id = 'chip-${_seq++}';
    state = [
      ...state,
      ScanItem(id: id, status: ScanItemStatus.recognizing),
    ];
    _resolve(id, product, null);
  }
```

- [ ] **Step 5: Run the tests**

Run: `flutter test test/widgets/top_sellers_strip_test.dart test/scan_session_controller_test.dart`
Expected: PASS.

- [ ] **Step 6: Full suite**

Run: `flutter test && flutter analyze`
Expected: green, clean.

- [ ] **Step 7: Commit**

```bash
git add lib/features/scan/presentation/top_sellers_strip.dart lib/features/scan/presentation/scan_session_controller.dart test/widgets/top_sellers_strip_test.dart
git commit -m "feat(scan): one-tap shortcuts for the shop's top sellers

Baskets are a real mix of regulars and unusual items, so the camera is
the wrong tool for half of them. Every tap here is a Gemini call that
never happens -- this is the cost feature as much as the speed one.

Built on bestSellersProvider, which already exists for Reports, so there
is no migration and nothing for the user to deploy.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 7: Probe checklist and spec outcomes

The user runs all server-side steps themselves; this task gives them the script.

**Files:**
- Modify: `supabase/README.md`
- Modify: `docs/superpowers/specs/2026-08-10-fast-scan-session-design.md`

- [ ] **Step 1: Add the deploy + probe section**

Append to `supabase/README.md`:

```markdown
## Fast scan session — deploy order and probes

**Deploy the Edge Function BEFORE installing an app build from
`feat/fast-scan`.** This is the reverse of migration `0009`, and the failure is
quiet rather than loud: a new app sends candidates keyed by list index (`i`),
an old function looks for `id`, every match is filtered out, and the app
reports "no match" for everything with no error anywhere. `recognize-product`
accepts BOTH shapes, so deploying it early is always safe.

1. Deploy `recognize-product` (`index.ts` only — no other files).
2. Probe it still answers the OLD shape, so an installed app keeps working:
   send `{"image_base64": "<jpeg>", "candidates": [{"id":"<real-uuid>","name":"Pepsi"}]}`
   and confirm a `product_id` equal to that uuid comes back.
3. Probe the NEW shape: same image, `candidates: [{"i":0,"name":"Pepsi"}]`.
   Expect `product_id: "0"`.
4. Install the app build and scan a real product. Confirm it resolves to the
   right item — this is what proves the index round-trip.
5. **Check label legibility.** Capture now runs at `ResolutionPreset.medium`
   (640x480) rather than the old 768px. Scan something with small print. If
   recognition is worse than it used to be, change `ResolutionPreset.medium` to
   `.high` in `lib/features/scan/data/real_scan_camera.dart` — that is the one
   number in this feature chosen without evidence.
6. Scan five items back-to-back without pausing. Confirm the shutter never
   blocks and all five chips resolve.
7. Background the app mid-session and return. The preview must come back live,
   not frozen, and the tray must still hold its chips.
8. Deny the camera permission once. Confirm the explanation screen appears
   instead of a black rectangle.
```

- [ ] **Step 2: Record the outcome section in the spec**

Append a `## 12. Outcomes` section to the design doc noting: what shipped, anything the probes changed (especially whether `ResolutionPreset.medium` survived), and any defect review caught. Leave the resolution line explicitly marked as unverified until the user reports back.

- [ ] **Step 3: Commit**

```bash
git add supabase/README.md docs/superpowers/specs/2026-08-10-fast-scan-session-design.md
git commit -m "docs: deploy order and probe checklist for the fast scan session

The function must go out before the app, and the mismatch degrades
silently to \"no match\" rather than failing loudly -- so the ordering is
written down rather than left to memory.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 8: Voice indexed candidates (independently droppable)

Last deliberately. Voice sends roughly one call per sentence against scan's one per item, so this is the smaller share of the saving, and `productId` threads through six files — `VoiceMatch`, `VoiceLine.chosenProductId`, the review sheet's choice chips. **If this turns hairy, stop and leave voice on uuids; Tasks 1–7 stand alone.**

**Files:**
- Modify: `lib/features/voice/presentation/voice_controller.dart:388`
- Modify: `lib/features/voice/domain/voice_parse_result.dart`
- Modify: `supabase/functions/parse-sale/index.ts:17`, `:292`
- Modify: `lib/features/scan/domain/scan_candidates.dart` (drop the Task 1 shim)
- Test: `test/voice_candidate_index_test.dart`

**Interfaces:**
- Consumes: `CandidatePayload` (Task 1).
- Produces: `VoiceParseResult.resolveIds(String? Function(String))`.

- [ ] **Step 1: Write the failing test**

Create `test/voice_candidate_index_test.dart`:

```dart
import 'package:ai_shopkeeper/features/voice/domain/voice_parse_result.dart';
import 'package:flutter_test/flutter_test.dart';

/// Voice keeps real product ids everywhere downstream -- the review sheet's
/// choice chips look products up by id. So the index the model echoes is
/// translated at the parse boundary and never travels further.
void main() {
  test('indices become product ids at the boundary', () {
    final parsed = VoiceParseResult.fromJson(const {
      'heard_text': 'two pepsi',
      'items': [
        {
          'heard': 'pepsi',
          'quantity': 2,
          'matches': [
            {'product_id': '0', 'confidence': 0.9},
          ],
        },
      ],
    });
    final resolved = parsed.resolveIds((s) => s == '0' ? 'uuid-pepsi' : null);
    expect(resolved.items.single.matches.single.productId, 'uuid-pepsi');
  });

  test('an unresolvable index is dropped, never passed through raw', () {
    final parsed = VoiceParseResult.fromJson(const {
      'heard_text': 'x',
      'items': [
        {
          'heard': 'x',
          'quantity': 1,
          'matches': [
            {'product_id': '99', 'confidence': 0.9},
          ],
        },
      ],
    });
    final resolved = parsed.resolveIds((_) => null);
    expect(resolved.items.single.matches, isEmpty);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/voice_candidate_index_test.dart`
Expected: FAIL — `resolveIds` is not defined.

- [ ] **Step 3: Add `resolveIds`**

In `lib/features/voice/domain/voice_parse_result.dart`, add to `VoiceParseResult`:

```dart
  /// Translates every match's identifier through [resolve], dropping any the
  /// resolver rejects. Called immediately after parsing so nothing downstream
  /// -- the review sheet, `chosenProductId`, the cart -- ever sees an index.
  VoiceParseResult resolveIds(String? Function(String) resolve) =>
      VoiceParseResult(
        heardText: heardText,
        items: [
          for (final it in items)
            it.copyWithMatches([
              for (final m in it.matches)
                if (resolve(m.productId) case final String id)
                  VoiceMatch(productId: id, confidence: m.confidence),
            ]),
        ],
      );
```

Add whatever `copyWithMatches` shape the existing item class needs — read the file first and match its constructor exactly rather than assuming field names.

- [ ] **Step 4: Wire the controller**

In `voice_controller.dart`, replace `_candidates()` with a payload-returning helper and pass `payload.resolve` into the parse result before it lands in state:

```dart
  CandidatePayload _candidatePayload() => buildCandidatePayload(
    ref.read(productsStreamProvider).value ?? const [],
    includeUnit: true,
    recentUnits: ref.read(recentUnitsSoldProvider).value,
  );
```

At every call site that parses a response, apply `.resolveIds(payload.resolve)` to the result before it reaches `state`.

- [ ] **Step 5: Teach `parse-sale` both shapes**

In `supabase/functions/parse-sale/index.ts`, make `Candidate.id` optional and add `i?: number` (mirroring Task 1's comment), then change the `ids` set to `candidates.map((c) => c.id ?? String(c.i))`.

- [ ] **Step 6: Drop the Task 1 shim**

Delete `buildCandidates` from `scan_candidates.dart` and its remaining references.

- [ ] **Step 7: Run everything**

Run: `flutter test && flutter analyze`
Expected: green, clean. The voice suite is large (`voice_controller_test.dart` is 35KB) — **any failure there means stop and reassess**, not patch the test.

- [ ] **Step 8: Commit**

```bash
git add lib/features/voice supabase/functions/parse-sale/index.ts lib/features/scan/domain/scan_candidates.dart test/voice_candidate_index_test.dart
git commit -m "perf(voice): send candidates by index too

Same saving as scan, applied to the voice prompt. Indices are translated
back to product ids at the parse boundary so the review sheet and
chosenProductId keep working on real ids.

parse-sale must be deployed BEFORE an app build carrying this.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:** §3.1 → Task 3; §3.2 merge-on-resolve → Task 3 Step 4 `_resolve`; §3.3 cap of 3 → Task 3 (`maxScanInFlight` + test); §3.4 fakeable camera → Task 2; §3.5 resolution → Task 4 + probe 5; §4 layout → Task 5; §5 strip → Task 6; §6 token trim → Tasks 1 and 8; §6.1 deploy order → Task 1 Step 5 and Task 7; §7 error handling → Task 3 (failure/frame/retry) and Task 5 (permission, lifecycle, back, add-button states); §8 costs → recorded in the spec, referenced in the Task 5 commit; §9 testing → tests in every task; §10 out of scope → nothing here implements it; §11 rollback → the Edge Function change is additive.

**Known gap:** §7's "out of stock chip is flagged and excluded" is only half-covered — `_clamp` returns 0 and `setQuantity` removes the chip, so an out-of-stock product silently vanishes rather than showing a flagged chip. Task 6's `scan_outOfStock` key exists for it. **Task 5's implementer should render a disabled chip when `_clamp` yields 0 instead of dropping it**, or the shopkeeper gets no explanation for the disappearance.

**Placeholder scan:** no TBD/TODO. Task 8 Steps 3–4 deliberately say "read the file first and match its constructor" rather than inventing `VoiceItem`'s exact shape — that file was not read while planning, and guessing a signature would be worse than naming the uncertainty.

**Type consistency:** `buildCandidatePayload`/`CandidatePayload.resolve` consistent across Tasks 1, 3, 8. `ScanItem.isAddable`/`isPending` defined in Task 3 and used in Tasks 5 and 6. `addShortcut` defined in Task 6 and called only there. `scanCameraProvider` defined Task 2, overridden Task 4, read Tasks 3 and 5. `FakeScanCamera(permissionGranted:)` consistent between Tasks 2 and 5.
