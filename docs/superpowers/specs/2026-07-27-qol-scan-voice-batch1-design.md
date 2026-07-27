# QoL Batch 1 — Scan & Voice — Design

**Date:** 2026-07-27
**Branch:** `feat/qol-scan-voice`
**Status:** Approved design, pending spec review

Three small, independent quality-of-life improvements to the scan and voice
sale flows. Each is shippable on its own; together they make the AI features
feel trustworthy (you can *see* what it understood) and forgiving (mistakes are
one tap to reverse).

Scope guard (YAGNI): **no** undo history (only the single last action), **no**
re-parse of scan images, **no** per-item voice chip text editing (a separate
future idea). Torch/flashlight is Member C's plugin and is out of this batch.

---

## Feature 1 — Scan "what I read"

**Problem:** The `recognize-product` Edge Function already returns
`read_brand` / `read_name` / `read_size`, and `RecognitionResult` parses them,
but `ScanOutcome` drops them — so the shopkeeper never sees *why* something
matched (or didn't). The scan is a black box.

**Change:**
1. Add `readBrand`, `readName`, `readSize` (all `String?`) to `ScanOutcome`
   (`lib/features/scan/presentation/scan_controller.dart`) and populate them
   from `recognition` in `captureAndRecognize`.
2. Add a display helper that composes the non-null parts into one label,
   joined by ` · ` (e.g. `Pepsi · 1L`, or `Pepsi · Cola · 500ml`). If every
   part is null/empty, the label is `null` and nothing is shown.
3. Surface the label in two places:
   - **Add-to-cart confirmation sheet** (`showAddToCartSheet`): add an
     **optional** `String? readLabel` parameter. When non-null, render a small
     caption under the product name (`Read: Pepsi · 1L`). Manual adds from
     inventory pass nothing → visually unchanged.
   - **No-match / chooser picker** (`showProductPickerSheet` path in
     `scan_screen.dart`): when a read label exists, show it in/under the sheet
     title (`Saw: Pepsi 1L — pick the right product`).
4. l10n: new key `scan_read` = `"Read: {details}"` (placeholder `details`),
   added to `app_en.arb` and `app_bn.arb` (+ regenerated localizations).

**Data flow:**
`recognize-product` JSON → `RecognitionResult.read*` → `ScanOutcome.read*` →
scan screen composes label → passed to sheet / picker as display-only text.

**Edge cases:** all read fields null → no caption (label is null). Long label →
single line, ellipsis (matches existing sheet text styling).

---

## Feature 2 — Voice: edit transcript, re-run the AI

**Problem:** The review sheet shows `Heard: "<transcript>"` as static text
(`voice_review_sheet.dart:89`). If Gemini misheard one word (common for
Bengali/mixed speech), the shopkeeper's only recovery is to re-record the whole
sentence.

**Change:**
1. Make the "Heard" line tappable → opens an edit affordance (a `TextField`
   prefilled with the current transcript; inline expand or a small edit
   dialog — implementation detail left to the plan).
2. On submit, a new `VoiceController` method (e.g. `reparseFromText(String)`)
   calls the existing voice repository's parse against the **transcript path**
   of `parse-sale` (the Edge Function already accepts `transcript` instead of
   `audio_base64`), then rebuilds `heardText` + `items` and returns the sheet to
   its `reviewing` state.
3. While the re-parse call is in flight, the sheet shows a brief inline
   "re-checking…" spinner (reuse the existing loading/phase state).

**Data flow:**
edited text → `VoiceController.reparseFromText` → voice repository
(`parse-sale` text path) → `VoiceParseResult` → controller state (`heardText`,
`items`) → review sheet rebuilds.

**Edge cases:**
- Empty / whitespace-only submit → no-op (keep current state, close editor).
- Unchanged text → still allowed; harmless re-parse (or short-circuit if
  identical — plan's choice).
- Re-parse failure (bad key, outage) → existing error/retry handling; the
  previous review state is preserved so nothing is lost.

**Reuses existing backend** — no Edge Function changes; the text path already
exists and is deployed.

---

## Feature 3 — Undo last add (scan **and** voice)

**Problem:** A wrong scan or a misheard voice sale silently lands in the cart;
fixing it means navigating to the Cart screen to delete the line.

**Approach chosen:** snapshot-and-restore (over tracking added line IDs).
The cart is a plain `List<CartLine>`; capturing it before an action and
restoring it on Undo reverses the *whole* action exactly — including cases
where the add merged into an existing line — with no per-line bookkeeping.

**Change:**
1. Add `void restore(List<CartLine> snapshot)` to `CartController`
   (`state = snapshot;`).
2. **Scan** (`scan_screen.dart._confirmAndAdd`): read the cart snapshot
   *before* calling `showAddToCartSheet`. On a successful add (`added == true`),
   the existing "Added <name>" snackbar gains an **Undo** `SnackBarAction` that
   calls `restore(snapshot)`.
3. **Voice** (`voice_review_sheet.dart`): snapshot the cart before the sentence's
   lines are committed to it; show the same Undo snackbar (all of the sentence's
   lines are reversed together — "undo the whole action").
4. l10n: new key `common_undo` = `"Undo"` (en + bn).

**Undo scope:** the single most recent add action only. No multi-step undo
stack. A second action replaces what "last add" means.

**Edge cases:**
- Snackbar dismissed/expires without tapping Undo → nothing happens (add stays).
- Cart changed by another action before Undo is tapped → restore still sets the
  cart to the captured snapshot (documented behavior: Undo reverts to the
  pre-action cart). Acceptable for the single-last-action model; snackbar is
  short-lived (~4–5s) so the window is small.

---

## Testing

- **Unit:** `CartController.restore` round-trip (add → snapshot pre-state →
  mutate → restore → equals snapshot).
- **Widget (scan):** confirmation sheet renders the `readLabel` caption when
  provided and omits it when null; no-match picker shows the "Saw:" label.
- **Widget (undo):** after a scan add, the snackbar's Undo action empties the
  cart back to its pre-add snapshot.
- **Widget (voice):** tapping "Heard" opens the editor; submitting edited text
  triggers `reparseFromText` (fake voice repository, as in existing voice
  tests) and the item list updates to the re-parsed result.
- Full `flutter test` suite stays green after each feature; `flutter analyze`
  clean (scoped paths only — never `dart format .` repo-wide).

## Localization keys added

| Key | English | Notes |
|-----|---------|-------|
| `scan_read` | `Read: {details}` | placeholder `details` (String) |
| `common_undo` | `Undo` | snackbar action label |

Bengali (`app_bn.arb`) values added alongside; localizations regenerated.

## Files touched (anticipated)

- `lib/features/scan/presentation/scan_controller.dart` (ScanOutcome + read fields)
- `lib/features/scan/presentation/scan_screen.dart` (label + undo snapshot)
- `lib/features/cart/presentation/add_to_cart_sheet.dart` (optional readLabel param)
- `lib/features/cart/presentation/cart_controller.dart` (restore method)
- `lib/features/scan/presentation/product_picker_sheet.dart` (show the read label near the title; exact widget mechanism decided in the plan)
- `lib/features/voice/presentation/voice_review_sheet.dart` (editable transcript + undo)
- `lib/features/voice/presentation/voice_controller.dart` (reparseFromText)
- `lib/l10n/app_en.arb`, `lib/l10n/app_bn.arb` (+ regenerated)
- Tests under `test/` mirroring the above.
