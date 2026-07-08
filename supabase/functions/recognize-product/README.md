# recognize-product — deploy & run

Vision product-scan Edge Function. Given an item photo + the shop's product
candidates, it asks a vision LLM which candidate is in the photo and returns
normalized JSON. It calls **Frog API** — a single OpenAI-compatible gateway that
serves both OpenAI and Gemini models — so there is one base URL + one key, and
`VISION_PROVIDER` just selects which model name is sent. Keys stay in Supabase
secrets (never on the device).

## One-time setup
1. Install the Supabase CLI and log in: `supabase login`
2. Link the project: `supabase link --project-ref <your-ref>`
3. Set secrets. Only the key is required — base URL and model ids default to
   Frog (`https://frogapi.app/v1`, `Gemini-3.1-Pro`, `GPT-5.5`):
   ```
   supabase secrets set FROG_API_KEY=xxxxx        # required
   supabase secrets set VISION_PROVIDER=openai    # openai=GPT-5.5 (default), gemini=Gemini-3.1-Pro
   ```
   Optional overrides if Frog rejects a default:
   ```
   supabase secrets set FROG_BASE_URL=https://frogapi.app/v1
   supabase secrets set GEMINI_MODEL=Gemini-3.1-Pro   # exact slug from the dashboard
   supabase secrets set OPENAI_MODEL=GPT-5.5          # exact slug from the dashboard
   ```
   `VISION_PROVIDER` picks between `GEMINI_MODEL` and `OPENAI_MODEL`; both are
   called through the same Frog endpoint/key.
4. Deploy: `supabase functions deploy recognize-product`

## Run the app with scanning enabled
```
flutter run \
  --dart-define=SUPABASE_URL=... \
  --dart-define=SUPABASE_ANON_KEY=... \
  --dart-define=VISION_SCAN_ENABLED=true
```
The "Scan product" button appears on the inventory screen only when
`VISION_SCAN_ENABLED=true`.

## Switch to Gemini-only later
`supabase secrets set VISION_PROVIDER=gemini` — the OpenAI path is never used
after that. (No code change needed; both go through the same Frog gateway.)

## Rollback the whole feature
`git checkout checkpoint-pre-vision-scan`
