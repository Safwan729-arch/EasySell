# Voice Sale Assistant Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a shopkeeper speak a multi-item sale ("sold 2 Pepsi and 3 chips"), match it against their own inventory, review/disambiguate it, and stage it into the existing cart for normal checkout.

**Architecture:** Mirrors the vision-scan feature. The phone records audio and posts it to a new `parse-sale` Supabase Edge Function which holds the gateway key, sends the shop's product list as a closed-set candidate list, and returns normalized `{heard_text, items[]}` JSON. Pure client-side threshold logic turns each item into a resolved / ambiguous / not-found line; a review sheet forces the user to settle every ambiguous line before anything reaches the cart. `record_sale_cart` is never called directly by this feature.

**Tech Stack:** Flutter, Riverpod, Supabase Edge Functions (Deno/TypeScript), Frog OpenAI-compatible gateway, `record` package for audio capture.

**Spec:** `docs/superpowers/specs/2026-07-22-voice-sale-assistant-design.md`

---

## File Structure

| File | Responsibility |
|---|---|
| `lib/features/voice/domain/voice_parse_result.dart` | Parse the Edge Function JSON. No logic. |
| `lib/features/voice/domain/voice_decision.dart` | PURE: matches → resolved/ambiguous/notFound. |
| `lib/features/voice/domain/voice_line.dart` | PURE: one reviewable line + list-level gating. |
| `lib/features/voice/data/voice_sale_repository.dart` | Invoke `parse-sale`, map errors to `Failure`. |
| `lib/features/voice/data/audio_recorder.dart` | MEMBER C seam: start/stop → bytes + mime. |
| `lib/features/voice/presentation/voice_controller.dart` | Orchestrate record → parse → lines. |
| `lib/features/voice/presentation/voice_sale_sheet.dart` | Mic UI: idle/recording/thinking/error. |
| `lib/features/voice/presentation/voice_review_sheet.dart` | Review + inline disambiguation. |
| `supabase/functions/parse-sale/index.ts` | Audio → transcript → intent + closed-set match. |

**Boundary rule:** everything in `domain/` is pure Dart — no Flutter, no network — so the correctness-critical logic is unit-testable without a device.

---

### Task 0: Spike — does the gateway accept audio? (GATING)

Nothing else is worth building until this is answered. The spec's Strategy 1 (one multimodal
call) vs Strategy 2 (transcribe, then chat) depends entirely on this.

**Files:**
- Create: `docs/superpowers/spikes/2026-07-22-frog-audio-support.md`

- [ ] **Step 1: Get the gateway key**

The key lives in Supabase secrets, not in the repo. Retrieve it:

```bash
supabase secrets list
```

If the CLI is not linked, read `FROG_API_KEY` from the Supabase Dashboard →
Project Settings → Edge Functions → Secrets. **Do not commit the key anywhere.**

- [ ] **Step 2: Probe Strategy 1 (audio inside chat/completions)**

Record or grab any short `.m4a` saying "sold two pepsi", then:

```bash
export FROG_API_KEY=<key>
B64=$(base64 -w0 sample.m4a)
curl -s -X POST https://frogapi.app/v1/chat/completions \
  -H "Authorization: Bearer $FROG_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"Gemini-3.1-Pro\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"Transcribe this audio.\"},{\"type\":\"input_audio\",\"input_audio\":{\"data\":\"$B64\",\"format\":\"m4a\"}}]}]}"
```

Expected if supported: a 200 with a transcript in `choices[0].message.content`.
Expected if unsupported: 400/415/422 complaining about the content part type.

- [ ] **Step 3: Probe Strategy 2 (dedicated transcription endpoint)**

```bash
curl -s -X POST https://frogapi.app/v1/audio/transcriptions \
  -H "Authorization: Bearer $FROG_API_KEY" \
  -F file=@sample.m4a \
  -F model=whisper-1
```

Expected if supported: `{"text":"sold two pepsi"}`.

- [ ] **Step 4: Record the finding**

Write `docs/superpowers/spikes/2026-07-22-frog-audio-support.md` containing: which probe
succeeded, the exact model slug that worked, the response shape, and the chosen strategy
(`VOICE_STRATEGY=multimodal` or `VOICE_STRATEGY=transcribe`).

If **neither** works, STOP and report — the feature needs a different provider and the spec
must be revisited before any code is written.

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/spikes/2026-07-22-frog-audio-support.md
git commit -m "docs(voice): spike result for gateway audio support"
```

---

### Task 1: Feature flag

**Files:**
- Modify: `lib/core/config/feature_flags.dart`

- [ ] **Step 1: Add the flag**

```dart
  /// Enables the microphone "Voice Sale" flow. Turn on with
  /// `--dart-define=VOICE_SALE_ENABLED=true`.
  static const bool voiceSaleEnabled =
      bool.fromEnvironment('VOICE_SALE_ENABLED', defaultValue: false);
```

Place it directly below `visionScanEnabled`, inside the `FeatureFlags` class.

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/core/config/feature_flags.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/core/config/feature_flags.dart
git commit -m "feat(voice): add voiceSaleEnabled feature flag"
```

---

### Task 2: Parse the Edge Function response

**Files:**
- Create: `lib/features/voice/domain/voice_parse_result.dart`
- Test: `test/voice_parse_result_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/voice/domain/voice_parse_result.dart';

void main() {
  test('parses transcript, items, quantity and ranked matches', () {
    final r = VoiceParseResult.fromJson({
      'heard_text': 'sold 2 pepsi and 3 chips',
      'items': [
        {
          'heard': 'pepsi',
          'quantity': 2,
          'unit_heard': 'piece',
          'matches': [
            {'product_id': 'a', 'confidence': 0.55},
            {'product_id': 'b', 'confidence': 0.52},
          ],
        },
      ],
    });

    expect(r.heardText, 'sold 2 pepsi and 3 chips');
    expect(r.items, hasLength(1));
    expect(r.items.first.heard, 'pepsi');
    expect(r.items.first.quantity, 2);
    expect(r.items.first.unitHeard, 'piece');
    expect(r.items.first.quantityAssumed, isFalse);
    expect(r.items.first.matches.map((m) => m.productId), ['a', 'b']);
  });

  test('empty items parses to an empty list, not an error', () {
    final r = VoiceParseResult.fromJson({'heard_text': 'hello', 'items': []});
    expect(r.items, isEmpty);
  });

  test('missing quantity defaults to 1 and is flagged as assumed', () {
    final r = VoiceParseResult.fromJson({
      'items': [
        {'heard': 'pepsi', 'matches': []},
      ],
    });
    expect(r.items.first.quantity, 1);
    expect(r.items.first.quantityAssumed, isTrue);
  });

  test('a size word is never folded into quantity', () {
    // "1 litre" is a SIZE: it belongs in `heard`, and quantity stays 1.
    final r = VoiceParseResult.fromJson({
      'items': [
        {'heard': 'pepsi 1 litre', 'quantity': 1, 'unit_heard': null, 'matches': []},
      ],
    });
    expect(r.items.first.quantity, 1);
    expect(r.items.first.heard, contains('litre'));
    expect(r.items.first.unitHeard, isNull);
  });

  test('non-positive or non-numeric quantities fall back to 1 (assumed)', () {
    final r = VoiceParseResult.fromJson({
      'items': [
        {'heard': 'a', 'quantity': 0, 'matches': []},
        {'heard': 'b', 'quantity': 'two', 'matches': []},
      ],
    });
    expect(r.items[0].quantity, 1);
    expect(r.items[0].quantityAssumed, isTrue);
    expect(r.items[1].quantity, 1);
    expect(r.items[1].quantityAssumed, isTrue);
  });

  test('malformed payload yields an empty result rather than throwing', () {
    final r = VoiceParseResult.fromJson({'nonsense': true});
    expect(r.items, isEmpty);
    expect(r.heardText, isNull);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/voice_parse_result_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '.../voice_parse_result.dart'`

- [ ] **Step 3: Write the implementation**

```dart
// The parsed outcome of a `parse-sale` request. Plain Dart (no codegen) so the
// JSON handling is small, explicit, and directly unit-testable -- same choice as
// the vision scan's RecognitionResult.

/// One candidate product the model matched, by the shop's own product id.
class VoiceMatch {
  const VoiceMatch({required this.productId, required this.confidence});

  final String productId;
  final double confidence;

  factory VoiceMatch.fromJson(Map<String, dynamic> json) => VoiceMatch(
    productId: json['product_id'] as String,
    confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
  );
}

/// One spoken item: what was heard, how many, and which products it might be.
class VoiceItem {
  const VoiceItem({
    required this.heard,
    required this.quantity,
    required this.quantityAssumed,
    this.unitHeard,
    this.matches = const <VoiceMatch>[],
  });

  /// The fragment of speech this line came from, e.g. "pepsi 1 litre". Size
  /// words live HERE (they identify the product); counts live in [quantity].
  final String heard;

  /// How many units. Never carries a size -- see [heard].
  final double quantity;

  /// True when the speaker gave no count and we defaulted to 1. The review UI
  /// highlights these so an assumed number is never mistaken for a heard one.
  final bool quantityAssumed;

  /// A spoken count word ("piece", "packet", "টা"), when present. Advisory only.
  final String? unitHeard;

  /// Ranked candidates, highest confidence first.
  final List<VoiceMatch> matches;

  factory VoiceItem.fromJson(Map<String, dynamic> json) {
    final rawQty = json['quantity'];
    final qty = rawQty is num ? rawQty.toDouble() : null;
    final valid = qty != null && qty > 0;
    final rawMatches = (json['matches'] as List?) ?? const [];
    return VoiceItem(
      heard: (json['heard'] as String?) ?? '',
      quantity: valid ? qty : 1,
      quantityAssumed: !valid,
      unitHeard: json['unit_heard'] as String?,
      matches: [
        for (final m in rawMatches)
          VoiceMatch.fromJson(Map<String, dynamic>.from(m as Map)),
      ],
    );
  }
}

/// Normalized result returned by the `parse-sale` Edge Function.
class VoiceParseResult {
  const VoiceParseResult({this.heardText, this.items = const <VoiceItem>[]});

  /// The full transcript, shown to the user so a mishear is obvious.
  final String? heardText;
  final List<VoiceItem> items;

  factory VoiceParseResult.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] as List?) ?? const [];
    return VoiceParseResult(
      heardText: json['heard_text'] as String?,
      items: [
        for (final i in rawItems)
          VoiceItem.fromJson(Map<String, dynamic>.from(i as Map)),
      ],
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/voice_parse_result_test.dart`
Expected: `+6: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/voice/domain/voice_parse_result.dart test/voice_parse_result_test.dart
git commit -m "feat(voice): parse parse-sale response; quantity kept separate from size"
```

---

### Task 3: The coin-flip rule (pure decision logic)

This is the correctness heart of the feature: never auto-pick between two products the
speech didn't distinguish.

**Files:**
- Create: `lib/features/voice/domain/voice_decision.dart`
- Test: `test/voice_decision_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/voice/domain/voice_decision.dart';
import 'package:mobile_app/features/voice/domain/voice_parse_result.dart';

VoiceMatch m(String id, double c) => VoiceMatch(productId: id, confidence: c);

void main() {
  test('a clear winner resolves to that product', () {
    // "pepsi 1 litre" -> 1L is far ahead.
    final d = decideVoiceLine([m('1L', 0.95), m('500ml', 0.20)]);
    expect(d.status, VoiceLineStatus.resolved);
    expect(d.choices.single.productId, '1L');
  });

  test('two near-identical scores are a coin flip and must ask', () {
    // "pepsi 1 piece" with both variants in stock -> ask, never guess.
    final d = decideVoiceLine([m('500ml', 0.55), m('1L', 0.52)]);
    expect(d.status, VoiceLineStatus.ambiguous);
    expect(d.choices.map((c) => c.productId), containsAll(['500ml', '1L']));
  });

  test('high confidence without a clear lead still asks', () {
    final d = decideVoiceLine([m('a', 0.91), m('b', 0.88)]);
    expect(d.status, VoiceLineStatus.ambiguous);
  });

  test('no matches at all is notFound', () {
    final d = decideVoiceLine([]);
    expect(d.status, VoiceLineStatus.notFound);
    expect(d.choices, isEmpty);
  });

  test('only weak matches is notFound', () {
    final d = decideVoiceLine([m('a', 0.30), m('b', 0.10)]);
    expect(d.status, VoiceLineStatus.notFound);
  });

  test('a lone match above the strong bar resolves', () {
    final d = decideVoiceLine([m('a', 0.84)]);
    expect(d.status, VoiceLineStatus.resolved);
  });

  test('a lone weak-but-plausible match asks rather than resolving', () {
    final d = decideVoiceLine([m('a', 0.60)]);
    expect(d.status, VoiceLineStatus.ambiguous);
  });

  test('choices are ranked and capped', () {
    final d = decideVoiceLine([
      m('a', 0.60), m('b', 0.59), m('c', 0.58), m('d', 0.57),
      m('e', 0.56), m('f', 0.55),
    ], thresholds: const VoiceThresholds(maxChoices: 3));
    expect(d.choices, hasLength(3));
    expect(d.choices.first.productId, 'a');
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/voice_decision_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '.../voice_decision.dart'`

- [ ] **Step 3: Write the implementation**

```dart
import 'voice_parse_result.dart';

/// What the review UI must do with one spoken line.
enum VoiceLineStatus {
  /// One product clearly won -- pre-filled, user can still change it.
  resolved,

  /// The speech did not distinguish between candidates. The user MUST choose.
  ambiguous,

  /// Nothing in the shop's inventory plausibly matches.
  notFound,
}

/// Tunable thresholds mapping model confidences to a review action. Mirrors
/// [ScanThresholds]; calibrate on real speech in Phase 3.
class VoiceThresholds {
  const VoiceThresholds({
    this.strong = 0.80,
    this.margin = 0.15,
    this.ambiguous = 0.50,
    this.maxChoices = 5,
  });

  /// Top-1 must reach this confidence to be pre-filled...
  final double strong;

  /// ...and lead the runner-up by at least this margin. Without this, two
  /// variants of the same product (Pepsi 500ml vs 1L) would be a coin flip
  /// decided by noise.
  final double margin;

  /// Any match at/above this can appear as a choice.
  final double ambiguous;

  /// Cap on candidates offered for one line.
  final int maxChoices;
}

/// The status of one line plus the matches it applies to.
class VoiceLineDecision {
  const VoiceLineDecision(this.status, this.choices);

  final VoiceLineStatus status;

  /// resolved -> exactly one; ambiguous -> the ranked shortlist; notFound -> empty.
  final List<VoiceMatch> choices;
}

/// Pure decision for a single spoken item. No I/O -- fully unit-testable.
VoiceLineDecision decideVoiceLine(
  List<VoiceMatch> matches, {
  VoiceThresholds thresholds = const VoiceThresholds(),
}) {
  final ranked = [...matches]
    ..sort((a, b) => b.confidence.compareTo(a.confidence));
  if (ranked.isEmpty) {
    return const VoiceLineDecision(VoiceLineStatus.notFound, []);
  }

  final top = ranked.first;
  final second = ranked.length > 1 ? ranked[1] : null;
  final leadsClearly =
      second == null || (top.confidence - second.confidence) >= thresholds.margin;

  if (top.confidence >= thresholds.strong && leadsClearly) {
    return VoiceLineDecision(VoiceLineStatus.resolved, [top]);
  }

  final plausible =
      ranked.where((m) => m.confidence >= thresholds.ambiguous).toList();
  if (plausible.isNotEmpty) {
    return VoiceLineDecision(
      VoiceLineStatus.ambiguous,
      plausible.take(thresholds.maxChoices).toList(),
    );
  }
  return const VoiceLineDecision(VoiceLineStatus.notFound, []);
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/voice_decision_test.dart`
Expected: `+8: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/voice/domain/voice_decision.dart test/voice_decision_test.dart
git commit -m "feat(voice): pure line decision -- ask on a coin flip, never guess"
```

---

### Task 4: Reviewable lines + the add-to-cart gate

**Files:**
- Create: `lib/features/voice/domain/voice_line.dart`
- Test: `test/voice_line_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/voice/domain/voice_decision.dart';
import 'package:mobile_app/features/voice/domain/voice_line.dart';
import 'package:mobile_app/features/voice/domain/voice_parse_result.dart';

VoiceItem item(String heard, double qty, List<VoiceMatch> matches) => VoiceItem(
  heard: heard, quantity: qty, quantityAssumed: false, matches: matches,
);
VoiceMatch m(String id, double c) => VoiceMatch(productId: id, confidence: c);

void main() {
  test('a clear winner arrives already chosen', () {
    final lines = buildVoiceLines(VoiceParseResult(
      items: [item('pepsi 1 litre', 2, [m('1L', 0.95), m('500ml', 0.2)])],
    ));
    expect(lines.single.status, VoiceLineStatus.resolved);
    expect(lines.single.chosenProductId, '1L');
    expect(lines.single.isSettled, isTrue);
  });

  test('a coin flip arrives unchosen with its options', () {
    final lines = buildVoiceLines(VoiceParseResult(
      items: [item('pepsi', 1, [m('500ml', 0.55), m('1L', 0.52)])],
    ));
    expect(lines.single.chosenProductId, isNull);
    expect(lines.single.isSettled, isFalse);
    expect(lines.single.choices, hasLength(2));
  });

  test('choosing a product settles the line', () {
    final line = buildVoiceLines(VoiceParseResult(
      items: [item('pepsi', 1, [m('500ml', 0.55), m('1L', 0.52)])],
    )).single;
    final settled = line.chooseProduct('1L');
    expect(settled.chosenProductId, '1L');
    expect(settled.isSettled, isTrue);
  });

  test('quantity can be corrected', () {
    final line = buildVoiceLines(VoiceParseResult(
      items: [item('pepsi 1 litre', 2, [m('1L', 0.95)])],
    )).single;
    expect(line.withQuantity(5).quantity, 5);
  });

  test('cannot add to cart while any line is unsettled', () {
    final lines = buildVoiceLines(VoiceParseResult(items: [
      item('pepsi 1 litre', 2, [m('1L', 0.95)]),
      item('biscuit', 1, []),
    ]));
    expect(canAddToCart(lines), isFalse);
  });

  test('can add once every line is settled', () {
    final lines = buildVoiceLines(VoiceParseResult(items: [
      item('pepsi 1 litre', 2, [m('1L', 0.95)]),
      item('chips', 3, [m('chips', 0.93)]),
    ]));
    expect(canAddToCart(lines), isTrue);
  });

  test('cannot add an empty list', () {
    expect(canAddToCart(const []), isFalse);
  });

  test('removing the unresolvable line unblocks the rest', () {
    final lines = buildVoiceLines(VoiceParseResult(items: [
      item('pepsi 1 litre', 2, [m('1L', 0.95)]),
      item('biscuit', 1, []),
    ]));
    expect(canAddToCart(removeLineAt(lines, 1)), isTrue);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/voice_line_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '.../voice_line.dart'`

- [ ] **Step 3: Write the implementation**

```dart
import 'voice_decision.dart';
import 'voice_parse_result.dart';

/// One row in the review sheet: what was heard, how many, and which product it
/// resolves to. Immutable -- edits return a new instance.
class VoiceLine {
  const VoiceLine({
    required this.heard,
    required this.quantity,
    required this.quantityAssumed,
    required this.status,
    required this.choices,
    this.chosenProductId,
  });

  final String heard;
  final double quantity;

  /// True when no count was spoken and we defaulted to 1; the UI highlights it.
  final bool quantityAssumed;

  final VoiceLineStatus status;

  /// Candidates to offer when the user must choose.
  final List<VoiceMatch> choices;

  /// The product this line will add to the cart. Null until settled.
  final String? chosenProductId;

  /// A line may only reach the cart once a real product is attached.
  bool get isSettled => chosenProductId != null;

  VoiceLine chooseProduct(String productId) => _copy(chosenProductId: productId);

  VoiceLine withQuantity(double newQuantity) => _copy(quantity: newQuantity);

  VoiceLine _copy({String? chosenProductId, double? quantity}) => VoiceLine(
    heard: heard,
    quantity: quantity ?? this.quantity,
    quantityAssumed: quantityAssumed,
    status: status,
    choices: choices,
    chosenProductId: chosenProductId ?? this.chosenProductId,
  );
}

/// Turn a parsed result into reviewable lines, pre-choosing only clear winners.
List<VoiceLine> buildVoiceLines(
  VoiceParseResult result, {
  VoiceThresholds thresholds = const VoiceThresholds(),
}) => [
  for (final item in result.items)
    () {
      final d = decideVoiceLine(item.matches, thresholds: thresholds);
      return VoiceLine(
        heard: item.heard,
        quantity: item.quantity,
        quantityAssumed: item.quantityAssumed,
        status: d.status,
        choices: d.choices,
        // Only a clear winner is pre-filled. Ambiguous and notFound stay null
        // so the user is forced to settle them.
        chosenProductId:
            d.status == VoiceLineStatus.resolved ? d.choices.single.productId : null,
      );
    }(),
];

/// Drop a line the user gave up on (e.g. an item they don't stock).
List<VoiceLine> removeLineAt(List<VoiceLine> lines, int index) =>
    [...lines]..removeAt(index);

/// The gate: nothing reaches the cart until every line has a real product.
bool canAddToCart(List<VoiceLine> lines) =>
    lines.isNotEmpty && lines.every((l) => l.isSettled);
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/voice_line_test.dart`
Expected: `+8: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/voice/domain/voice_line.dart test/voice_line_test.dart
git commit -m "feat(voice): reviewable lines and the add-to-cart gate"
```

---

### Task 5: Candidate list gains `unit` (without changing scan)

**Files:**
- Modify: `lib/features/scan/domain/scan_candidates.dart`
- Test: `test/scan_candidates_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/inventory/domain/product.dart';
import 'package:mobile_app/features/scan/domain/scan_candidates.dart';

void main() {
  // Build a Product via its existing constructor/fromJson; adjust field names
  // only if the model differs. Keep one shared fixture for both tests.
  final product = Product.fromJson(const {
    'id': 'p1',
    'shop_id': 's1',
    'name': 'Pepsi 1L',
    'brand': 'Pepsi',
    'variant': '1L',
    'quantity': 10,
    'buying_price': 50,
    'selling_price': 60,
    'reorder_threshold': 2,
    'unit': 'pcs',
  });

  test('scan payload is unchanged -- no unit key by default', () {
    final c = buildCandidates([product]).single;
    expect(c.containsKey('unit'), isFalse);
    expect(c['id'], 'p1');
    expect(c['brand'], 'Pepsi');
    expect(c['variant'], '1L');
  });

  test('voice opts in to unit', () {
    final c = buildCandidates([product], includeUnit: true).single;
    expect(c['unit'], isNotNull);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/scan_candidates_test.dart`
Expected: FAIL — `No named parameter with the name 'includeUnit'`

- [ ] **Step 3: Add the opt-in parameter**

Replace the body of `buildCandidates` with:

```dart
/// Turns the shop's products into the compact candidate list sent to a model.
/// Only id/name are guaranteed; brand/variant are included when present (they
/// sharpen matching). Loose items simply carry no brand/variant.
///
/// [includeUnit] is opt-in so the vision-scan payload stays byte-for-byte
/// unchanged; the voice flow enables it because spoken sizes ("1 litre") match
/// far better when the model can see each product's unit.
List<Map<String, dynamic>> buildCandidates(
  List<Product> products, {
  bool includeUnit = false,
}) => [
  for (final p in products)
    {
      'id': p.id,
      'name': p.name,
      if (p.brand != null && p.brand!.isNotEmpty) 'brand': p.brand,
      if (p.variant != null && p.variant!.isNotEmpty) 'variant': p.variant,
      if (includeUnit) 'unit': p.unit.name,
    },
];
```

If `Product.unit` is not an enum with `.name`, use the field's existing string
representation instead — check `lib/features/inventory/domain/product.dart` first.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/scan_candidates_test.dart`
Expected: `+2: All tests passed!`

- [ ] **Step 5: Confirm scan still passes**

Run: `flutter test`
Expected: all existing tests still green.

- [ ] **Step 6: Commit**

```bash
git add lib/features/scan/domain/scan_candidates.dart test/scan_candidates_test.dart
git commit -m "feat(voice): opt-in unit in candidate list; scan payload unchanged"
```

---

### Task 6: The repository

**Files:**
- Create: `lib/features/voice/data/voice_sale_repository.dart`
- Test: `test/voice_repository_error_mapping_test.dart`

- [ ] **Step 1: Write the failing tests**

Mirror `test/customer_repository_error_mapping_test.dart` — read it first for the
established shape. The mapping function is exposed for testing:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/core/error/failure.dart';
import 'package:mobile_app/features/voice/data/voice_sale_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('a function error becomes a friendly DatabaseFailure', () {
    final f = mapVoiceFailure(FunctionException(status: 502));
    expect(f, isA<DatabaseFailure>());
    expect(f.message, isNot(contains('502')));
  });

  test('a socket error becomes a NetworkFailure', () {
    expect(
      mapVoiceFailure(const SocketException('no route')),
      isA<NetworkFailure>(),
    );
  });

  test('anything else becomes an UnexpectedFailure', () {
    expect(mapVoiceFailure(Exception('boom')), isA<UnexpectedFailure>());
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/voice_repository_error_mapping_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '.../voice_sale_repository.dart'`

- [ ] **Step 3: Write the implementation**

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../domain/voice_parse_result.dart';

/// Maps transport errors to user-facing failures. Top-level so it is directly
/// unit-testable without constructing a Supabase client.
Failure mapVoiceFailure(Object e) {
  if (e is FunctionException) {
    return const DatabaseFailure(
      'Could not understand that right now. Please try again.',
    );
  }
  if (e is SocketException) {
    return const NetworkFailure('No internet connection. Please try again.');
  }
  return const UnexpectedFailure('Something went wrong. Please try again.');
}

/// Calls the `parse-sale` Edge Function, which holds the gateway key and turns
/// spoken audio into matched line items against the shop's own products.
class VoiceSaleRepository {
  VoiceSaleRepository(this._client);

  final SupabaseClient _client;

  Future<Result<VoiceParseResult>> parse({
    required Uint8List audioBytes,
    required String audioMime,
    required List<Map<String, dynamic>> candidates,
  }) async {
    try {
      final res = await _client.functions.invoke(
        'parse-sale',
        body: {
          'audio_base64': base64Encode(audioBytes),
          'audio_mime': audioMime,
          'candidates': candidates,
        },
      );
      final data = res.data;
      final map = data is String ? jsonDecode(data) : data;
      return Result.success(
        VoiceParseResult.fromJson(Map<String, dynamic>.from(map as Map)),
      );
    } catch (e) {
      return Result.failure(mapVoiceFailure(e));
    }
  }
}

final voiceSaleRepositoryProvider = Provider<VoiceSaleRepository>((ref) {
  return VoiceSaleRepository(ref.watch(supabaseClientProvider));
});
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/voice_repository_error_mapping_test.dart`
Expected: `+3: All tests passed!`

If `FunctionException`'s constructor signature differs, adjust the test to match the
installed `supabase_flutter` version — the assertion (friendly message, right Failure
type) is what matters.

- [ ] **Step 5: Commit**

```bash
git add lib/features/voice/data/voice_sale_repository.dart test/voice_repository_error_mapping_test.dart
git commit -m "feat(voice): repository over the parse-sale function"
```

---

### Task 7: Stub Edge Function (unblocks the app before the real one exists)

**Files:**
- Create: `supabase/functions/parse-sale/index.ts`

- [ ] **Step 1: Write the stub**

```ts
// Supabase Edge Function: parse-sale (STUB)
// Returns a canned response so the Flutter side can be built and tested before
// the gateway wiring lands. Replaced wholesale in Task 11.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

Deno.serve(async (req) => {
  const body = await req.json().catch(() => null);
  if (!body?.audio_base64 || !Array.isArray(body.candidates)) {
    return new Response(
      JSON.stringify({ error: "audio_base64 and candidates are required" }),
      { status: 400, headers: { "Content-Type": "application/json" } },
    );
  }
  const first = body.candidates[0]?.id ?? null;
  return new Response(
    JSON.stringify({
      heard_text: "sold 2 pepsi",
      items: first
        ? [{ heard: "pepsi", quantity: 2, unit_heard: null,
             matches: [{ product_id: first, confidence: 0.93 }] }]
        : [],
    }),
    { status: 200, headers: { "Content-Type": "application/json" } },
  );
});
```

- [ ] **Step 2: Deploy it**

Run: `supabase functions deploy parse-sale`
Expected: `Deployed Function parse-sale`

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/parse-sale/index.ts
git commit -m "feat(voice): stub parse-sale function"
```

---

### Task 8: Audio capture (MEMBER C seam)

**Files:**
- Create: `lib/features/voice/data/audio_recorder.dart`
- Modify: `pubspec.yaml`, `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist`

- [ ] **Step 1: Add the package**

Run: `flutter pub add record`
Expected: `pubspec.yaml` gains `record:` with the current version resolved by pub — do not
hand-write a version.

- [ ] **Step 2: Add the platform permissions**

In `android/app/src/main/AndroidManifest.xml`, above `<application>`:

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
```

In `ios/Runner/Info.plist`, inside the top-level `<dict>`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Used to record what you sold so it can be added to your cart.</string>
```

- [ ] **Step 3: Write the recorder**

```dart
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

/// MEMBER C seam: microphone capture. Kept behind this tiny interface so a
/// richer plugin can replace it without touching the controller or UI.
abstract class AudioRecorderPort {
  /// Whether the user granted microphone access.
  Future<bool> hasPermission();

  /// Begin capturing. Throws if permission was refused.
  Future<void> start();

  /// Stop and return the recording, or null if nothing was captured.
  Future<({Uint8List bytes, String mime})?> stop();

  Future<void> dispose();
}

class RecordAudioRecorder implements AudioRecorderPort {
  final _recorder = AudioRecorder();

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> start() =>
      _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: '');

  @override
  Future<({Uint8List bytes, String mime})?> stop() async {
    final path = await _recorder.stop();
    if (path == null) return null;
    final bytes = await _readFile(path);
    if (bytes == null || bytes.isEmpty) return null;
    return (bytes: bytes, mime: 'audio/m4a');
  }

  @override
  Future<void> dispose() async => _recorder.dispose();
}
```

Add a `_readFile` helper using `dart:io` `File(path).readAsBytes()`, returning null when the
file is missing. On web `record` returns a blob URL — out of scope; this app ships mobile.

Consult the `record` package README for the exact `start()` signature in the installed
version (it has changed across majors); the surface this app needs is
`hasPermission / start / stop / dispose`.

```dart
final audioRecorderProvider = Provider<AudioRecorderPort>((ref) {
  final recorder = RecordAudioRecorder();
  ref.onDispose(recorder.dispose);
  return recorder;
});
```

- [ ] **Step 4: Verify it compiles**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/features/voice/data/audio_recorder.dart \
  android/app/src/main/AndroidManifest.xml ios/Runner/Info.plist
git commit -m "feat(voice): microphone capture behind a Member C seam"
```

---

### Task 9: The controller

**Files:**
- Create: `lib/features/voice/presentation/voice_controller.dart`
- Test: `test/voice_controller_test.dart`

- [ ] **Step 1: Write the failing test**

Follow the fake-repository pattern already used in `test/widgets/cart_screen_test.dart`
(override the provider with a fake). The behaviours to pin down:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/voice/domain/voice_line.dart';
import 'package:mobile_app/features/voice/domain/voice_parse_result.dart';

void main() {
  test('a parsed result becomes reviewable lines', () {
    final lines = buildVoiceLines(VoiceParseResult(
      heardText: 'sold 2 pepsi',
      items: [
        VoiceItem(
          heard: 'pepsi', quantity: 2, quantityAssumed: false,
          matches: const [VoiceMatch(productId: 'p1', confidence: 0.93)],
        ),
      ],
    ));
    expect(lines.single.chosenProductId, 'p1');
    expect(canAddToCart(lines), isTrue);
  });
}
```

The controller itself holds `VoiceSaleState`:

```dart
enum VoicePhase { idle, recording, thinking, reviewing, error }
```

- [ ] **Step 2: Write the controller**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../inventory/presentation/inventory_controller.dart';
import '../../scan/domain/scan_candidates.dart';
import '../data/audio_recorder.dart';
import '../data/voice_sale_repository.dart';
import '../domain/voice_line.dart';

enum VoicePhase { idle, recording, thinking, reviewing, error }

class VoiceSaleState {
  const VoiceSaleState({
    this.phase = VoicePhase.idle,
    this.heardText,
    this.lines = const <VoiceLine>[],
    this.errorMessage,
  });

  final VoicePhase phase;
  final String? heardText;
  final List<VoiceLine> lines;
  final String? errorMessage;

  bool get canAdd => canAddToCart(lines);

  VoiceSaleState copyWith({
    VoicePhase? phase,
    String? heardText,
    List<VoiceLine>? lines,
    String? errorMessage,
  }) => VoiceSaleState(
    phase: phase ?? this.phase,
    heardText: heardText ?? this.heardText,
    lines: lines ?? this.lines,
    errorMessage: errorMessage,
  );
}

class VoiceController extends Notifier<VoiceSaleState> {
  @override
  VoiceSaleState build() => const VoiceSaleState();

  Future<void> startRecording() async {
    final recorder = ref.read(audioRecorderProvider);
    if (!await recorder.hasPermission()) {
      state = state.copyWith(
        phase: VoicePhase.error,
        errorMessage: 'micDenied',
      );
      return;
    }
    await recorder.start();
    state = state.copyWith(phase: VoicePhase.recording);
  }

  Future<void> stopAndParse() async {
    final recorder = ref.read(audioRecorderProvider);
    final clip = await recorder.stop();
    if (clip == null) {
      state = state.copyWith(phase: VoicePhase.error, errorMessage: 'noSpeech');
      return;
    }
    state = state.copyWith(phase: VoicePhase.thinking);

    final products = ref.read(productsStreamProvider).value ?? const [];
    final result = await ref.read(voiceSaleRepositoryProvider).parse(
      audioBytes: clip.bytes,
      audioMime: clip.mime,
      candidates: buildCandidates(products, includeUnit: true),
    );

    result.when(
      success: (parsed) {
        final lines = buildVoiceLines(parsed);
        state = state.copyWith(
          phase: lines.isEmpty ? VoicePhase.error : VoicePhase.reviewing,
          heardText: parsed.heardText,
          lines: lines,
          errorMessage: lines.isEmpty ? 'noMatch' : null,
        );
      },
      failure: (f) => state = state.copyWith(
        phase: VoicePhase.error,
        errorMessage: f.message,
      ),
    );
  }

  void choose(int index, String productId) => _replace(
    index,
    state.lines[index].chooseProduct(productId),
  );

  void setQuantity(int index, double quantity) => _replace(
    index,
    state.lines[index].withQuantity(quantity),
  );

  void removeLine(int index) =>
      state = state.copyWith(lines: removeLineAt(state.lines, index));

  void reset() => state = const VoiceSaleState();

  void _replace(int index, VoiceLine line) {
    final next = [...state.lines];
    next[index] = line;
    state = state.copyWith(lines: next);
  }
}

final voiceControllerProvider =
    NotifierProvider<VoiceController, VoiceSaleState>(VoiceController.new);
```

Adjust `Result.when` to the actual API in `lib/core/error/result.dart` — read it first and
match the existing call style used in `cart_checkout_controller.dart`. Likewise confirm the
products provider name in `lib/features/inventory/presentation/inventory_controller.dart`.

- [ ] **Step 3: Run the tests**

Run: `flutter test test/voice_controller_test.dart && flutter analyze`
Expected: tests pass, analyze clean.

- [ ] **Step 4: Commit**

```bash
git add lib/features/voice/presentation/voice_controller.dart test/voice_controller_test.dart
git commit -m "feat(voice): controller orchestrating record -> parse -> review"
```

---

### Task 10: Localization strings

**Files:**
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_bn.arb`

- [ ] **Step 1: Add the English strings**

```json
  "voice_title": "Speak a sale",
  "voice_hintIdle": "Hold and say what you sold",
  "voice_recording": "Listening…",
  "voice_thinking": "Working it out…",
  "voice_heard": "I heard",
  "voice_whichOne": "Which one?",
  "voice_notFound": "Not found",
  "voice_pick": "Pick",
  "voice_addToCart": "Add to cart",
  "voice_assumedQty": "Assumed 1 — check this",
  "voice_lowStock": "Only {count} in stock",
  "voice_errNoSpeech": "Didn't catch that. Try again.",
  "voice_errNoMatch": "Couldn't match anything you said.",
  "voice_errMicDenied": "Microphone access is off. Turn it on in Settings.",
  "voice_retry": "Try again"
```

`voice_lowStock` needs a placeholder block:

```json
  "@voice_lowStock": {
    "placeholders": { "count": { "type": "num", "format": "decimalPattern" } }
  }
```

- [ ] **Step 2: Add the Bengali strings**

Same keys in `app_bn.arb` (key sets must match exactly — `l10n_parity_test` enforces it):

```json
  "voice_title": "বিক্রির কথা বলুন",
  "voice_hintIdle": "চেপে ধরে বলুন কী বিক্রি হয়েছে",
  "voice_recording": "শুনছি…",
  "voice_thinking": "বুঝে নিচ্ছি…",
  "voice_heard": "আমি শুনেছি",
  "voice_whichOne": "কোনটি?",
  "voice_notFound": "পাওয়া যায়নি",
  "voice_pick": "বেছে নিন",
  "voice_addToCart": "কার্টে যোগ করুন",
  "voice_assumedQty": "১ ধরে নেওয়া হয়েছে — দেখে নিন",
  "voice_lowStock": "স্টকে আছে মাত্র {count}টি",
  "voice_errNoSpeech": "শুনতে পাইনি। আবার চেষ্টা করুন।",
  "voice_errNoMatch": "আপনার বলা কিছুই মেলাতে পারিনি।",
  "voice_errMicDenied": "মাইক্রোফোনের অনুমতি বন্ধ আছে। সেটিংসে গিয়ে চালু করুন।",
  "voice_retry": "আবার চেষ্টা করুন"
```

Include the same `@voice_lowStock` placeholder block.

- [ ] **Step 3: Generate and verify parity**

Run: `flutter gen-l10n && flutter test test/l10n_parity_test.dart`
Expected: generation succeeds, parity test passes.

- [ ] **Step 4: Commit**

```bash
git add lib/l10n/
git commit -m "feat(l10n): voice sale strings (en + bn)"
```

---

### Task 11: The review sheet

**Files:**
- Create: `lib/features/voice/presentation/voice_review_sheet.dart`
- Test: `test/widgets/voice_review_sheet_test.dart`

- [ ] **Step 1: Write the failing widget tests**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Add to cart is disabled while a line is unsettled', (t) async {
    // Pump the sheet with one resolved line and one ambiguous line.
    // Expect: the "Add to cart" ElevatedButton has a null onPressed.
  });

  testWidgets('choosing a candidate settles the line and enables the button', (t) async {
    // Pump with a single ambiguous line offering "Pepsi 500ml" / "Pepsi 1L".
    // Tap "Pepsi 1L". Expect the button becomes enabled.
  });

  testWidgets('removing a not-found line unblocks the rest', (t) async {
    // Pump with one resolved line + one not-found line; tap its remove icon.
    // Expect the button becomes enabled.
  });
}
```

Fill each body following the `ProviderScope(overrides: [...])` + `pumpWidget` pattern in
`test/widgets/cart_payment_toggle_test.dart` — read that file first and copy its harness,
overriding `voiceControllerProvider`'s dependencies rather than the controller itself.

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/widgets/voice_review_sheet_test.dart`
Expected: FAIL — sheet does not exist.

- [ ] **Step 3: Build the sheet**

A `ConsumerWidget` reading `voiceControllerProvider`. Structure, top to bottom:

1. Title `voice_title`; below it `voice_heard` + the transcript in a muted style.
2. `ListView.separated` over `state.lines`, each row:
   - resolved → leading ✅, the product name resolved from `productsStreamProvider` by
     `chosenProductId`, a quantity stepper calling `setQuantity`, and — when
     `quantityAssumed` — a small `voice_assumedQty` caption.
   - ambiguous → leading ⚠️, `"${line.heard}" × ${qty}`, `voice_whichOne`, then a `Wrap` of
     `ChoiceChip`s (one per `line.choices`, labelled with the resolved product name) calling
     `choose(index, productId)`.
   - notFound → leading ⚠️, the heard text, a `voice_pick` button opening the existing
     product picker (`lib/features/scan/presentation/product_picker_sheet.dart`) and a
     remove `IconButton` calling `removeLine(index)`.
   - When the chosen product's stock is below the line quantity, show `voice_lowStock` as a
     warning caption. This is advisory only — `record_sale_cart` remains the authority.
3. A footer `ElevatedButton` labelled `voice_addToCart` with
   `onPressed: state.canAdd ? _addToCart : null`.

`_addToCart` resolves each line's product from `productsStreamProvider`, calls
`ref.read(cartControllerProvider.notifier).addOrIncrement(product, line.quantity)`, calls
`reset()`, closes the sheet, and navigates to `/cart`.

Reuse `core/widgets/` components (`rounded_icon_tile`, `pressable`) to match the app's
visual language rather than introducing new styling.

- [ ] **Step 4: Run the tests**

Run: `flutter test test/widgets/voice_review_sheet_test.dart`
Expected: `+3: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/voice/presentation/voice_review_sheet.dart test/widgets/voice_review_sheet_test.dart
git commit -m "feat(voice): review sheet with inline disambiguation"
```

---

### Task 12: The mic sheet and entry point

**Files:**
- Create: `lib/features/voice/presentation/voice_sale_sheet.dart`
- Modify: the screen hosting the Scan entry point (find it with
  `grep -rn "visionScanEnabled" lib/`)

- [ ] **Step 1: Build the mic sheet**

A `ConsumerWidget` switching on `state.phase`:

- `idle` → large mic button + `voice_hintIdle`; press → `startRecording()`.
- `recording` → pulsing mic + `voice_recording` + a stop button → `stopAndParse()`.
- `thinking` → `voice_thinking` + the app's existing skeleton/loader.
- `reviewing` → show `VoiceReviewSheet`.
- `error` → the mapped message (`noSpeech` → `voice_errNoSpeech`, `noMatch` →
  `voice_errNoMatch`, `micDenied` → `voice_errMicDenied`, otherwise the failure's own
  message) + a `voice_retry` button calling `reset()`.

Honour `AppMotion.reduced(context)` for the pulse, as other animated widgets do.

- [ ] **Step 2: Add the flag-gated entry point**

Beside the existing Scan action, mirroring its conditional exactly:

```dart
if (FeatureFlags.voiceSaleEnabled)
  IconButton(
    icon: const Icon(Icons.mic_none),
    tooltip: context.l10n.voice_title,
    onPressed: () => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const VoiceSaleSheet(),
    ),
  ),
```

- [ ] **Step 3: Verify**

Run: `flutter analyze && flutter test`
Expected: analyze clean, all tests pass.

- [ ] **Step 4: Commit**

```bash
git add lib/features/voice/presentation/voice_sale_sheet.dart lib/features/
git commit -m "feat(voice): mic sheet and flag-gated entry point"
```

---

### Task 13: The real Edge Function

Replaces the Task 7 stub using the strategy chosen in Task 0.

**Files:**
- Modify: `supabase/functions/parse-sale/index.ts`

- [ ] **Step 1: Write the function**

```ts
// Supabase Edge Function: parse-sale
// Turns spoken audio into line items matched against the shop's own products.
// Two strategies behind one contract (see spec §5.1), chosen by VOICE_STRATEGY:
//   multimodal  -> one chat call with an input_audio part
//   transcribe  -> /audio/transcriptions first, then a text chat call
// Keys stay in Supabase secrets. MEMBER B owns prompt tuning.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

interface Candidate {
  id: string; name: string; brand?: string; variant?: string; unit?: string;
}

const BASE_URL = (Deno.env.get("FROG_BASE_URL") ?? "https://frogapi.app/v1")
  .replace(/\/+$/, "");
const API_KEY = Deno.env.get("FROG_API_KEY") ?? "";
// Model slugs retire -- keep them overridable rather than hardcoded.
const MODEL = Deno.env.get("VOICE_MODEL") ?? "Gemini-3.1-Pro";
const TRANSCRIBE_MODEL = Deno.env.get("VOICE_TRANSCRIBE_MODEL") ?? "whisper-1";
const STRATEGY = (Deno.env.get("VOICE_STRATEGY") ?? "multimodal").toLowerCase();

const instruction = (candidates: Candidate[]) =>
  `You turn a shopkeeper's spoken sentence into sale line items.
The speech may be English, Bengali, or a mix of both.

CRITICAL RULE -- quantity and size are DIFFERENT fields, never merge them:
- Count words (piece, pcs, packet, টা, টি, পিস) give "quantity".
- Size words (500ml, 1 litre, kg, লিটার, কেজি) are part of "heard" and are used to
  pick the right product. A size must NEVER become the quantity.
  Example: "pepsi 1 litre" => quantity 1, heard "pepsi 1 litre" (the 1L product).
  Example: "2 pepsi" => quantity 2, heard "pepsi".

Match each item against the shop's product list below. If the speech does NOT
distinguish between two candidates (e.g. "pepsi" when both 500ml and 1L exist),
return BOTH with SIMILAR confidence. Do not guess a winner -- the app will ask
the user. Never invent a product_id that is not in the list.
If no count was spoken, omit "quantity".

Return ONLY minified JSON of this exact shape:
{"heard_text":string,"items":[{"heard":string,"quantity":number,"unit_heard":string|null,"matches":[{"product_id":"<id from the list>","confidence":<0..1>}]}]}
Product list: ${JSON.stringify(candidates)}`;

function extractJson(text: string): Record<string, unknown> {
  const cleaned = text.trim().replace(/^```json/i, "").replace(/```$/, "").trim();
  const start = cleaned.indexOf("{");
  const end = cleaned.lastIndexOf("}");
  return JSON.parse(start >= 0 ? cleaned.slice(start, end + 1) : cleaned);
}

async function chat(content: unknown): Promise<Record<string, unknown>> {
  // NOTE: no `temperature` -- some newer models reject temperature:0 outright.
  const res = await fetch(`${BASE_URL}/chat/completions`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${API_KEY}`,
    },
    body: JSON.stringify({ model: MODEL, messages: [{ role: "user", content }] }),
  });
  if (!res.ok) {
    const detail = await res.text().catch(() => "");
    throw new Error(`gateway ${res.status}: ${detail.slice(0, 300)}`);
  }
  const json = await res.json();
  return extractJson(json?.choices?.[0]?.message?.content ?? "{}");
}

async function transcribe(audioB64: string, mime: string): Promise<string> {
  const bytes = Uint8Array.from(atob(audioB64), (c) => c.charCodeAt(0));
  const form = new FormData();
  form.append("file", new Blob([bytes], { type: mime }), "audio.m4a");
  form.append("model", TRANSCRIBE_MODEL);
  const res = await fetch(`${BASE_URL}/audio/transcriptions`, {
    method: "POST",
    headers: { Authorization: `Bearer ${API_KEY}` },
    body: form,
  });
  if (!res.ok) {
    const detail = await res.text().catch(() => "");
    throw new Error(`transcribe ${res.status}: ${detail.slice(0, 300)}`);
  }
  return (await res.json())?.text ?? "";
}

async function parse(audioB64: string, mime: string, candidates: Candidate[]) {
  if (STRATEGY === "transcribe") {
    const text = await transcribe(audioB64, mime);
    if (!text.trim()) return { heard_text: "", items: [] };
    const raw = await chat(
      `${instruction(candidates)}\n\nThe shopkeeper said: "${text}"`,
    );
    return { ...raw, heard_text: raw.heard_text ?? text };
  }
  return await chat([
    { type: "text", text: instruction(candidates) },
    {
      type: "input_audio",
      input_audio: { data: audioB64, format: mime.split("/")[1] ?? "m4a" },
    },
  ]);
}

function normalize(raw: Record<string, unknown>, candidates: Candidate[]) {
  const ids = new Set(candidates.map((c) => c.id));
  const rawItems = Array.isArray(raw.items) ? raw.items : [];
  const items = rawItems.map((it: Record<string, unknown>) => {
    const matches = Array.isArray(it?.matches) ? it.matches : [];
    return {
      heard: typeof it?.heard === "string" ? it.heard : "",
      // Pass quantity through only when it is a real positive number; the app
      // defaults to 1 and flags it, rather than us inventing a bulk number.
      quantity: typeof it?.quantity === "number" && it.quantity > 0
        ? it.quantity
        : null,
      unit_heard: typeof it?.unit_heard === "string" ? it.unit_heard : null,
      matches: matches
        .filter((m: Record<string, unknown>) => ids.has(m?.product_id as string))
        .map((m: Record<string, unknown>) => ({
          product_id: m.product_id,
          confidence: Math.max(0, Math.min(1, Number(m.confidence) || 0)),
        })),
    };
  }).filter((it) => it.heard !== "" || it.matches.length > 0);
  return { heard_text: raw.heard_text ?? null, items };
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  let audioB64: unknown;
  let mime: unknown;
  let candidates: unknown;
  try {
    const body = await req.json();
    audioB64 = body.audio_base64;
    mime = body.audio_mime ?? "audio/m4a";
    candidates = body.candidates;
  } catch (_e) {
    return json({ error: "invalid JSON body" }, 400);
  }
  if (!audioB64 || !Array.isArray(candidates)) {
    return json({ error: "audio_base64 and candidates are required" }, 400);
  }
  try {
    const raw = await parse(
      audioB64 as string, mime as string, candidates as Candidate[],
    );
    return json(normalize(raw, candidates as Candidate[]), 200);
  } catch (e) {
    // Real failures return 5xx so the app shows retry instead of a misleading
    // "heard nothing". A genuine empty result is a 200 with items: [].
    console.error("parse-sale failed:", e);
    return json({ error: "parse failed" }, 502);
  }
});
```

- [ ] **Step 2: Set secrets and deploy**

```bash
supabase secrets set VOICE_STRATEGY=<from Task 0> VOICE_MODEL=<slug from Task 0>
supabase functions deploy parse-sale
```

- [ ] **Step 3: Smoke-test it**

```bash
curl -s -X POST "$SUPABASE_URL/functions/v1/parse-sale" \
  -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"audio_base64\":\"$(base64 -w0 sample.m4a)\",\"audio_mime\":\"audio/m4a\",\"candidates\":[{\"id\":\"p1\",\"name\":\"Pepsi 1L\",\"variant\":\"1L\"}]}"
```

Expected: 200 with `heard_text` and an `items` array.

- [ ] **Step 4: Commit**

```bash
git add supabase/functions/parse-sale/index.ts
git commit -m "feat(voice): real parse-sale function with dual audio strategy"
```

---

### Task 14: Manual verification and threshold calibration

**Files:**
- Modify: `lib/features/voice/domain/voice_decision.dart` (threshold constants only)

- [ ] **Step 1: Run on the physical S22**

```bash
flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... \
  --dart-define=VOICE_SALE_ENABLED=true
```

- [ ] **Step 2: Walk the scenarios**

Record the outcome of each:

| Scenario | Expected |
|---|---|
| "sold 2 Pepsi and 3 chips" (English) | both lines ✅, correct quantities |
| Same sentence in Bengali | same result |
| Mixed English/Bengali | same result |
| "pepsi 1 piece" with 500ml AND 1L stocked | ⚠️ asks which one |
| "pepsi 1 litre" with both stocked | ✅ picks 1L, quantity 1 |
| An item not in inventory | ⚠️ not found, removable |
| Airplane mode | offline message, nothing staged |
| Mic permission denied | the mic-denied message |
| Quantity above stock | warning at review; checkout still rejects atomically |

- [ ] **Step 3: Calibrate**

If clear commands are being asked about too often, lower `strong` (e.g. 0.75). If wrong
products are being auto-picked, raise `margin` (e.g. 0.20). Change **only** the constants in
`VoiceThresholds` and re-run `flutter test` — the decision tests must still pass.

- [ ] **Step 4: Commit**

```bash
git add lib/features/voice/domain/voice_decision.dart
git commit -m "chore(voice): calibrate thresholds against real speech"
```

---

## Definition of Done

- [ ] `flutter analyze` clean
- [ ] `flutter test` fully green
- [ ] Feature invisible with the flag off; a build without `VOICE_SALE_ENABLED=true` behaves exactly as before
- [ ] Every scenario in Task 14 verified on a physical device
- [ ] No API key committed anywhere in the repo
- [ ] `record_sale_cart` unchanged — voice only stages into the cart
