# parse-sale — deploy & run

Voice sale Edge Function. Given a shopkeeper's spoken sentence (audio) + the
shop's product candidates, it asks an LLM to transcribe the speech and turn it
into sale line items matched against those candidates, and returns normalized
JSON. Like `recognize-product` it calls **Frog API** — a single OpenAI-compatible
gateway serving both OpenAI and Gemini models — so there is one base URL + one
key. Keys stay in Supabase secrets (never on the device).

The sibling of `recognize-product`: same gateway, same key, same
"never trust the model / never invent an id" normalization. Camera in → this is
microphone in.

## How audio reaches the model — run the probe FIRST

An OpenAI-compatible gateway may accept audio one of two ways. Deploy the
throwaway `probe-audio` function, invoke it once, and read its `recommendation`
to learn which your gateway supports, then set `VOICE_STRATEGY` accordingly:

- `VOICE_STRATEGY=multimodal` (default) — one `/chat/completions` call with an
  `input_audio` content part. Simplest.
- `VOICE_STRATEGY=transcribe` — `/audio/transcriptions` first, then a text chat
  call. Fallback when the gateway rejects audio inside chat/completions.

Either way the response shape is identical, so the Flutter app never changes.

## One-time setup
1. Install the Supabase CLI and log in: `supabase login`
2. Link the project: `supabase link --project-ref <your-ref>`
3. Set secrets. Only the key is required; the rest default to Frog values:
   ```
   supabase secrets set FROG_API_KEY=xxxxx              # required (already set for recognize-product)
   supabase secrets set VOICE_STRATEGY=multimodal       # or 'transcribe' — from the probe result
   ```
   Optional overrides if a default slug is rejected:
   ```
   supabase secrets set FROG_BASE_URL=https://frogapi.app/v1
   supabase secrets set VOICE_MODEL=Gemini-3.1-Pro          # exact slug from the dashboard
   supabase secrets set VOICE_TRANSCRIBE_MODEL=whisper-1    # only used by the 'transcribe' strategy
   ```
4. Deploy: `supabase functions deploy parse-sale`

## Contract

Request:
```jsonc
{
  "audio_base64": "<audio bytes, base64>",
  "audio_mime": "audio/m4a",
  "candidates": [
    { "id": "uuid", "name": "Pepsi 1L", "brand": "Pepsi", "variant": "1L", "unit": "pcs" }
  ]
}
```

Response:
```jsonc
{
  "heard_text": "sold 2 pepsi and 3 chips",
  "items": [
    { "heard": "pepsi", "quantity": 2, "unit_heard": null,
      "matches": [ { "product_id": "uuid", "confidence": 0.55 } ] }
  ]
}
```

Genuine failures (bad key, gateway outage, unparseable reply) return **502** so
the app shows a retry state; a real "nothing recognized" is a **200** with an
empty `items` array.

## Smoke test
```
curl -s -X POST "$SUPABASE_URL/functions/v1/parse-sale" \
  -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"audio_base64\":\"$(base64 -w0 sample.m4a)\",\"audio_mime\":\"audio/m4a\",\"candidates\":[{\"id\":\"p1\",\"name\":\"Pepsi 1L\",\"variant\":\"1L\"}]}"
```

## Run the app with voice enabled
```
flutter run \
  --dart-define=SUPABASE_URL=... \
  --dart-define=SUPABASE_ANON_KEY=... \
  --dart-define=VOICE_SALE_ENABLED=true
```
