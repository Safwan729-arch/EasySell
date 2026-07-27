# Scan Migration: Frog/OpenAI → Gemini 3.6 Flash (direct)

**Date:** 2026-07-27
**Feature owner:** Member A (Full Stack)
**Scope:** `supabase/functions/recognize-product` Edge Function only. No Flutter/app changes.

---

## 1. Goal

Rebuild the product-scan Edge Function (`recognize-product`) so it recognizes a
product photo by calling **Google's official Gemini API directly** with the
**`gemini-3.6-flash`** model, instead of routing through the **Frog** gateway
(OpenAI-compatible, GPT/Gemini-via-Frog). Frog and its OpenAI model are removed
from this function.

Voice (`parse-sale`) is out of scope here — it keeps using Frog for its
text→line-items step for now. This spec migrates **scan only**.

## 2. Hard constraint — the contract is frozen

The Flutter app already calls this function and depends on its request/response
shape. Both are preserved **exactly**; the app requires zero changes.

**Request (unchanged):**
```jsonc
{
  "image_base64": "<base64 JPEG bytes, no data: prefix>",
  "candidates": [ { "id": "uuid", "name": "Pepsi 1L", "brand": "Pepsi", "variant": "1L" } ]
}
```

**Response (unchanged):**
```jsonc
{
  "status": "match" | "multiple" | "none",
  "read_brand": string | null,
  "read_name": string | null,
  "read_size": string | null,
  "matches": [ { "product_id": "<id from candidates>", "confidence": 0.0-1.0 } ]
}
```

Function name stays `recognize-product`. HTTP status conventions stay: 400 for
bad input, 200 for a real result (including `status:"none"`), 502 for genuine
failures.

## 3. What changes (engine swap)

| Before | After |
|---|---|
| POST `https://frogapi.app/v1/chat/completions` | POST `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent` |
| Auth: `Authorization: Bearer FROG_API_KEY` | Auth: `x-goog-api-key: GEMINI_API_KEY` |
| Image as OpenAI `image_url` data-URL content part | Image as Gemini `inline_data` part (`{mime_type, data}`) |
| Model: `OPENAI_MODEL` / `GEMINI_MODEL` via `VISION_PROVIDER` | Model: `gemini-3.6-flash` (pinned default) |
| JSON via prompt + `extractJson()` brace-scraping | **Structured output** — `responseMimeType: application/json` + `responseSchema` |

Removed from this function entirely: `FROG_BASE_URL`, `FROG_API_KEY`,
`VISION_PROVIDER`, `OPENAI_MODEL`, the Frog `GEMINI_MODEL` slug, and the
`temperature` field styled for the OpenAI gateway.

## 4. Structured output (Approach A)

Gemini is asked to return JSON conforming to a `responseSchema` so the shape is
enforced by the API rather than coaxed by prompt text. Schema mirrors the
response contract:

```jsonc
{
  "type": "object",
  "properties": {
    "status":     { "type": "string", "enum": ["match", "multiple", "none"] },
    "read_brand": { "type": "string", "nullable": true },
    "read_name":  { "type": "string", "nullable": true },
    "read_size":  { "type": "string", "nullable": true },
    "matches": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "product_id": { "type": "string" },
          "confidence": { "type": "number" }
        },
        "required": ["product_id", "confidence"]
      }
    }
  },
  "required": ["status", "matches"]
}
```

Config sent: `generationConfig: { responseMimeType: "application/json",
responseSchema: <above>, temperature: 0 }`.

The instruction prompt (product-identification rules, "never invent an id",
"rank by confidence") is carried over largely as-is, minus the "return ONLY
minified JSON of this exact shape" sentence — the schema now enforces shape.
MEMBER B owns prompt tuning; the seam comment stays.

Even with structured output, the response text is still `JSON.parse`d defensively
inside a try (a safety block or truncation can still yield non-conforming text),
and any parse failure throws → 502.

## 5. `normalize()` — unchanged behavior

The existing `normalize()` stays as the trust boundary: drop matches whose
`product_id` is not in the candidate set, clamp `confidence` to `[0,1]`, force
`status:"none"` when no valid matches survive. Never trust the model's raw shape
even with a schema.

## 6. Error handling (parity with current + parse-sale discipline)

- Non-2xx from Gemini (bad key → 400, quota → 429, outage → 5xx): read body,
  `throw new Error("gemini <status>: <detail>")` → caught → **502**.
- Unexpected response shape (missing `candidates[0].content.parts`, empty parts,
  safety block with no text): **throw → 502**, never a silent `status:"none"`.
  Mirrors the guard already in `parse-sale`.
- Gemini genuinely finds nothing → model returns `status:"none"` (or empty
  matches) → normalize → **200**. A real "no match" is a success, not an error.
- Missing `image_base64` or non-array `candidates` → **400** (unchanged).
- Missing `GEMINI_API_KEY` at call time surfaces as a Gemini 401/403 → 502; a
  fast-fail 400 guard when the key is unset is a nice-to-have (see §8).

Multi-part / "thinking" responses: join non-`thought` parts before parsing, same
as `parse-sale.transcribe()`, so a leading thought segment can't be misread.

## 7. Config / secrets

| Secret | Role | State |
|---|---|---|
| `GEMINI_API_KEY` | Auth for Gemini (shared with voice) | Already set |
| `GEMINI_VISION_MODEL` | Optional override of the model slug | Optional; defaults to `gemini-3.6-flash` |

`const MODEL = Deno.env.get("GEMINI_VISION_MODEL") ?? "gemini-3.6-flash";`

Frog secrets (`FROG_API_KEY`, etc.) remain in Supabase, untouched, because
`parse-sale` still uses them. This function simply stops referencing them.
**Roadmap note:** the agreed end-state is Frog fully removed — a follow-up job
migrates `parse-sale`'s brain step to Gemini too, and the Frog secrets are
deleted only after that. Keeping them now is purely to avoid breaking voice
mid-migration; scan itself has no Frog dependency after this change.

Image mime is assumed `image/jpeg` (what the app sends today; the old code
hard-coded the same). Kept as a constant; an optional `image_mime` request field
is a possible future add but not in scope.

## 8. Testing

- **Direct probe** (before app): POST a real product-photo base64 + candidates to
  the deployed function; assert 200 and a well-formed contract response with a
  plausible match. This is the gate before any on-phone test.
- **No-match probe:** a photo of something not in the candidate list → expect
  `status:"none"`, empty matches, 200.
- **Bad-key / failure path:** confirm a forced failure returns 502, not a fake
  `status:"none"`.
- **On-device:** scan a real product on the S22, confirm the confirmation UI
  still receives the same shape and behaves as before.
- Optional hardening: a 400 fast-fail when `GEMINI_API_KEY` is unset (clearer
  than a downstream 401), matching how `parse-sale` guards audio-without-key.

## 9. Out of scope

- No Flutter/app changes (contract frozen).
- No migration of `parse-sale`'s Frog brain step (separate future work).
- No removal of Frog secrets from Supabase.
- No `analytics`/schema changes.

## 10. Rollback

The change is confined to one file (`recognize-product/index.ts`). Reverting the
commit and redeploying restores the Frog path. Frog secrets remain in place, so
rollback needs no secret changes.
