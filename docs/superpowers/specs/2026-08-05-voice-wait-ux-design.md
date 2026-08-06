# Voice Sale: Making the Post-Speech Wait Bearable — Design

**Date:** 2026-08-05
**Feature owner:** Member A (Full Stack)
**Scope:** `lib/features/voice/**`, `lib/app.dart`, `supabase/functions/parse-sale/index.ts`
**Shipped as:** commit `53ee72b` on `feat/voice-wait-ux`, then two follow-up
fixes to the backgrounding half of it — `96830d2` (§8) and `e6e672d` (§9)
**Related:**
- [[2026-07-27-voice-noise-latency-design]] — fixed the 30s *hang*; this one
  addresses the normal-case *wait*
- [[2026-07-22-voice-sale-assistant-design]] — the original "speak a sale →
  cart" flow this is the waiting room for
- [[2026-07-12-offline-banner-design]] — the banner in §4 sits beside that one,
  and §9 is a hazard they share

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

The follow-ups (§8, §9) took it to 322: `voice_background_parse_test.dart` grew
to 9, `voice_ready_banner_test.dart` to 7, and
`test/widgets/voice_banner_reopen_test.dart` (2) covers the real mounting.

Gotchas here, all of which cost time:

- **Never `pumpAndSettle` the thinking pane or a *pending* banner.** Both carry
  a `CircularProgressIndicator`, which by design never settles — the suite
  hangs with no output rather than failing.
- **A single `pump()` is not enough before tapping the banner.** It is
  mid-`AnimatedSwitcher` entrance, wrapped in an `IgnorePointer`, so taps miss
  with only a "would not hit test" warning. Pump ~300ms — and, per above, not
  `pumpAndSettle`.
- **Inside `testWidgets` time is fake**, so polling with `Future.delayed` spins
  forever. Use `tester.pump()`, bounded, with an `expect` after the loop so a
  regression fails instead of hanging.
- **`await` on a call that only completes when a faked future does** deadlocks
  the test the same way; `unawaited` it.

## 7. Follow-up

`parse-sale` must be redeployed (needs **both** `index.ts` and
`quantity_words.ts`) for the ping to stop costing a rejected request. Until
then the container still warms, which is most of the benefit.

---

## 8. Follow-up fix: the dead zone (commit `96830d2`)

Reported from the device: the thinking pane had no minimize button (you had to
tap empty space), and once minimized *there was no way back* until the parse
finished on its own.

**Root cause: one over-narrow condition.** The banner keyed off
`hasBackgroundResult`, which required `reviewing || error` — a *finished*
parse. Between dismissal and the result landing, `hasBackgroundSale` was false
everywhere, so the sale existed but rendered nowhere. §4 shipped the banner as
"here is your finished cart" when what backgrounding actually needs is a
**live task indicator**: the handle must cover the sale's whole life, and
being able to reopen a finished one is almost a side effect.

The getter now spans `thinking` too, and `isBackgroundPending` distinguishes
the states. Everything else follows from that one widening.

**The unreported symptom was the serious one.** During that dead zone, tapping
the mic called `startListening`, which bumps the session counter — so the
in-flight parse's result was dropped when it landed. A sale the shopkeeper had
*already spoken* vanished with no error and no trace. The three reported
symptoms were annoying; this one silently lost work.

**Fixed by routing, not by asking.** A "you have a sale in progress, discard
it?" dialog was rejected: two voice sales cannot run at once, so there is
nothing to choose between. Every entry point (mic *and* banner) now calls
`resumeFromBackground()` first, so tapping the mic mid-parse **reopens** the
existing sale. There is no path left that can lose it by accident.

**Discarding therefore needed its own affordance** — the ✕ on the working
banner. Abandoning a misspoken sale is legitimate; it just has to be a
deliberate act with a button behind it rather than a side effect of tapping
something else.

Also: an explicit "Continue in background" button (the hint pointed at a
gesture nothing advertised), and the stage spinner was inset 2px inside an 18px
box at 2px stroke, rendering as a faint dot — it now fills its slot.

## 9. Follow-up fix: the banner could not open anything (commit `e6e672d`)

Reported next: tapping the ready banner made **the banner disappear and nothing
open**. Tapping the mic afterwards showed the cart intact, which made it look
like the mic was "restoring" the sale.

**Root cause: the banner has no `Navigator` above it.** `WidgetsApp` calls
`builder` with the router as its *child*
(`flutter/lib/src/widgets/app.dart`, `result = Builder(...builder(context,
routing))`), so anything mounted in `app.dart`'s builder — this banner and
[[2026-07-12-offline-banner-design|the offline one]] — is an **ancestor** of
the router's Navigator. `showModalBottomSheet` resolves
`Navigator.of(context)`, which only ever searches upwards, so pushing from the
banner's context threw *"Navigator operation requested with a context that does
not include a Navigator"*. The exception surfaced only in the console.

`useRootNavigator: true` does **not** fix this. It changes
`findAncestorStateOfType` to `findRootAncestorStateOfType` — still upwards, and
in router mode there is nothing above to find. The fix is to push from a
context that is *inside* a Navigator: `app_router.dart`'s navigator key was
private, is now `rootNavigatorKey`, and `showVoiceSaleSheet` falls back to
`rootNavigatorKey.currentContext` whenever the caller has no Navigator of its
own (`Navigator.of` accepts the Navigator element's own context).

**Order matters, and it explains the symptom.** `resumeFromBackground()` ran
*first*, so the tap consumed the background flag — hiding the banner — and only
then crashed. The claim now happens after the host context is resolved and the
guard has passed, so a tap that cannot open the sheet leaves the handle on
screen instead of stranding a parsed cart with nothing pointing at it. Pinned
by test.

**Why a green suite missed a crash on the app's most visible button.**
`voice_ready_banner_test.dart` mounts the banner under `MaterialApp(home:)`,
which builds a Navigator around its child — so in the test the banner had
exactly the ancestor the real app denies it. The harness handed the widget the
opposite of production and every navigation assertion passed. Its doc comment
even asserted the correct requirement while the scaffold quietly violated it.

**Rule to carry forward: a widget mounted somewhere structurally unusual must
be tested in that structure.** `voice_banner_reopen_test.dart` builds
`MaterialApp.router` + `GoRouter` and reproduces `app.dart`'s builder verbatim.
Route-pushing cases for anything above the router belong there, not in the
plain-`MaterialApp` harness.
