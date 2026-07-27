# Voice Sale: Noise Resilience & Timeout Fix

**Date:** 2026-07-27
**Feature owner:** Member A (Full Stack)
**Scope:** `supabase/functions/parse-sale/index.ts`, `lib/features/voice/**`
**Hard constraint:** every load-bearing fix must work on **all phones**, not just
high-end Android. No change may make voice *worse* on any device.

---

## 1. Problem

Voice-to-cart fails in noisy shop environments. The observed failure mode is
**latency, not accuracy**: the thinking pane hangs for ~30 seconds and then
errors out with "Could not understand that right now." That message comes from
`mapVoiceFailure` handling the `TimeoutException` thrown by the 30s timeout at
`voice_sale_repository.dart:52`.

### 1.1 Why noise costs time

The model is never told that background noise exists, so it attempts to
transcribe *everything* it hears — the customer, the fan, bystanders on the
street. More audible content means more generated text, and generation time
scales with output length. Three compounding factors:

1. **No output ceiling.** `generationConfig` at `index.ts:113-122` sets
   `responseMimeType`, `responseSchema`, `temperature`, and `thinkingConfig` —
   but **no `maxOutputTokens`**. A model confused by noise can generate until it
   hits the model default, with nothing to stop it.
2. **No server-side deadline.** The Gemini `fetch` has no `AbortSignal`, so the
   Edge Function waits indefinitely and the client is the only thing that ever
   gives up — at 30s.
3. **Inflated payload.** `RecordConfig(encoder: aacLc)` at
   `audio_recorder.dart:58-61` takes every package default: 44.1 kHz, **stereo**,
   128 kbps ≈ **16 KB per second of speech**, then `base64Encode` adds 33%. A
   12-second clip becomes a ~250 KB JSON POST, and upload time counts against
   the same 30s budget.

Unbounded clip length compounds all three: nothing caps recording duration, and
in noise shopkeepers speak longer and repeat themselves.

## 2. Cross-device verification (what shaped this design)

The "all phones" constraint was checked against the plugin's native source
rather than assumed. The findings split the fixes into two reliability classes.

| Setting | Cross-device behavior | Verdict |
|---|---|---|
| `noiseSuppress` / `echoCancel` / `autoGain` | `AudioEffectsManager.apply()` guards each with `isAvailable()` and logs when missing | **Safe** — silent no-op, never throws |
| `androidConfig.audioSource` | Passed to `AudioRecord(...)`; `VOICE_RECOGNITION` exists since API 10, platform falls back internally | **Safe** |
| `sampleRate` / `numChannels` / `bitRate` | `PCMReader.calculateBufferSize` **throws** `"Recording config is not supported by the hardware"` when `AudioRecord.getMinBufferSize` returns `ERROR_BAD_VALUE`; `createReader` throws if `AudioRecord` fails to initialize | **NOT safe to hardcode** |

The second row is the critical one. `VoiceController.startListening` catches a
`start()` throw and reports `noSpeech` (`voice_controller.dart:87-94`), so a
hardcoded 16 kHz mono profile would leave voice **completely dead** on any
device that rejects it — trading a slow feature for a broken one. 16 kHz mono is
near-universal, but "near-universal" does not satisfy the constraint. This is
why §4 specifies a fallback ladder rather than a flat config change.

**iOS caveat.** `echoCancel` and `autoGain` are wired only into
`RecorderStreamDelegate.swift` (the `startStream` path). This app uses file
recording via `start(path:)`, and `noiseSuppress` is parsed into
`RecordConfig.swift` but never applied on iOS at all. **On iPhone these three
flags are no-ops.** iOS therefore gains nothing from Layer 3 and depends
entirely on Layers 1, 2, and 4 — which is precisely why the load-bearing work
lives there.

## 3. Layer 1 — Server-side bounds (universal; the actual timeout fix)

All changes in `supabase/functions/parse-sale/index.ts`. Zero device dependency:
an iPhone SE and a Galaxy S22 benefit identically.

**3.1 Output ceiling.** Add `maxOutputTokens: 1024` to `generationConfig`,
overridable via a `GEMINI_VOICE_MAX_TOKENS` secret. A realistic five-item sale
produces roughly 300 output tokens, so 1024 leaves comfortable headroom while
still capping a runaway. Note that on Gemini 3.x, thinking tokens count against
this budget; `thinkingLevel: "minimal"` is already set, keeping that draw small.
If the cap is ever hit the reply truncates, `JSON.parse` fails, and the existing
catch returns 502 — a fast, honest error instead of a 30s hang.

**3.2 Server-side deadline.** Add `signal: AbortSignal.timeout(20_000)` to the
Gemini `fetch`. An abort throws, the existing catch maps it to 502, and the app
shows its error state at ~20s instead of dangling to the client's 30s. The
client timeout stays at 30s as a backstop for network stalls.

**3.3 Prompt hardening.** The instruction at `index.ts:33-55` never mentions
noise. Add a rule: transcribe only the primary/nearest speaker; ignore
background chatter, ambient noise, and other voices; `heard_text` covers only
the sale sentence. This attacks the root cause — the model transcribing the
whole room — rather than merely truncating the result. MEMBER B owns prompt
tuning; the seam comment stays.

**3.4 Timing instrumentation.** `console.error` a timing breakdown (request
received → Gemini call duration → total). Confirms the diagnosis against real
noisy failures instead of leaving it inferred. No response-shape change.

**Response contract is unchanged.** No app-side changes follow from Layer 1.

## 4. Layer 2 — Payload shrink with a fallback ladder (universal)

In `lib/features/voice/data/audio_recorder.dart`. Speech-tuned capture:
**mono / 16 kHz / 32 kbps**, cutting the wire cost from ~16 KB/s to ~4 KB/s of
speech (4×), before base64's 33%.

Because §2 established these three fields can throw, `RecordAudioRecorder.start()`
becomes a two-rung ladder:

1. Attempt the speech profile.
2. On throw: `cancel()` to release any partial session, pick a fresh temp path,
   and retry once with today's rates (44.1 kHz / stereo / 128 kbps) —
   **keeping the Layer 3 effect flags**, since §2 verified those never throw.
3. If the fallback also throws, propagate as today (controller reports
   `noSpeech`).

Worst case on an exotic device: exactly today's behavior. Best case: 4× less to
upload. The ladder is what makes this optimization safe to ship universally.

**Recording cap.** `VoiceController` starts a 15-second `Timer` on entering
`listening` that auto-invokes `stopAndParse()`. A clip can then never grow
unbounded. The timer is session-aware and must be cancelled in `reset()`, on
manual `stopAndParse()`, and on any transition out of `listening`, so a stale
timer can never fire into a later session. Auto-stop reuses the normal parse
path — no new phase, no new error state.

## 5. Layer 3 — Best-effort mic tuning (upside where supported, never harmful)

Added to the speech profile and preserved on the fallback rung:

- `androidConfig.audioSource: AndroidAudioSource.voiceRecognition` — routes to
  the ASR-tuned front-end that Google's own speech recognition uses. Typically
  the single largest real-world gain on Android.
- `noiseSuppress: true`, `autoGain: true` — best-effort for devices where the
  source alone does not engage the effects.
- `echoCancel: **false**` — deliberately off. Echo cancellation targets speaker
  playback bleeding into the mic, which is not the failure here, and the package
  documents that it *lowers recording volume*. Enabling it would cost signal to
  solve a problem this app does not have.

Real gains on most Android hardware; silent no-ops on iOS file recording and on
Android devices lacking the effects. Framed as a bonus, never as the fix.

## 6. Layer 4 — Escape hatch (universal)

`_ErrorPane` (`voice_sale_sheet.dart:242`) currently offers only "Try again",
which repeats the same slow failure in the same noisy room. It gains a second
action that opens the transcript editor, letting the shopkeeper type the sale
and run it through the existing `reparseFromText` text path.

`_editTranscript` is today a private method of `VoiceReviewSheet`
(`voice_review_sheet.dart:60-96`). It is lifted to a shared top-level function
in a new `lib/features/voice/presentation/voice_transcript_dialog.dart`, called
by both the review sheet and the error pane. The existing controller-disposal
discipline (post-frame `dispose`, documented at lines 88-95) moves with it
verbatim. From the error pane it opens prefilled with `state.heardText ?? ''` —
empty on a timeout, since nothing was heard.

Requires one new l10n key (an "Type it instead" action label) in `app_en.arb`
and its Bengali counterpart, following the existing `voice_*` naming.

## 7. Testing

- **Unit:** `RecordAudioRecorder.start()` falls back to default rates when the
  speech profile throws, and still produces a usable recording. This is the test
  that protects the "all phones" constraint and must exist.
- **Unit:** the 15s cap fires `stopAndParse` exactly once, and a cancelled timer
  never fires into a later session.
- **Direct probe:** POST noisy audio to the deployed function; assert a bounded
  response and confirm the timing log shows the Gemini segment under the 20s
  abort.
- **Failure path:** force a slow/failed Gemini call; assert a ~20s 502 rather
  than a 30s client timeout.
- **On-device (S22):** record a sale in a genuinely noisy setting; confirm it
  returns within a usable time and the review sheet is correct.
- **Regression:** confirm quiet-room voice accuracy has not degraded from the
  lower bitrate — 32 kbps mono AAC-LC is well above speech intelligibility
  thresholds and Gemini downsamples to 16 kHz regardless, but this is asserted
  by test, not assumed.

## 8. Out of scope

- On-device transcription (`speech_to_text`) as a replacement for the audio
  upload. Considered and rejected: on-device ASR degrades *worse* in noise than
  Gemini and has unreliable Bengali/code-switched support, trading a latency
  problem for an accuracy problem in exactly the conditions being fixed.
- Live amplitude/level metering in the listening pane. `getAmplitude()` is
  available cross-platform and would tell a shopkeeper whether they are being
  heard, but it does not address the timeout and is deferred.
- Streaming/chunked upload overlapping record and transmit.
- Any change to the `parse-sale` request/response contract.
- Scan (`recognize-product`) — untouched.

## 9. Rollback

Layers are independent and revert cleanly in isolation. Layer 1 is one Edge
Function file (revert + redeploy). Layers 2, 3, and 4 are app-side and ship
together in the same build. Nothing here changes the database, the function
contract, or any stored secret, so rollback needs no coordination beyond a
revert.
