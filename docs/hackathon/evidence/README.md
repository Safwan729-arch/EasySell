# Execution evidence: scripts and raw results

These scripts produced the numbers in the "EasySell: Execution Evidence"
document (19 October 2026). They call the **live** Supabase project over
HTTPS, the same way the app does, from throwaway test accounts with their own
test shops. The real demo shop is never touched.

| Script | What it proves | Raw result |
|---|---|---|
| `setup.mjs` | Creates two test accounts, each with its own shop | (none) |
| `ai_benchmark.mjs` | Voice and camera AI accuracy, speed and estimated cost | `results/ai_benchmark.json` |
| `money_safety.mjs` | Races for the last item, retried sales and payments, all-or-nothing carts, frozen prices | `results/money_safety.json` |
| `security_probe.mjs` | What the public key and another shop's owner can and cannot do | `results/security_probe.json` |
| `deployment_check.mjs` | Migrations and AI functions are deployed | `results/deployment_check.json` |
| `cleanup.mjs` | Deletes the test shops | (none) |

`results/flutter_test.txt` and `results/flutter_analyze.txt` are the fresh
test and analyzer runs.

## Running them

Needs Node 18+ and `ffprobe` (FFmpeg) on the PATH, plus `dart_defines.json` at
the repo root (the Supabase URL and public anon key; git-ignored).

```bash
export EV_CREDS=/somewhere/outside/the/repo/creds.json   # test logins live here, never commit it
node setup.mjs
node ai_benchmark.mjs <photos dir> <audio work dir>
node money_safety.mjs
node security_probe.mjs
node deployment_check.mjs
node cleanup.mjs
```

- **Audio:** `ai_benchmark.mjs` turns each test sentence into speech with
  Google's text-to-speech voice (Indian English or Bangla) and caches the
  files in the audio work dir.
- **Photos:** the 13 photos are from Wikimedia Commons, resized to at most
  1024 px. Their file names are in `photos.txt`; save each as
  `<key>.jpg` in the photos dir.
- **Cost:** a full run makes about 35 Gemini calls (under US$0.10).
