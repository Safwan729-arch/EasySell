# parse-sale — deploy & run

Voice sale Edge Function. Given either a **transcript** of a shopkeeper's
spoken sentence or raw **audio**, plus the shop's product candidates, it turns
the sentence into sale line items matched against those candidates, and
returns normalized JSON.

## Hybrid flow: Gemini hears it, Frog understands it

Two providers, two jobs:
- **Audio in → Gemini transcribes.** When the request carries `audio_base64`,
  this function calls the Gemini API directly
  (`generativelanguage.googleapis.com`) to transcribe the clip to text. The
  shop's product names are passed as vocabulary hints so brand names are heard
  correctly, but the full candidate JSON (with ids) is never sent to Gemini —
  it only needs words, not ids.
- **Text (typed or transcribed) → Frog parses.** The resulting transcript is
  fed into the **existing, unchanged** Frog/GPT step — an OpenAI-compatible
  gateway — which matches it against the candidate list and returns
  structured line items. This is the same path a plain `transcript` request
  always used; audio is just a new way to arrive at a transcript.

### Why Gemini, not Frog, for audio

Verified 2026-07-22 (probe-audio spike): **Frog does not accept audio.**
`/chat/completions` rejects an `input_audio` content block
(`400: "Content blocks are expected to be either text or image_url type"`) and
there is no `/audio/transcriptions` endpoint (`404`). Gemini has a free tier
and accepts audio directly via `generateContent`, so it does the
transcription; Frog keeps doing exactly what it always has with plain text.

## One-time setup
1. Install the Supabase CLI and log in: `supabase login`
2. Link the project: `supabase link --project-ref <your-ref>`
3. Set secrets:
   ```
   supabase secrets set FROG_API_KEY=xxxxx          # required (already set for recognize-product)
   supabase secrets set GEMINI_API_KEY=xxxxx         # required for audio input (free Gemini key)
   ```
   Optional overrides if a default is rejected:
   ```
   supabase secrets set FROG_BASE_URL=https://frogapi.app/v1
   supabase secrets set VOICE_MODEL=gpt-5.6-luna              # exact lowercase slug from the Frog dashboard
   supabase secrets set GEMINI_TRANSCRIBE_MODEL=gemini-2.5-flash  # free tier, audio-capable
   ```
   `FROG_API_KEY`, `VOICE_MODEL`/`OPENAI_MODEL`, and `GEMINI_API_KEY` are the
   only ones that matter for a first deploy — the rest default sensibly.
4. Deploy: `supabase functions deploy parse-sale`

## Contract

Request — **exactly one** of `transcript` or `audio_base64` is required
(never both). `candidates` is always required.

Text in:
```jsonc
{
  "transcript": "sold 2 pepsi and 3 chips",
  "candidates": [
    { "id": "uuid", "name": "Pepsi 1L", "brand": "Pepsi", "variant": "1L", "unit": "pcs" }
  ]
}
```

Audio in:
```jsonc
{
  "audio_base64": "<base64-encoded audio bytes, no data: prefix>",
  "audio_mime": "audio/m4a",           // optional, defaults to "audio/m4a"
  "candidates": [
    { "id": "uuid", "name": "Pepsi 1L", "brand": "Pepsi", "variant": "1L", "unit": "pcs" }
  ]
}
```

Response (same shape regardless of which input was used):
```jsonc
{
  "heard_text": "sold 2 pepsi and 3 chips",
  "items": [
    { "heard": "pepsi", "quantity": 2, "unit_heard": null,
      "matches": [ { "product_id": "uuid", "confidence": 0.55 } ] }
  ]
}
```

A silent/unintelligible audio clip is a real "nothing was said" result: Gemini
returning an empty/whitespace transcript short-circuits to
`{ "heard_text": "", "items": [] }` with **200**, without calling Frog at all.

Genuine failures (bad key, gateway/Gemini outage, unparseable reply) return
**502** so the app shows a retry state; missing/duplicate input fields
(neither or both of `transcript`/`audio_base64`, missing `candidates`, or
audio sent with no `GEMINI_API_KEY` configured) return **400**.

## Smoke test — text (no audio needed — it takes text)
```
curl -s -X POST "$SUPABASE_URL/functions/v1/parse-sale" \
  -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"transcript":"sold 2 pepsi","candidates":[{"id":"p1","name":"Pepsi 1L","variant":"1L"},{"id":"p2","name":"Pepsi 500ml","variant":"500ml"}]}'
```
Because "pepsi" alone does not say which size, a correct response returns BOTH
candidates with similar confidence (the app then asks the user).

## Smoke test — audio
Base64-encode a short recording and put it in a JSON file so curl doesn't
choke on shell-escaping a huge string:
```bash
python3 -c "import base64,json; print(json.dumps({
  'audio_base64': base64.b64encode(open('sample.m4a','rb').read()).decode(),
  'audio_mime': 'audio/m4a',
  'candidates': [
    {'id': 'p1', 'name': 'Pepsi 1L', 'variant': '1L'},
    {'id': 'p2', 'name': 'Pepsi 500ml', 'variant': '500ml'}
  ]
}))" > body.json

curl -s -X POST "$SUPABASE_URL/functions/v1/parse-sale" \
  -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d @body.json
```

## Run the app with voice enabled
```
flutter run \
  --dart-define=SUPABASE_URL=... \
  --dart-define=SUPABASE_ANON_KEY=... \
  --dart-define=VOICE_SALE_ENABLED=true
```
