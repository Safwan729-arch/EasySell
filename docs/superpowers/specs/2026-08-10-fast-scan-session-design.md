# Fast Scan Session — Design

**Date:** 2026-08-10
**Branch:** `feat/fast-scan` (stacked on `feat/cart-discount`, as that was stacked on `feat/voice-wait-ux`)
**Status:** Approved design, pending spec review

Make scanning a multi-item basket fast. Today the scan flow is strictly serial —
camera → wait → sheet → camera — and a ten-item customer costs roughly **40 taps
and 75 seconds**, most of it the shopkeeper standing still while a Gemini call
completes. This replaces the loop with a **session**: a live viewfinder that
never closes, recognition that runs in the background, and one review tray that
commits everything at once.

---

## 1. The problem, measured

Per item, the current [`scan_screen.dart`](../../../lib/features/scan/presentation/scan_screen.dart)
`_run()` loop costs:

| Step | Cost |
|---|---|
| `image_picker` launches the system camera | ~1s |
| Shutter + Android's "use this photo" confirm | 2 taps |
| Upload + `recognize-product` round trip | **2–5s, camera closed, nothing else possible** |
| "Did you mean" picker (sometimes) | 1 tap |
| `showAddToCartSheet` → Add | 1 tap |
| Camera relaunches | ~1s |

The user (shopkeeper, testing on a physical S22) reported **both** the camera
round trip and the AI wait as painful, and summarised it as "the system feels
very slow and time consuming". No single fix addresses that; the design has to
attack the camera round trip and the blocking wait together.

**The structural fault is that nothing overlaps.** Ten items means ten dead
pauses laid end to end, when the phone is perfectly able to capture during them.

## 2. Approaches considered

| Approach | Verdict |
|---|---|
| **A. Live viewfinder + background recognition + review tray** | **Chosen.** Attacks both reported bottlenecks. |
| B. Keep `image_picker`, only move recognition off the critical path | Rejected — halves the win and leaves the camera round trip, which the user explicitly named. |
| C. One photo of several items on the counter, model returns a list | Rejected — recognition accuracy collapses on cluttered, overlapping, angled packaging, and it cannot reliably count three identical bottles. When wrong, the recovery is hand-editing a list, i.e. the slowest possible outcome. Revisitable later as an *extra* button, never the main path. |
| D. Barcode scanning | Not re-opened. Ruled out 2026-07-04 as "unrealistic for small/medium shops" ([[2026-07-04-vision-product-scan-design]] §1). Noted for the record that a barcode read is offline, instant and unambiguous, so it would beat everything here *for packaged goods* — if that premise ever changes, this is the first thing to revisit. |

## 3. Architecture

Capture and recognition are decoupled. A tap on the shutter does four things and
blocks on none of them:

```
tap shutter ──┬──► frame captured (instant) ──► chip appended, status=recognizing
              │
              └──► recognition queued (max 3 in flight) ──► chip resolves, any order

  ...viewfinder is ready for the next tap immediately
```

### 3.1 Session state

New `ScanSessionController` (Riverpod `Notifier<ScanSession>`), living at
`lib/features/scan/presentation/scan_session_controller.dart`:

```dart
enum ScanItemStatus { recognizing, resolved, ambiguous, unmatched, failed }

class ScanItem {
  final String id;             // local, stable chip key
  final ScanItemStatus status;
  final Product? product;      // resolved
  final List<Product> choices; // ambiguous
  final String? readLabel;     // reuses the existing ScanOutcome.readLabel
  final double quantity;
  final Uint8List? frame;      // held for retry; dropped on success
}
```

Methods: `capture(bytes)`, `setChoice(itemId, product)`, `setQuantity`,
`remove`, `retry`, `addAllToCart()`.

### 3.2 Merge on resolve

Three shutter presses on the same product must not produce three chips. When a
recognition resolves to a product **already held by a resolved chip**, it folds
into that chip and bumps its quantity; the redundant chip is dropped.

Merging happens at *resolve* time, not capture time, because a pending chip has
no product yet and results arrive out of order. This is what makes "tap three
times for three bottles" work, and it is why the modal quantity sheet leaves the
common path entirely. The exceptions (2.5 kg of rice) get an inline `− 3 +`
stepper on the chip.

### 3.3 Concurrency cap: 3

In-flight recognitions are capped at **3**; further captures queue.

Chosen because a person cannot press a shutter much faster than ~1/s and each
call takes ~3s, so three-in-flight is roughly the natural steady state anyway.
Higher buys no wall-clock improvement and invites rate-limit rejections. Lower
would re-serialise the thing this design exists to parallelise.

### 3.4 The camera must be fakeable

Real cameras do not exist in `flutter test`, and this project's guard against
regression is its suite. The camera therefore sits behind a narrow interface —
`initialize / preview / capture / dispose` — with a real implementation wrapping
the `camera` package and a fake returning canned bytes.

Everything that carries risk (queueing, merging, clamping, tray rendering,
add-all) is then testable. Only the thin plugin wrapper needs a device.

### 3.5 Capture resolution — verify on device

The current code deliberately shoots at `maxWidth: 768, imageQuality: 60`
because "the smaller payload noticeably cuts scan latency on slow shop
connections" ([`scan_controller.dart:50`](../../../lib/features/scan/presentation/scan_controller.dart#L50)).

The `camera` package offers presets rather than a max width, so the starting
point is `ResolutionPreset.medium` (640×480) as the closest match. **This is the
one number in the design not backed by evidence** — small print on packaging is
exactly where 640 could read worse than 768. If on-device recognition quality
drops, move to `ResolutionPreset.high` (1280×720) and accept the larger upload.
One-line change; flagged in the probe checklist.

## 4. Screen layout

```
┌─────────────────────────────┐
│      LIVE VIEWFINDER        │  never leaves the app
│            ( ⬤ )            │
├─────────────────────────────┤
│ ⚡ Pepsi 1L   Biscuit   Soap │  top sellers, one tap = +1
├─────────────────────────────┤
│ [Pepsi ×3] [Rice 2kg] [ … ] │  tray
├─────────────────────────────┤
│   Add 5 items · ৳540        │
└─────────────────────────────┘
```

**The tray is the confirmation step.** Nothing reaches the cart until *Add*.
This preserves the standing rule that AI output is never auto-committed
(CLAUDE.md §6) — it moves confirmation from *once per item* to *once per
customer*. See §8 for the cost of that move.

## 5. Top-sellers strip

A horizontally scrolling row of the ~12 best-selling in-stock products. A tap
appends a chip that is **already `resolved`** (no recognition, no network) to
**the tray** — not straight to the cart — so every path through the screen
converges on the same review-then-commit step. A strip tap for a product already
in the tray merges by the same §3.2 rule.

Built entirely on what already exists: `bestSellersProvider` and
`aggregateBestSellers` in
[`analytics_controller.dart`](../../../lib/features/analytics/presentation/analytics_controller.dart),
themselves derived from `TransactionRepository.recentSales()`. **No migration,
nothing for the user to deploy** — which matters, because `0009` (cart discount)
is still unapplied on their side.

Hidden entirely when the shop has no sales history, rather than showing
alphabetical filler that would teach the shopkeeper to ignore the row.

## 6. Prompt token trim

While costing the design, `recognize-product` turned out to `JSON.stringify` the
**entire product catalog into every request**
([`index.ts:55`](../../../supabase/functions/recognize-product/index.ts#L55)):

| Part of the request | Tokens (~100 products) |
|---|---|
| Product catalog | **~3,500** |
| The photo | ~300 |
| Instructions + schema | ~200 |
| Response | <100 |

So ~90% of per-scan spend re-sends a list that has not changed since yesterday,
and it scales with catalog size — 300 products triples the bill for
photographing one bottle.

Each candidate currently carries a full UUID, ~20 tokens of noise the model
never needs to understand, only echo back:

```json
{"id":"550e8400-e29b-41d4-a716-446655440000","name":"Pepsi","brand":"PepsiCo","variant":"1L"}
{"i":7,"name":"Pepsi","brand":"PepsiCo","variant":"1L"}
```

Replacing the UUID with the candidate's list index and mapping back client-side
cuts roughly **40% of tokens per scan** at identical accuracy.

**Only token counts are claimed here, never prices.** The per-token rate for
`gemini-3.6-flash` is not verifiable from this repo and was deliberately not
guessed at; multiply by whatever the Google AI Studio console shows.

### 6.1 Deploy order is the opposite of 0009 — and the failure is silent

`buildCandidates` feeds **both** AI flows; `parse-sale` uses it with
`includeUnit: true`. If the app emits `i` and a deployed function still expects
`id`, `normalize()`'s id-validation set ([`index.ts:146`](../../../supabase/functions/recognize-product/index.ts#L146))
matches nothing and every scan degrades to **"no match"** — no error, no crash,
just an app that quietly stopped recognising things. That is worse than the
`0009` failure mode, which at least fails loudly.

Mitigation: both Edge Functions accept **either** shape — `id` if present, else
`i`. That makes the functions safe to deploy while the old app is still
installed.

> **Deploy the Edge Functions FIRST, then install the app.** Backwards from
> `0009`, where the migration had to precede the app. Goes at the top of the
> probe checklist rather than relying on memory.

## 7. Error handling

Governing rule: **one bad chip never kills the session.** The shopkeeper keeps
shooting through failures and cleans up at the end.

- **Recognition fails** → that chip alone offers retry. Its frame is held in
  memory so retry re-sends the photo instead of demanding a re-shoot; bytes drop
  on success.
- **Offline** → same path; frames held, retry when connectivity returns.
- **Camera permission denied** → explanation + a button into system settings,
  not a black screen.
- **App backgrounded** → camera released and rebuilt on resume. This is the
  `camera` package's best-known trap; skipping it yields a frozen preview or a
  leaked handle. The tray survives untouched.
- **Back with unadded chips** → confirm *Add them* / *Discard*. Never a silent
  loss.
- **Out of stock** → a resolved chip with nothing left is flagged and excluded
  from the count; quantities clamp via the existing `remainingStockFor`.

**The Add button** is disabled while anything is in flight, reading
*"Recognizing 2…"*, then *"Add 5 items · ৳540"* — a ~3s worst case after the
last shot. Leftover unidentified chips prompt once: *"1 item couldn't be
identified — add the other 5 and discard it?"* One decision, nothing lost
quietly.

## 8. The cost of this design (recorded deliberately)

**The per-item confirmation screen is a safety mechanism, and this design
weakens it.** Today the shopkeeper is *forced* to look at every recognition
while the item is still in their hand, so a mistake is caught immediately.
Afterwards they scan ten things quickly and glance at a row of chips — and
people will eventually stop reading that row and just press Add.

The tray is a deliberately weaker guard than what it replaces. The trade was
accepted on the reasoning that the current flow is slow enough to risk not being
used at all, and an unused safeguard catches nothing. **If wrong items start
reaching real sales, this section is the place to start** — the fix would be
raising the confidence threshold at which a chip auto-resolves rather than
reverting the session model.

Other accepted costs: a live preview draws materially more power and heat than a
camera open for two seconds; the `camera` package is Member C's seam by the team
contract (CLAUDE.md §1) and the user explicitly authorised crossing it; the
strip is empty on day one and will drift toward recommending discontinued stock.

## 9. Testing

Everything but the plugin wrapper runs behind the fake camera.

- **Unit (session):** merge-on-resolve (three Pepsi captures → one chip ×3),
  out-of-order resolution, the 3-in-flight cap holding under a burst of 10,
  quantity clamping, retry reusing the held frame.
- **Unit (candidates):** index ↔ product-id round trip; both payload shapes
  accepted.
- **Widget:** every chip status renders; a strip tap lands in the tray; add-all
  merges correctly into the cart; back-with-unadded prompts.
- **Device (user only):** preview renders, label legibility at the chosen
  resolution, background/resume, permission denial.

`flutter analyze` clean and the full suite green after each task. Never
`dart format .` repo-wide (it reflows ~50 committed files) — touched paths only,
and only where the file was already formatted at HEAD.

## 10. Out of scope

One photo of multiple items (§2 C); barcodes (§2 D); offline scanning; the strip
anywhere outside the scan screen; multi-step undo. Each is its own conversation.

## 11. Rollback

Additive and branch-isolated. Reverting the branch restores `image_picker` and
the serial loop. The Edge Function change is backward-compatible by
construction (§6.1), so a rolled-back app keeps working against a deployed
function.

## 12. Outcomes

The design as specified shipped: live viewfinder, background recognition
capped at 3-in-flight, merge-on-resolve, the top-sellers strip, the review
tray as the sole confirmation point, and the prompt token trim from §6.

**§3.5's capture resolution — still unverified.** `ResolutionPreset.medium`
(640×480) shipped exactly as designed and is still the one number in this
feature chosen without evidence, not backed by a measurement. The old flow
shot at `maxWidth: 768`, and small print on packaging is precisely where 640
could read worse. This stays marked **UNVERIFIED** until the user runs probe
step 5 in `supabase/README.md` on the physical S22 and reports back. If it
regresses, the fix is a one-line change to `.high` in
`lib/features/scan/data/real_scan_camera.dart` — already flagged at the point
of use.

**A second camera failure mode was added.** The real camera wrapper now
distinguishes `CameraUnavailable` (the device reports no cameras at all) from
`CameraPermissionDenied` (a camera exists but permission was refused). The
scan screen shows different copy for each, and — deliberately — the
no-camera case has no "Open settings" button, because there is no permission
to grant; sending the shopkeeper into Settings to fix a problem Settings
cannot fix would be worse than no button at all.

**Review caught four defects in the plan's own code before merge:**
1. A thrown recognition future permanently leaked its queue slot, which over
   a session was enough to wedge the 3-in-flight cap and kill the session —
   fixed by freeing the slot in a `finally`.
2. `choose()` keyed by a stale chip id silently inflated an unrelated chip's
   quantity instead of failing — fixed by guarding `choose`/`retry` against
   ids that no longer resolve to a live chip.
3. The camera controller leaked on re-initialize and again on a post-
   `bindToLifecycle` failure — fixed by disposing the previous controller in
   both paths.
4. The widget test guarding the core safety property of this whole
   redesign — *the shutter must never pop a modal over the live camera* — was
   **blind**. It asserted `find.byType(ModalBarrier)` finds nothing, but
   `showDialog`/`showModalBottomSheet` render `AnimatedModalBarrier`, a
   sibling type of `ModalBarrier`, not a subtype — so the assertion passed
   whether or not a modal was actually showing. Two plausible-looking
   assertions in a row failed to catch this; it surfaced only because the fix
   was mutation-checked (the test was confirmed to fail against a
   deliberately reintroduced bug) rather than trusted on read. Record this as
   a standing lesson: an untested assertion about widget presence/absence in
   Flutter should be verified against the actual runtime type tree, not the
   type it's presumed to render as.

**The voice path is untouched.** `parse-sale` and its caller still send
UUID-keyed candidates (`id`, not `i`). The `buildCandidates` shim in
`lib/features/scan/domain/scan_candidates.dart` exists solely to produce both
shapes from one call site and has no reason to exist once voice migrates to
index-keyed candidates too — the final task in this feature, if it runs,
removes it. Until then it is not dead code.

*(Superseded: the voice task did run. `parse-sale` and its caller now send
index-keyed candidates too, indices are translated back to product ids at the
parse boundary via `VoiceParseResult.resolveIds`, and the `buildCandidates`
shim is gone.)*

## 13. Carried defects — known and deliberately not fixed

Two items survived the final whole-branch review's fix wave. Both were
adjudicated as bounded, and both are recorded here because a future session
will otherwise rediscover them from scratch.

**1. A superseded `initialize()` can still stomp the screen's `setState`.**
`RealScanCamera.initialize()` carries a generation counter, so a concurrent
call that gets superseded disposes its own `CameraController` instead of
leaking bound hardware. But `ScanSessionScreen._start()` has no generation
tracking of its own, so whichever `await` resolves *last* wins the `setState`
regardless of which call the camera layer considers current.

Trigger: the app backgrounds mid-`initialize()` (firing `inactive` →
`dispose()`) and resumes before the first call settles (firing `resumed` → a
second `_start()`). That is the same sequence the camera-level fix exists for,
so this gap is reachable, not theoretical. If the two calls disagree — the
stale one throwing after the fresh one succeeded — the screen can show a
permission error while a working camera is bound underneath, or the reverse.

Carried because: no crash, no data loss, nowhere near the money path, confined
to camera setup, and one tap of the retry button recovers it. Fixing it means
adding generation tracking to the screen as well. **If a shopkeeper reports a
camera error that a retry immediately clears, this is the first suspect.**

**2. One test for the overlapping-shutter fix is not load-bearing.**
`scan_session_controller_test.dart`'s "a capture whose camera call throws
neither crashes nor leaves a chip behind" passes with the fix fully reverted —
`ScanSessionController.capture()` awaits the camera *before* mutating state, so
it never could have left a phantom chip. The assertion is true and worth
keeping; it just proves an invariant that already held. The two widget tests in
`scan_session_screen_test.dart` are what actually close that finding, both
confirmed by revert-and-rerun. Do not treat the controller test as coverage for
the in-flight guard.
