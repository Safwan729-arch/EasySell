# parse-sale — deploy & run

Voice sale Edge Function. Given a **transcript** of a shopkeeper's spoken
sentence + the shop's product candidates, it asks an LLM to turn the sentence
into sale line items matched against those candidates, and returns normalized
JSON. Like `recognize-product` it calls **Frog API** — an OpenAI-compatible
gateway — so there is one base URL + one key. Keys stay in Supabase secrets
(never on the device).

## Why text in, not audio

Verified 2026-07-22 (probe-audio spike): **Frog does not accept audio.**
`/chat/completions` rejects an `input_audio` content block
(`400: "Content blocks are expected to be either text or image_url type"`) and
there is no `/audio/transcriptions` endpoint (`404`). So the **speech→text step
runs on-device** (Flutter `speech_to_text` plugin), and only the resulting text
reaches this function. This function does the *understanding* (transcript →
line items matched against the shop's products), which is plain text and works.

## One-time setup
1. Install the Supabase CLI and log in: `supabase login`
2. Link the project: `supabase link --project-ref <your-ref>`
3. Set secrets. Only the key is required; the model defaults to the same
   `OPENAI_MODEL` the scan feature uses (e.g. `gpt-5.6-luna`), so no new model
   secret is needed:
   ```
   supabase secrets set FROG_API_KEY=xxxxx        # required (already set for recognize-product)
   ```
   Optional overrides if a default is rejected:
   ```
   supabase secrets set FROG_BASE_URL=https://frogapi.app/v1
   supabase secrets set VOICE_MODEL=gpt-5.6-luna    # exact lowercase slug from the Frog dashboard
   ```
4. Deploy: `supabase functions deploy parse-sale`

## Contract

Request:
```jsonc
{
  "transcript": "sold 2 pepsi and 3 chips",
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
the app shows a retry state; a real "nothing sale-like was said" is a **200**
with an empty `items` array.

## Smoke test (no audio needed — it takes text)
```
curl -s -X POST "$SUPABASE_URL/functions/v1/parse-sale" \
  -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"transcript":"sold 2 pepsi","candidates":[{"id":"p1","name":"Pepsi 1L","variant":"1L"},{"id":"p2","name":"Pepsi 500ml","variant":"500ml"}]}'
```
Because "pepsi" alone does not say which size, a correct response returns BOTH
candidates with similar confidence (the app then asks the user).

## Run the app with voice enabled
```
flutter run \
  --dart-define=SUPABASE_URL=... \
  --dart-define=SUPABASE_ANON_KEY=... \
  --dart-define=VOICE_SALE_ENABLED=true
```
