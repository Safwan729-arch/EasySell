# Voice Sale: Making the Post-Speech Wait Bearable — Design

**Date:** 2026-08-05
**Feature owner:** Member A (Full Stack)
**Scope:** `lib/features/voice/**`, `lib/app.dart`, `supabase/functions/parse-sale/index.ts`
**Shipped as:** commit `53ee72b` on `feat/voice-wait-ux`
**Related:** [2026-07-27-voice-noise-latency-design](2026-07-27-voice-noise-latency-design.md)
(fixed the 30s *hang*; this one addresses the normal-case *wait*)

---

## 1. Problem

Between "shopkeeper stops speaking" and "cart appears" there are a few seconds
of nothing. The old thinking pane showed the word "Working it out…" over two
static grey skeleton cards.

That is a dead wall. A frozen screen and a broken screen look identical, so in a
queue the wait reads as a hang — and the shopkeeper can do nothing but stand and
watch it while a customer waits. The complaint was never "it's slow"; it was
"it's slow *and I'm stuck*".

## 2. Framing: two independent levers

Borrowed from the airport baggage-claim result — moving arrival gates further
from the carousel eliminated complaints without making bags any faster:

- **Lever A — fewer seconds.** Genuine latency reduction.
- **Lever B — the seconds don't feel like waiting.** Occupied time feels far
  shorter than unoccupied time.

Lever B is cheaper per unit of perceived improvement, and was under-exploited.
Both were pulled.

## 3. Options considered

| # | Option | Verdict |
|---|---|---|
| 1 | Warm the Edge Function container on record start | **Shipped** |
| 2 | Shorten the trailing-silence window | **Shipped** |
| 3 | Let the parse continue after the sheet is dismissed | **Shipped** — biggest win |
| 4 | Staged progress + moving bar instead of skeletons | **Shipped** |
| 5 | Stagger the review rows in | **Shipped** |
| 6 | Chunked upload while recording | **Rejected** — see §5 |

## 4. Decisions worth recording

**Warm-up ping (§3.1).** Edge Functions scale to zero, so the 1–3s cold start
used to land entirely *after* the shopkeeper stopped talking — the one moment
they are actively waiting. Tapping the mic now fires `{"ping": true}`, which
short-circuits in `parse-sale` before any Gemini call (so it costs no tokens)
and before every validation branch (so it needs no `candidates`). The client
swallows all failures: a deploy predating the ping branch simply 400s, and the
container is warm either way — which is the entire point.

**800ms, not 600ms (§3.2).** `SpeechEndDetector.trailingSilenceSamples` went
6 → 4 (at `micLevelInterval`'s 5 samples/sec). This is dead time on *every*
sale. It was not cut further because below ~600ms a natural mid-sentence pause
— "two kilos of rice … and one Pepsi" — starts truncating the second half,
which costs far more than the 200ms it would save. Both ends are pinned by test.

**Dismissal backgrounds, it does not cancel (§3.3).** `showVoiceSaleSheet`'s
`whenComplete` used to call `reset()`, which cancelled the in-flight parse.
It now calls `releaseSheet()`: in the `thinking` phase the session is left
alone and a `background` flag is set; every other phase still resets exactly as
before. The shopkeeper has *already spoken the sale*, so throwing the work away
would make them say it twice.

**Banner, not snackbar.** A shopkeeper mid-transaction may not look up for half
a minute. A snackbar would time out and the parsed sale would be lost with no
trace. `VoiceReadyBanner` is persistent, sits beside `OfflineBanner` in
`app.dart` (so it survives navigating away from wherever the sale started), and
renders zero height when nothing is waiting. A failed background parse is
claimed through the same banner but styled as a problem, not good news — its
error pane is where "type it instead" lives.

**The progress stages are paced on a timer, and the code says so.** `parse-sale`
transcribes and parses in a *single* Gemini call and reports nothing until it
returns, so there is no real intermediate signal to display. The stages are
honest *labels* on a plausible schedule, not measurements. The bar creeps
toward 92% and waits: a bar that reaches 100% before the answer lands is worse
than no bar at all.

**The dismiss hint is load-bearing.** "You can close this — we'll buzz you when
it's ready" is what makes §3.3 discoverable. Without it nobody learns they may
walk away, and the whole feature is invisible.

## 5. Rejected: chunked upload while recording

Investigated in `package:record` 7.1.1 before building. **Do not re-open without
new evidence** — the analysis:

- Audio is already AAC-LC at 32kbps mono/16kHz ≈ **80KB** for a full 15s clip
  after base64. That is ~0.2–0.6s of upload on 4G, ~1.3s on 3G.
- The Gemini call is 2–5s. **Upload is a minority of the total wait**, so the
  ceiling on this optimization is below what the warm-up ping (§4) already
  delivers, at a fraction of the risk.
- Implementing it means switching from file recording to `startStream`, plus a
  new multi-chunk ingest protocol on `parse-sale`: Gemini needs complete,
  container-valid audio, and a partial `.m4a` is not decodable because the
  `moov` atom that makes it playable is written last.
- Edge Functions cannot be deployed or probed from this repo (server ops are the
  user's), so it would be an unverifiable protocol change to the feature the
  demo depends on — one that took three prior specs to stabilize.

Revisit only if measurement shows upload dominating the wait on real shop
connections.

## 6. Testing

`test/voice_background_parse_test.dart` (6), `test/widgets/voice_ready_banner_test.dart`
(4), `test/widgets/voice_thinking_pane_test.dart` (3), plus 2 in
`test/voice_level_test.dart` pinning the silence window at both ends. Suite went
299 → 314.

Note for future widget tests here: never `pumpAndSettle` the thinking pane — its
active stage carries a `CircularProgressIndicator`, which by design never
settles. And inside `testWidgets` time is fake, so polling with
`Future.delayed` spins forever; use `tester.pump()`.

## 7. Follow-up

`parse-sale` must be redeployed (needs **both** `index.ts` and
`quantity_words.ts`) for the ping to stop costing a rejected request. Until
then the container still warms, which is most of the benefit.
