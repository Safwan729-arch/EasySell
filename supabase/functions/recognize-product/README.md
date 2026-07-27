# recognize-product — deploy & run

Vision product-scan Edge Function. Given an item photo + the shop's product
candidates, it asks Gemini which candidate is in the photo and returns
normalized JSON matched against those candidates.

## Gemini-direct flow

The image is sent straight to Google's official **Gemini API**
(`generativelanguage.googleapis.com`) via `generateContent`, as an
`inline_data` part. The reply is forced into the exact response shape below
using Gemini **structured output** (`responseMimeType: application/json` +
`responseSchema`), so there is no fragile "find the JSON in the text" step.
Keys stay in Supabase secrets (never on the device).

> **History:** this function used to route the image through the Frog gateway
> (an OpenAI-compatible endpoint serving GPT/Gemini). It no longer uses Frog at
> all — it calls Gemini directly. (The voice function `parse-sale` still uses
> Frog for its text→line-items step for now; those Frog secrets stay in place
> until that migration happens.)

## One-time setup
1. Install the Supabase CLI and log in: `supabase login`
2. Link the project: `supabase link --project-ref <your-ref>`
3. Set secrets:
   ```
   supabase secrets set GEMINI_API_KEY=xxxxx    # required (official Google AI Studio key)
   ```
   Optional override if you want a different model than the default
   `gemini-3.6-flash`:
   ```
   supabase secrets set GEMINI_VISION_MODEL=gemini-flash-latest   # exact Gemini model slug
   ```
   `GEMINI_API_KEY` is shared with the voice function `parse-sale`; if voice
   already works, scan needs no new secret.
4. Deploy: `supabase functions deploy recognize-product`

## Contract

Request — both fields required:
```jsonc
{
  "image_base64": "<base64 JPEG bytes, no data: prefix>",
  "candidates": [
    { "id": "uuid", "name": "Pepsi 1L", "brand": "Pepsi", "variant": "1L" }
  ]
}
```

Response:
```jsonc
{
  "status": "match" | "multiple" | "none",
  "read_brand": string | null,
  "read_name": string | null,
  "read_size": string | null,
  "matches": [ { "product_id": "<id from candidates>", "confidence": 0.0-1.0 } ]
}
```

`status` is derived from how many candidate matches survive validation: `none`
(zero), `match` (one), `multiple` (two or more — the app then asks the user
which). Matches whose `product_id` is not in the candidate list are dropped, and
`confidence` is clamped to `[0,1]`; the model's raw output is never trusted.

### Status conventions
- **400** — bad input: missing/empty `image_base64`, non-array `candidates`, or
  `GEMINI_API_KEY` not configured.
- **200** — a real result, *including* `status:"none"` when Gemini genuinely
  recognizes nothing in the candidate list.
- **502** — genuine failures: bad key, Gemini outage/quota, an unparseable
  reply, or an unexpected Gemini response shape (missing/empty `candidates`, a
  non-array/empty `parts` list — e.g. a safety block). These are never
  reported as a silent "no match".

## Smoke test (direct probe)

Because there is no local Deno/Supabase CLI here, verify against the deployed
function. PowerShell:
```powershell
$img = [Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\path\to\product.jpg"))
$body = @{
  image_base64 = $img
  candidates = @(
    @{ id = "p1"; name = "Pepsi 1L"; brand = "Pepsi"; variant = "1L" },
    @{ id = "p2"; name = "Pepsi 500ml"; brand = "Pepsi"; variant = "500ml" }
  )
} | ConvertTo-Json -Depth 5
Set-Content -Path "$env:TEMP\scan-probe.json" -Value $body -Encoding utf8

$anon = (Get-Content .\dart_defines.json | ConvertFrom-Json).SUPABASE_ANON_KEY
Invoke-RestMethod -Method Post `
  -Uri "$env:SUPABASE_URL/functions/v1/recognize-product" `
  -Headers @{ Authorization = "Bearer $anon"; "Content-Type" = "application/json" } `
  -InFile "$env:TEMP\scan-probe.json"
```
A clear photo of a listed product returns `status:"match"` (or `"multiple"` when
the size is ambiguous) with that product's id. A photo of something not in the
list returns `status:"none"` with empty `matches`.

## Run the app with scanning enabled
```
flutter run \
  --dart-define=SUPABASE_URL=... \
  --dart-define=SUPABASE_ANON_KEY=... \
  --dart-define=VISION_SCAN_ENABLED=true
```
The "Scan product" button appears on the inventory screen only when
`VISION_SCAN_ENABLED=true`.

## Rollback
Revert the Gemini-migration commits on `feat/scan-gemini` (or
`git checkout checkpoint-pre-vision-scan` for the whole original feature). No
secret changes are needed to roll back — the Frog secrets were left in place.
