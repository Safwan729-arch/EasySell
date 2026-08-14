# Vision Product Scan (Gemini/OpenAI closed-set match) — Design

**Date:** 2026-07-04
**Feature owner:** Member A (Flutter + Supabase), with Member B seam (vision prompt) and Member C seam (camera)
**Rebuilt on 2026-08-10 by [[2026-08-10-fast-scan-session-design]]** — the serial
capture→wait→sheet loop became a session with a live viewfinder and background
recognition. The closed-set matching designed here is unchanged and still the
core of it; what changed is the flow around it. That work also took over the
Member C camera seam (`image_picker` → the `camera` package) with the user's
consent, and revisited but did not overturn the barcode decision in §10.
**Status:** Approved for planning
**Branch:** `feat/vision-product-scan` · **Rollback tag:** `checkpoint-pre-vision-scan`

## 1. Goal

Add a **"Scan Product"** flow to the selling workflow: the shopkeeper photographs an
item, a **vision LLM identifies it by matching against the shop's own product list**
(closed-set multiple-choice), and the app opens the existing **Sell confirmation
sheet** pre-filled with the matched product. Loose/unbranded items fall back to
**manual selection**.

Barcodes are explicitly out of scope (unrealistic for small/medium shops). No image
embeddings, pgvector, or product-photo storage are required for this feature — the
match is label-text → product name/brand/variant.

## 2. Non-negotiable constraints (from the user)

1. **Safe rollback.** The feature is fully isolated and reversible:
   - Known-good state tagged `checkpoint-pre-vision-scan`.
   - All work on branch `feat/vision-product-scan`.
   - Feature gated behind an **on/off flag** so it can be disabled without reverting.
   - **Additive only** — no existing sell/inventory code is modified destructively;
     the scan flow reuses `showSaleConfirmationSheet` without changing it.
2. **Dual provider (OpenAI + Gemini), later Gemini-only.** The vision call sits behind
   one interface with two interchangeable implementations, chosen by config. Switching
   to Gemini-only is a one-line config change.
3. **Keys stay server-side.** Chosen approach: a **Supabase Edge Function** holds the
   API keys as secrets; the Flutter app never embeds them.

## 3. Architecture

```
[Flutter]                                  [Supabase Edge Function: recognize-product]
 Scan button
   → capture photo (image_picker)          VisionRecognizer (provider switch via env)
   → VisionScanRepository.recognize(  ─────►   ├─ GeminiRecognizer  (GEMINI_API_KEY)
        image, candidates[])                   └─ OpenAiRecognizer  (OPENAI_API_KEY)
   ◄──────────  RecognitionResult JSON  ─────   image + candidate list → matches JSON
   → scanController decides:
       strong  → showSaleConfirmationSheet(product)     (existing, unchanged)
       several → "Did you mean?" dialog → sheet
       none    → manual pick / add new
```

- **Provider abstraction lives in the Edge Function** (Deno/TypeScript). The Flutter
  side is provider-agnostic — it calls one function and gets a normalized result.
- **Candidate list** = the shop's products (`id, name, brand, variant`), which the app
  already has loaded (`productsStreamProvider`). For small/medium shops the whole list
  fits one request; a brand pre-filter is a future optimization for very large catalogs.

## 4. The Edge Function contract (Member A ↔ Member B seam)

`POST /functions/v1/recognize-product` (authenticated with the caller's Supabase JWT).

**Request**
```jsonc
{
  "image_base64": "<jpeg bytes, base64>",
  "candidates": [
    { "id": "uuid", "name": "Pepsi 500ml", "brand": "Pepsi", "variant": "500ml" }
    // … the shop's products
  ]
}
```

**Response**
```jsonc
{
  "status": "match" | "multiple" | "none",
  "read":   { "brand": "Pepsi", "name": "Pepsi", "size": "500ml" }, // what the model read; for logging
  "matches": [ { "product_id": "uuid", "confidence": 0.94 } ]        // ranked, may be empty
}
```

**Provider selection (server-side):**
- `VISION_PROVIDER` env = `gemini` (default) | `openai`.
- Secrets `GEMINI_API_KEY` and/or `OPENAI_API_KEY`.
- The function builds a provider-specific prompt that sends the image + candidate list
  and requests **structured JSON** (both Gemini and OpenAI vision models support image
  input + JSON output). Each provider adapter normalizes its raw output into the
  Response shape above. Moving to Gemini-only = set `VISION_PROVIDER=gemini` (and,
  eventually, delete the OpenAI adapter).

The **prompt/model call is Member B's territory**; this contract is the clean seam.

## 5. Flutter components (all new files — additive)

```
lib/features/scan/
  data/
    vision_scan_repository.dart      # calls supabase.functions.invoke('recognize-product')
  domain/
    recognition_result.dart          # RecognitionResult, ProductMatch, RecognitionStatus (freezed)
  presentation/
    scan_controller.dart             # AsyncNotifier: capture → recognize → decide
    scan_screen.dart                 # entry: capture + progress + result routing
    match_selection_sheet.dart       # "Did you mean?" dialog (multiple matches)
    no_match_sheet.dart              # none: manual pick / add new
lib/core/config/
  feature_flags.dart                 # visionScanEnabled (from --dart-define, default false)
```

- **Capture** uses `image_picker` (camera source) — the **Member C seam**, marked with
  a `// MEMBER C` comment so a richer camera plugin can replace it later.
- **`scan_controller`** orchestrates and maps `RecognitionResult` → UI action using
  tunable confidence thresholds (see §6).
- **Manual fallback** (`no_match_sheet` and the "none" path) opens a searchable product
  picker; on selection it calls the existing `showSaleConfirmationSheet`. (A minimal
  searchable picker is included; it reuses the product name search already used in
  inventory.)
- **Entry point:** a "Scan Product" action surfaced in the selling workflow (e.g. a
  button on the inventory/sell surface), rendered **only when `visionScanEnabled`**.

## 6. Matching / decision logic (client-side, tunable constants)

The model returns per-candidate `confidence` in [0,1]. Constants (calibrate later):
- `strongMatch` = 0.80 **and** top-1 leads #2 by ≥ 0.15 margin → **auto-open** sell sheet.
- else any candidate ≥ `ambiguous` = 0.50 → **selection dialog** (top 3–5 with names).
- else → **no-match** → manual pick / add new.

`status` from the function is advisory; the client applies these thresholds so the UX
is controlled app-side and testable in isolation.

## 7. Safety-net / feature-flag mechanics

- `feature_flags.dart` exposes `const bool visionScanEnabled = bool.fromEnvironment(
  'VISION_SCAN_ENABLED', defaultValue: false);` — the Scan entry point is wrapped in
  `if (visionScanEnabled)`. Shipping with the flag off = feature invisible, zero risk.
- Because every file is new and the only edit to existing screens is *adding a
  flag-gated button*, disabling the flag (or deleting `lib/features/scan/`) fully
  removes the feature. The tag `checkpoint-pre-vision-scan` restores the pre-feature app.

## 8. Prerequisites / setup (new for this project)

1. **Supabase CLI** installed and the project linked (`supabase login`, `supabase link`)
   — currently the project uses the dashboard only, so this is a new setup step.
2. **Deploy** the function: `supabase functions deploy recognize-product`.
3. **Set secrets:** `supabase secrets set GEMINI_API_KEY=… OPENAI_API_KEY=… VISION_PROVIDER=gemini`.
4. **Flutter deps:** add `image_picker` (+ camera permission in `AndroidManifest.xml`
   and `NSCameraUsageDescription` in `Info.plist`).
5. **Run with the flag on:** `flutter run --dart-define=VISION_SCAN_ENABLED=true …`.

## 9. Edge cases & limitations

- **Loose/unbranded items** → the model returns `none`; user picks manually. Expected.
- **No readable label** (blur, angle, glare) → `none` or low confidence → manual/retry.
- **Model picks wrong / over-confident** → the **existing confirmation sheet is the
  safety net** (AI-originated sales must be confirmed — project rule §6); user can
  override. Never auto-commit a sale.
- **Sparse product data** — matching sharpens when `brand`/`variant` are filled; a weak
  match on bare names is acceptable and improves as the catalog is completed.
- **Large catalogs (thousands)** — sending all candidates is fine for small/medium
  shops; a brand pre-filter (read brand first → filter → confirm) is a future step.
- **Cost/latency** — one vision call per scan (a second or two; online assumed).
- **Provider drift** — Gemini vs OpenAI may score differently; thresholds are per-app
  constants, tuned once a provider is chosen.
- **CLI/deploy dependency** — the feature can't function until the Edge Function is
  deployed and secrets set; until then the flag stays off.

## 10. Out of scope (explicitly)

- Product photos in the inventory list (separate future work; not needed for scan).
- Image embeddings / pgvector / on-device models (the earlier approach — dropped).
- Barcode scanning.
- Offline scanning (online assumed).

## 11. Testing

- **Unit (pure, no network):** the threshold/decision function — given a
  `RecognitionResult`, asserts the correct action (auto / dialog / none) across
  confidence + margin cases.
- **Unit:** JSON parsing of the Edge Function response into `RecognitionResult`
  (match / multiple / none / malformed).
- **Manual:** deploy the function, scan a labeled product present in inventory
  (auto-open), two look-alikes (dialog), a loose item (none → manual).

## 12. Phasing

1. **Phase 1 — Contract + skeleton (flag off):** domain models, `VisionScanRepository`,
   `scan_controller` decision logic (+ unit tests), a stub Edge Function returning a
   canned response. App compiles and tests pass with the feature invisible.
2. **Phase 2 — Real Edge Function + capture UI:** implement the Gemini + OpenAI adapters
   behind the provider switch, wire `image_picker` capture, the scan screen, selection
   and no-match sheets, and the flag-gated entry point.
3. **Phase 3 — Calibrate & (optional) Gemini-only:** tune thresholds on real photos;
   flip `VISION_PROVIDER=gemini` permanently and optionally remove the OpenAI adapter.

Each phase is independently shippable; Phase 1 lands entirely behind the flag.
