# Execution evidence for the hackathon (2026-10-19)

The optional "execution evidence" deliverable: proof that EasySell is built and
works. It lives as a Claude Doc ("EasySell: Execution Evidence"); the scripts and
raw results that produced every number are in `docs/hackathon/evidence/`.

## Why it was built this way

- **Measured, not screenshotted.** Most teams send screenshots. We tested the
  live system (AI functions, database, security rules) so each deck claim has a
  number a judge can check and re-run.
- **Throwaway test accounts, not the demo shop.** Two accounts with their own
  shops ran every write test; `cleanup.mjs` deletes the shops. The demo shop's
  numbers (used in the deck and video) were never touched. The two logins remain
  in Supabase Auth; their passwords were kept outside the repo.
- **No admin key.** Everything goes through the public key plus a signed-in
  user's token, exactly as the app does, so the security results reflect what a
  real user or attacker can do.
- **Rejected: a local-only database test** (PGlite). It is single-connection, so
  it cannot show two sales racing for the last item, and it proves nothing about
  the deployed system.

## Gotchas that cost time

- **No Bangla text-to-speech on Windows** (only US English voices). `msedge-tts`
  1.3.4 and `edge-tts` 7.0.2 both fail now (Microsoft rejects old clients, 403).
  Google's `translate_tts` endpoint works for `bn` and `en-IN` with no key.
- **Wikimedia Commons API rate-limits fast** (about 18 searches, then "too many
  requests"). Download via `Special:FilePath/<name>?width=1024`, a few seconds
  apart.
- **`parse-sale` returns the heard sentence as `heard_text`**, not `transcript`.
- **The AI functions do not return Gemini's token counts**, so cost is an
  estimate from request sizes (text ≈ 4 chars a token, audio 32 tokens a second,
  images up to 1,120 tokens), clearly labelled as such.
- **No Deno on this machine**, so the parse-sale Deno unit test was not re-run.
  Its Bangla fraction fix (আড়াই → 2.5, দেড় → 1.5) was shown live instead.

## Results worth remembering (19 Oct 2026)

- Voice 19/20 sentences (Bangla 10/10), 33/33 products, 32/33 quantities;
  "Four Mum water" lost "four". Camera 12/13; the back of a Pepsodent tube was
  read as "Pepsodent Toothpaste" but not matched to "Toothpaste (Pepsodent)",
  which hints the vision prompt under-weights brand-only matches.
- Median 2.0 s voice, 2.1 s camera. Estimated US$0.0013 per voice sale and
  US$0.0023 per photo (US$0.0046 after Gemini 3.6 Flash's 1 Jan 2027 price rise).
- Money safety 7/7 (10/10 races), security 13/13, deployment 8/8, tests 710/710.
