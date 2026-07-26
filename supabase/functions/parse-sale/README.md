# parse-sale — deploy & run

Voice sale Edge Function. Given either raw **audio** of a shopkeeper's spoken
sentence (what the app sends) or a **transcript** (a curl-testable debug path),
plus the shop's product candidates, it turns the sentence into sale line items
matched against those candidates, and returns normalized JSON.

## One Gemini call: hears it AND understands it

A **single** Google Gemini `generateContent` call
(`generativelanguage.googleapis.com`) does both jobs at once:
- **Transcribes** the audio verbatim into `heard_text` (the review sheet shows
  this so a mishear is obvious).
- **Extracts** sale line items, matched against the candidate list, using
  structured output (`responseMimeType: application/json` + `responseSchema`) so
  the reply is guaranteed to be the right shape — no brace-scraping.

The text `transcript` path uses the same single call, just without the audio
part.

> **History:** this function used to make two hops — Gemini transcribed the
> audio, then the Frog gateway (OpenAI-compatible GPT) parsed the text into
> items. It now does both in one Gemini call; **Frog is no longer used by
> voice.** (Frog was never able to accept audio anyway — verified 2026-07-22 it
> rejects an `input_audio` block and has no transcription endpoint.)

## One-time setup
1. Install the Supabase CLI and log in: `supabase login`
2. Link the project: `supabase link --project-ref <your-ref>`
3. Set secrets:
   ```
   supabase secrets set GEMINI_API_KEY=xxxxx    # required (official Google AI Studio key, shared with scan)
   ```
   Optional override if you want a different model than the default
   `gemini-3.6-flash`:
   ```
   supabase secrets set GEMINI_VOICE_MODEL=gemini-flash-latest   # exact Gemini model slug
   ```
   `GEMINI_API_KEY` is the only secret that matters. (The old `FROG_*`,
   `VOICE_MODEL`/`OPENAI_MODEL`, and `GEMINI_TRANSCRIBE_MODEL` secrets are no
   longer read by this function.)
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
  "audio_mime": "audio/aac",           // optional, defaults to "audio/aac"
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
`quantity` is omitted when no count was spoken — the app defaults it to 1 and
flags it as assumed.

A silent/unintelligible audio clip is a real "nothing was said" result: Gemini
returns empty `items` (and an empty `heard_text`) →
`{ "heard_text": "", "items": [] }` with **200**.

Genuine failures (bad key, Gemini outage, unparseable reply) return **502** so
the app shows a retry state; missing/duplicate input fields (neither or both of
`transcript`/`audio_base64`, missing `candidates`, or `GEMINI_API_KEY` not
configured) return **400**. An unexpected Gemini response shape (missing/empty
`candidates`, or a non-array `parts` list — e.g. a safety block or an API change)
is also a **502** (retry) — it is never treated as a silent empty result.

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
  'audio_mime': 'audio/aac',
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
