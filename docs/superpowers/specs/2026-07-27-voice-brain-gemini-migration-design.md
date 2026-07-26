# Voice Brain Migration: Frog/GPT → Gemini 3.6 Flash (single call)

**Date:** 2026-07-27
**Feature owner:** Member A (Full Stack)
**Scope:** `supabase/functions/parse-sale` Edge Function only. No Flutter/app changes.
**Branch:** `feat/voice-sale` (work directly on the existing voice branch — no new branch).

---

## 1. Goal

Migrate the voice sale parser (`parse-sale`) so a **single Google Gemini
`generateContent` call** both transcribes the shopkeeper's audio and turns it into
structured sale line items — replacing today's two hops (Gemini transcribe → Frog/GPT
parse). This finishes removing Frog from the app: after this (with scan already on
Gemini), Frog is used by nothing.

**Approach B** from brainstorming: one cloud trip, `gemini-3.6-flash` doing hearing +
matching in one shot.

## 2. Frozen contract

The app (`voice_sale_repository.dart` → `VoiceParseResult.fromJson`) depends on these;
both stay identical:

**Request:** `{ audio_base64, audio_mime, candidates }` (app path). A text
`{ transcript, candidates }` path is kept for curl/debug. Exactly one of
`audio_base64` / `transcript`.

**Response:**
```jsonc
{
  "heard_text": string,
  "items": [
    { "heard": string, "quantity": number?, "unit_heard": string|null,
      "matches": [ { "product_id": "<id from candidates>", "confidence": 0..1 } ] }
  ]
}
```
`quantity` is **omitted** when no count was spoken — the app defaults it to 1 and flags
`quantityAssumed`. This must remain omittable.

## 3. What changes

| Before | After |
|---|---|
| `transcribe()` → Gemini (audio→text) then `parse()` → Frog `chat/completions` (text→items) | **one** `parseSale()` → Gemini `generateContent` (audio **or** text → items) |
| Auth: Gemini key for transcribe + `Authorization: Bearer FROG_API_KEY` for parse | Auth: `x-goog-api-key: GEMINI_API_KEY` only |
| Models: `GEMINI_TRANSCRIBE_MODEL` + `VOICE_MODEL`/`OPENAI_MODEL` (Frog) | `GEMINI_VOICE_MODEL`, default `gemini-3.6-flash` |
| JSON via prompt + `extractJson()` brace-scraping | structured output (`responseMimeType` + `responseSchema`) |

Deleted entirely: `BASE_URL`, `FROG_API_KEY`, Frog `MODEL`, `parse()`, `transcribe()`,
`extractJson()`, `transcribePrompt()`.

## 4. The single Gemini call

- One `contents[0].parts`: `[ {text: instruction(candidates)}, <audio or transcript part> ]`.
  - Audio path: `{ inline_data: { mime_type, data } }` (default mime `audio/aac`).
  - Text path: `{ text: transcript }`.
- `generationConfig: { responseMimeType: "application/json", responseSchema, temperature: 0 }`.
- The instruction merges the two jobs: (1) transcribe verbatim into `heard_text`,
  (2) extract items. The existing rules carry over verbatim: **quantity ≠ size**,
  ambiguous → return BOTH candidates with similar confidence, never invent an id,
  English/Bengali/mix, omit `quantity` when no count was spoken, empty items when
  nothing sale-like was said.

`responseSchema` (item `required` is `["heard","matches"]` so `quantity`/`unit_heard`
stay optional):
```jsonc
{
  "type":"object",
  "properties":{
    "heard_text":{"type":"string"},
    "items":{"type":"array","items":{
      "type":"object",
      "properties":{
        "heard":{"type":"string"},
        "quantity":{"type":"number"},
        "unit_heard":{"type":"string","nullable":true},
        "matches":{"type":"array","items":{
          "type":"object",
          "properties":{"product_id":{"type":"string"},"confidence":{"type":"number"}},
          "required":["product_id","confidence"]}}
      },
      "required":["heard","matches"]}}
  },
  "required":["heard_text","items"]
}
```

## 5. Error handling & normalize (parity kept)

- Non-2xx from Gemini → `throw new Error("gemini <status>: …")` → caught → **502**.
- Unexpected shape (missing/empty `candidates`, non-array/empty `parts`, safety block)
  → **502**, never a silent empty result. Join only non-`thought` parts before parse.
- **Silent/unintelligible audio** → Gemini returns empty `items` (and empty
  `heard_text`) → normalize → **200 `{heard_text:"", items:[]}`**. (No separate
  pre-transcription short-circuit is needed now; one call naturally yields empty items.)
- Missing `GEMINI_API_KEY` → **400** (now required for both paths). Neither/both of
  `transcript`/`audio_base64`, or non-array `candidates` → **400**.
- `normalize()` is **kept unchanged**: drop invented ids, clamp confidence to `[0,1]`,
  pass `quantity` only when a positive number (else null → app assumes 1),
  `unit_heard` string|null, `heard_text` falls back to the input transcript (audio path
  falls back to `""`).

## 6. Config / secrets

| Secret | Role | State |
|---|---|---|
| `GEMINI_API_KEY` | Auth for Gemini (shared with scan) | Already set |
| `GEMINI_VOICE_MODEL` | Optional model override | Optional; defaults to `gemini-3.6-flash` |

Frog secrets and `GEMINI_TRANSCRIBE_MODEL` become unused by `parse-sale`. With scan
already migrated, **Frog is now unused app-wide** — its secrets can be deleted after
this ships and is verified.

## 7. Testing

No local Deno/CLI, so probe the deployed function (like scan):
- **Text probe:** `{transcript:"sold 2 pepsi", candidates:[Pepsi 1L, Pepsi 500ml]}`
  → 200, `items[0]` has `quantity:2`, `heard:"pepsi"`, and **both** Pepsis with similar
  confidence (ambiguous). A `{transcript:"sold pepsi 1 litre", …}` should favor the 1L.
- **Audio probe:** a short synthesized clip (Windows SAPI TTS) saying "sold two pepsi"
  → 200 with a plausible `heard_text` and the same item shape. If TTS is unavailable,
  fall back to the user's on-device test as the audio-path gate.
- **Failure probe:** a bogus `GEMINI_VOICE_MODEL` → 502 (proves failures aren't a fake
  empty result); then restore.
- **On-device:** Bengali / English / mixed sale, ambiguous item, silence.

## 8. Out of scope

- No app changes (contract frozen). No scan changes. No deletion of Frog secrets in
  this change (a follow-up cleanup once verified).

## 9. Rollback

Confined to `parse-sale/index.ts`. Reverting the commit restores the Gemini+Frog two-hop
version. Frog secrets remain in place, so rollback needs no secret changes.
