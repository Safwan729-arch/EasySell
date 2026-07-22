# Voice Sale Assistant (speak a sale → cart) — Design

**Date:** 2026-07-22
**Feature owner:** Member A (Flutter + Supabase), with Member B seam (intent prompt) and Member C seam (speech capture)
**Status:** Approved for planning — **amended 2026-07-22, see §0**
**Branch:** `feat/voice-sale` (new, from `feat/customer-credit`) · **Rollback tag:** `checkpoint-pre-voice-sale`

## 0. Amendment — on-device speech-to-text (supersedes the "audio to cloud" approach)

The original design (§2, §3, §5) sent recorded **audio** to the cloud, on the
premise the Frog gateway could transcribe it. The Task 0 spike (a `probe-audio`
Edge Function, run 2026-07-22) proved it **cannot**: `/chat/completions` rejects
an `input_audio` content block (`400: "Content blocks are expected to be either
text or image_url type"`, gateway-level, any model) and there is no
`/audio/transcriptions` endpoint (`404`).

**Revised approach (user-approved):** the phone does speech-to-text **on-device**
(Flutter `speech_to_text` plugin); only the resulting **transcript text** is sent
to `parse-sale`, which does the understanding + closed-set matching against the
shop's products. The pipeline is still *speak → cart → review → confirm*.

**What this changes vs the body of this spec:**
- `parse-sale` request is `{ transcript, candidates }`, not `{ audio_base64, … }`.
  Its **response shape is unchanged**, so all the client domain logic (§4, and the
  parser/decision/review-line layer) is reused as-is.
- The Member C seam is a **speech recognizer** (`speech_to_text`), not an audio
  recorder. It yields a transcript string, not audio bytes.
- `VoiceSaleRepository.parse` takes a `transcript` string, not audio bytes.
- No `VOICE_STRATEGY` / transcription-fallback machinery — there is one text call.
- **Trade-off accepted:** transcription quality now depends on the device's
  speech engine. On the S22 (online) English + Bengali are acceptable for the MVP;
  a dedicated cloud transcriber (e.g. Whisper) remains a future upgrade that would
  change only the ears stage, not the app.

The sections below are retained for history; where they say "audio", read
"transcript" per this amendment.

## 1. Goal

Let a shopkeeper **say what they sold** and have the app stage it for checkout:

> "sold 2 Pepsi and 3 chips" → cart is filled with those lines → review → confirm → sold.

The spoken audio is matched **against the shop's own product list** (closed-set), exactly
as the vision scan matches a photo. The result is always reviewed by a human before any
stock moves.

This is the camera-scan feature with a microphone swapped in for the camera. Wherever a
decision has already been made for scan, this spec follows it rather than inventing a
second pattern.

## 2. Decisions taken (from brainstorming)

| Question | Decision |
|---|---|
| Languages | **English + Bengali**, including mixing them mid-sentence |
| Where the "listening" happens | **Cloud** — audio goes to the model; the phone only records |
| Items per command | **Multiple** ("2 Pepsi and 3 chips") |
| Landing surface | The **existing cart**, not a direct single sale |
| Ambiguous product | **Ask the user** — never auto-pick a coin-flip |
| Auto-commit | **Never.** Human confirms before `record_sale_cart` |

**Why cloud listening:** on-device speech-to-text is weak at Bengali, which would quietly
break the "speak any language" property. Sending audio to the model is what makes
multilingual input real.

## 3. Architecture

```
[Flutter]                                  [Supabase Edge Function: parse-sale]
 🎤 Voice button (flag-gated)
   → record audio (MEMBER C seam)          Frog gateway (OpenAI-compatible)
   → VoiceSaleRepository.parse( ───────►     audio → transcript → intent + closed-set match
        audioBytes, candidates[])            (internally 1 or 2 calls; see §5)
   ◄────────  VoiceParseResult JSON  ──────   { heard_text, items[] }
   → per-line decision (pure, tunable thresholds)
   → Voice Review sheet: resolve ⚠️ lines
   → cartController.addOrIncrement(...) per resolved line
   → existing cart → checkout → record_sale_cart   (UNCHANGED)
```

- **Additive only.** No existing sell/inventory/cart code is modified destructively. Voice
  *adds* lines to the cart through `CartController`'s existing public API.
- **Feature-flagged.** `FeatureFlags.voiceSaleEnabled` (default `false`), mirroring
  `visionScanEnabled`. Flag off ⇒ the feature is invisible and zero-risk.
- **Keys stay server-side** in Supabase secrets. The app never holds a model key.

## 4. The critical correctness rule: ask when it's a coin-flip

A shop stocking **Pepsi 500ml** and **Pepsi 1L** hears "pepsi 1 piece sold". There is not
enough information in that sentence to choose. A confident guess here silently sells the
wrong stock and corrupts inventory, so the rule is: **when the words don't narrow it down,
the app asks.**

Mechanically this reuses the scan feature's two-part test — top confidence **and** the
margin over the runner-up:

| Spoken | Scores | Verdict | UI |
|---|---|---|---|
| "pepsi 1 piece" | 500ml `0.55`, 1L `0.52` | too close | ⚠️ ask |
| "pepsi 1 litre" | 1L `0.95`, 500ml `0.20` | clear winner | ✅ auto |
| "pepsi half litre" | 500ml `0.93`, 1L `0.22` | clear winner | ✅ auto |

Thresholds mirror `ScanThresholds` (`strong 0.80`, `margin 0.15`, `ambiguous 0.50`) and are
calibrated in Phase 3.

### 4.1 Quantity vs size — a hard contract rule

"1 **piece**" is a *quantity*; "1 **litre**" is a *size*. They are near-identical to a
language model and confusing them is the nastiest available bug:

- ❌ "1 litre" read as *quantity 1, unit litre* → wrong Pepsi selected
- ❌ "1 piece" read as a *size* → hunts for a nonexistent "1 piece" variant

The prompt and the response contract therefore keep them in **separate fields**, and this
is stated explicitly to the model:

- Count words (`piece`, `pcs`, `packet`, `টা`, `টি`, `পিস`) → `quantity`
- Size words (`500ml`, `1 litre`, `kg`, `লিটার`, `কেজি`) → part of `heard`, used for
  product matching, **never** folded into `quantity`

Products already carry `variant` and `unit`, so the model has real sizes to match against
instead of inventing them. Covered by unit tests (§9).

## 5. Edge Function contract (Member A ↔ Member B seam)

`POST /functions/v1/parse-sale` (authenticated with the caller's Supabase JWT).

**Request**
```jsonc
{
  "audio_base64": "<audio bytes, base64>",
  "audio_mime": "audio/m4a",
  "candidates": [
    { "id": "uuid", "name": "Pepsi 1L", "brand": "Pepsi", "variant": "1L", "unit": "pcs" }
  ]
}
```
Candidates are built by the existing `buildCandidates` helper, extended with an **optional
`includeUnit` parameter defaulting to `false`**. Scan's call site is therefore byte-for-byte
unchanged (its prompt payload does not gain a field), while voice opts in. The candidate
*list shape* is deliberately shared — both AI features match against the same closed set —
even though their result types are separate (§6).

**Response**
```jsonc
{
  "heard_text": "sold 2 pepsi and 3 chips",   // full transcript, shown to the user
  "items": [
    {
      "heard": "pepsi",                        // the fragment this line came from
      "quantity": 2,
      "unit_heard": "piece",                   // nullable; never merged into quantity
      "matches": [ { "product_id": "uuid", "confidence": 0.55 } ]  // ranked, may be empty
    }
  ]
}
```

**Server-side normalization** (same discipline as `recognize-product`):
- Drop any `product_id` not in the submitted candidate list (never let the model invent ids).
- Clamp confidences to `[0,1]`; drop items with `quantity <= 0` or non-numeric quantity.
- Genuine failures (bad key, gateway outage, unparseable reply) → **502**, so the app shows
  its retry state instead of a misleading "heard nothing".
- A real "nothing recognized" is a **200** with an empty `items` array.

### 5.1 Audio transport — the one real unknown ⚠️

Frog is an OpenAI-compatible `/chat/completions` gateway. Image input is proven (scan works);
**audio input through it is unverified.** This is the highest technical risk in the feature,
so `parse-sale` is designed with two internal strategies behind the same external contract:

- **Strategy 1 (preferred, one call):** audio sent as an `input_audio` content part to a
  multimodal model; it transcribes *and* extracts intent in one shot.
- **Strategy 2 (fallback, two calls):** audio → a transcription endpoint
  (`/audio/transcriptions`) → transcript text → the existing chat model for intent +
  closed-set matching.

Strategy is chosen by a `VOICE_STRATEGY` secret. **The app contract is identical either way**,
so this risk cannot leak into the Flutter layer. Phase 0 is a spike that determines which
strategy the deployment uses.

**Known gateway gotchas** (carried over from scan): model slugs retire — keep them in
`VOICE_MODEL` / transcription-model secrets rather than hardcoded; and some newer models
reject `temperature: 0`, so omit it or make it configurable rather than copying it blindly.

## 6. Flutter components (all new files — additive)

```
lib/features/voice/
  data/
    voice_sale_repository.dart      # invokes 'parse-sale'; returns Result<VoiceParseResult>
    audio_recorder.dart             # MEMBER C seam: start/stop capture -> bytes + mime
  domain/
    voice_parse_result.dart         # VoiceParseResult, VoiceItem, VoiceMatch (plain Dart)
    voice_line.dart                 # VoiceLine: heard + quantity + status + chosen product
    voice_decision.dart             # PURE: matches -> resolved | ambiguous | notFound
  presentation/
    voice_controller.dart           # AsyncNotifier: record -> parse -> build lines
    voice_sale_sheet.dart           # mic UI: idle / recording / thinking / error
    voice_review_sheet.dart         # the review + disambiguation surface
lib/core/config/feature_flags.dart  # + voiceSaleEnabled
```

**Deliberate decoupling:** `VoiceMatch` mirrors scan's `ProductMatch` rather than importing
it, so the two features' *result* types can evolve independently (voice results carry
quantity and a heard fragment; scan results never will). If a third consumer appears,
promote a shared type then (rule of three) — not now. The candidate-list *input* helper is
shared, since both features match against the identical closed set (§5).

**`voice_decision.dart` is pure** (no I/O, no Flutter) so the coin-flip rule from §4 is
directly unit-testable, exactly like `decideScanAction`.

### 6.1 The Voice Review sheet

```
┌───────────────────────────────────────┐
│  I heard: "sold 2 pepsi and 3 chips"   │  ← transcript, so a mishear is obvious
│  ─────────────────────────────────────│
│  ✅ Pepsi 500ml            ×2     ✎    │  resolved, quantity editable
│  ⚠️  "pepsi" ×1 — which one?           │  ambiguous → inline choice chips
│      [ Pepsi 500ml ] [ Pepsi 1L ]      │
│  ⚠️  "biscuit" — not found  [pick] [✕] │  unmatched → pick manually or drop
│  ─────────────────────────────────────│
│           [ Add to cart ]              │  disabled until no ⚠️ remains
└───────────────────────────────────────┘
```

- Disambiguation is **inline per row**, not a stack of dialogs — a 4-item command must not
  fire 4 modals.
- **"Add to cart" stays disabled while any line is unresolved.** Unresolved lines are
  resolved or removed; they never silently vanish.
- Lines exceeding available stock show a soft warning via
  `CartController.remainingStockFor`. It is only a warning — `record_sale_cart` remains the
  authority and rejects genuine oversell atomically.
- On confirm, each resolved line calls `cartController.addOrIncrement(product, qty)`; the
  user lands on the normal cart and checks out as usual.

### 6.2 Entry point

A flag-gated 🎤 button beside the existing Scan entry in the selling surface, so the two AI
capture paths sit together. Tap-to-record (press, speak, stop) — **no always-on listening**
(battery, privacy, and needless complexity).

## 7. Localization

All new strings in **both** `lib/l10n/app_en.arb` and `lib/l10n/app_bn.arb` (parity enforced
by `l10n_parity_test`): mic states (idle/recording/thinking), "I heard", "which one?",
"not found", "Add to cart", stock warning, and every error message in §8.

## 8. Error handling

`Result<T>` / `Failure` throughout; user-friendly messages, never raw errors.

| Case | Behaviour |
|---|---|
| Offline | `NetworkFailure` fast-fail + the existing offline banner; nothing staged |
| Mic permission denied | Explain and offer settings; feature no-ops (MEMBER C seam) |
| Recording too short / silent | "Didn't catch that — try again", re-record without losing the sheet |
| Model heard speech but no products matched | 200 with empty items → "Couldn't match anything you said", show transcript, offer manual add |
| Some items matched, some not | Partial success — matched lines ✅, others ⚠️ for the user to resolve |
| Gateway failure / 502 | "Couldn't understand right now. Please try again." + retry |
| Malformed model JSON | Normalized away server-side; worst case → 502 path above |
| Quantity absent for an item | Default to 1 and mark the line for review (never assume a bulk number) |
| Insufficient stock | Soft warning at review; hard atomic rejection at `record_sale_cart` |

## 9. Testing

**Pure unit (no network, no Flutter):**
- `voice_decision` — resolved / ambiguous / notFound across confidence + margin cases,
  including the Pepsi 500ml-vs-1L coin-flip.
- JSON parsing of `VoiceParseResult` — well-formed, empty items, unknown ids, missing
  fields, malformed payloads.
- **Quantity vs size separation** (§4.1) — "1 piece" yields `quantity: 1` and never a size;
  "1 litre" is matched as size and never becomes `quantity: 1` of a wrong variant.

**Controller/widget:**
- "Add to cart" disabled while any line is ⚠️; enabled once all are resolved or removed.
- Choosing a candidate on an ambiguous row flips it to ✅.
- Confirm pushes exactly the resolved lines into `CartController`.

**Manual (physical S22):** English command; Bengali command; mixed-language command;
the ambiguous Pepsi case; an item not in inventory; airplane mode; mic permission denied.

## 10. Phasing

0. **Spike (gating):** verify whether Frog accepts audio in `/chat/completions`; pick
   Strategy 1 or 2 (§5.1). Nothing else proceeds until this is answered.
1. **Contract + skeleton (flag off):** domain models, repository, pure decision logic +
   full unit tests, stub Edge Function returning a canned response. App compiles, tests
   green, feature invisible.
2. **Real function + UI:** implement the chosen strategy, mic capture (Member C seam),
   voice sheet, review sheet, flag-gated entry point.
3. **Calibrate:** tune thresholds on real speech; verify Bengali quality; decide whether the
   ask-rate is tolerable.

Each phase is independently shippable; Phase 1 lands entirely behind the flag.

## 11. Out of scope (explicitly)

- **Always-on / wake-word listening.** Tap-to-record only.
- **Voice for anything but sales** — no restock, price edits, or queries by voice yet.
- **Remembering "when I say pepsi I mean 500ml."** Genuinely useful, but it can learn a
  wrong default and then repeat it silently. Revisit only if the ask-rate proves annoying.
- **Offline voice.** Online assumed, same as scan.
- **Editing a sale by voice**, voice-driven customer/khata selection, and voice feedback
  (text-to-speech replies).
- **Replacing the scan feature.** The two coexist.

## 12. Files touched

| File | Change |
|---|---|
| `supabase/functions/parse-sale/index.ts` | new: audio → intent + closed-set match |
| `lib/features/voice/**` | new: 2 data, 3 domain, 3 presentation files |
| `lib/core/config/feature_flags.dart` | + `voiceSaleEnabled` |
| `lib/features/scan/domain/scan_candidates.dart` | `buildCandidates` gains optional `includeUnit` (default `false`; scan payload unchanged) |
| selling surface (scan entry point host) | + flag-gated 🎤 button |
| `lib/l10n/app_en.arb`, `lib/l10n/app_bn.arb` | new strings (en + bn) |
| `pubspec.yaml` | + an audio recording package (MEMBER C seam) |
| `test/**` | decision, parsing, quantity-vs-size, review-sheet gating tests |
