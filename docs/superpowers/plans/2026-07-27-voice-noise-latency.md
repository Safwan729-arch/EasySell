# Voice Noise Resilience & Timeout Fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop voice-to-cart from hanging ~30s and erroring in noisy shops, using fixes that work on every phone rather than only high-end Android.

**Architecture:** Four independent layers. Layer 1 bounds the Gemini call server-side (`maxOutputTokens` + `AbortSignal` + a noise-aware prompt) — this is the actual timeout fix and is fully device-independent. Layer 2 shrinks the upload ~4× behind a fallback ladder so an unsupported capture profile can never break recording. Layer 3 adds best-effort mic tuning that no-ops where unsupported. Layer 4 gives the error state a "type it instead" escape hatch via the existing text-parse path.

**Tech Stack:** Flutter + Riverpod, `package:record` 7.1.1, Supabase Edge Functions (Deno/TypeScript), Google Gemini `generateContent`.

**Spec:** [docs/superpowers/specs/2026-07-27-voice-noise-latency-design.md](../specs/2026-07-27-voice-noise-latency-design.md)

## Global Constraints

- **Every load-bearing fix must work on all phones.** No change may make voice worse on any device.
- **`sampleRate` / `numChannels` / `bitRate` can throw** — `PCMReader.calculateBufferSize` throws `"Recording config is not supported by the hardware"` when `AudioRecord.getMinBufferSize` returns `ERROR_BAD_VALUE`. Never hardcode these without a fallback.
- **`noiseSuppress` / `echoCancel` / `autoGain` never throw** — `AudioEffectsManager.apply()` guards each with `isAvailable()`. Safe to set unconditionally.
- **On iOS these three flags are no-ops** for file recording (wired only into `RecorderStreamDelegate.swift`, the streaming path). iOS gains come from Layers 1, 2, and 4 only.
- **`echoCancel` must be `false`** — it targets speaker-playback bleed (not this failure) and the package documents that it lowers recording volume.
- **The `parse-sale` request/response contract is frozen.** No field added, removed, or renamed.
- **Client timeout stays 30s** (`voice_sale_repository.dart:52`) as a network backstop; the server aborts first at 20s. **Revised post-launch:** the final whole-branch review found 20s didn't compose with upload + cold start inside the 30s client budget on the fallback capture rung; the server abort default is now 15000ms (env override clamped to a 25000ms ceiling). Client timeout is unchanged.
- Run `flutter analyze` before every commit. **Never run `dart format .` repo-wide** — format only the paths you touched.

---

### Task 1: Bound the Gemini call server-side

**Files:**
- Modify: `supabase/functions/parse-sale/index.ts:30-31` (config constants)
- Modify: `supabase/functions/parse-sale/index.ts:33-55` (instruction prompt)
- Modify: `supabase/functions/parse-sale/index.ts:100-147` (`parseSale`)
- Modify: `supabase/functions/parse-sale/index.ts:213-231` (handler timing)

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: nothing consumed by other tasks. The HTTP contract is unchanged, so Tasks 2-4 are unaffected by this one.

This task has no Deno test harness in the repo; its test cycle is a live probe against the deployed function, matching how `recognize-product` was verified.

- [ ] **Step 1: Add the timeout and token-ceiling constants**

Below the existing `MODEL` constant at `index.ts:31`, add:

```ts
// Hard ceiling on generated output. A model confused by shop noise tries to
// transcribe the whole room; without a cap it can generate until the model
// default, which is what produced the 30s client timeouts. A realistic 5-item
// sale is ~300 output tokens, so 1024 leaves headroom. NOTE: on Gemini 3.x
// thinking tokens count against this budget -- thinkingLevel "minimal" (set
// below) keeps that draw small. Hitting the cap truncates the JSON, which
// fails JSON.parse and surfaces as a fast 502 rather than a 30s hang.
const MAX_OUTPUT_TOKENS = Number(Deno.env.get("GEMINI_VOICE_MAX_TOKENS") ?? "1024");

// Server-side deadline for the Gemini call. Must stay BELOW the app's 30s
// client timeout so the user gets a real error state instead of the client
// giving up on a request the server is still waiting on.
const GEMINI_TIMEOUT_MS = Number(Deno.env.get("GEMINI_VOICE_TIMEOUT_MS") ?? "20000");
```

> **Revised post-launch (final whole-branch review):** 20000 didn't compose —
> it left only ~10s of the client's 30s budget for upload + Edge Function cold
> start, which a weak connection on the fallback capture rung could exceed.
> The shipped default is **15000**, with any `GEMINI_VOICE_TIMEOUT_MS`
> override clamped to a **25000** ceiling. See `index.ts` for the final code.

- [ ] **Step 2: Add the noise rule to the prompt**

In the `instruction` template (`index.ts:33-55`), insert this block immediately **before** the `Rank each item's matches by confidence (highest first).` line:

```
NOISE RULE — the recording may come from a busy shop or street:
- Transcribe ONLY the primary speaker (the person closest to the microphone).
- IGNORE background chatter, other people's voices, traffic, music, and ambient
  noise. Do NOT transcribe them and do NOT turn them into items.
- "heard_text" must contain ONLY the sale sentence — never a description of the
  noise, never bystander speech. If the primary speaker said nothing sale-like,
  return an empty items array and a SHORT heard_text.
```

- [ ] **Step 3: Apply the ceiling and the deadline to the fetch**

In `parseSale`, add `signal` to the `fetch` options and `maxOutputTokens` to `generationConfig`:

```ts
  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": GEMINI_API_KEY },
      // Aborts throw, hit the handler's catch, and become a 502 -- the same
      // path as any other Gemini failure. No new error branch needed.
      signal: AbortSignal.timeout(GEMINI_TIMEOUT_MS),
      body: JSON.stringify({
        contents: [
          { role: "user", parts: [{ text: instruction(candidates) }, userPart] },
        ],
        generationConfig: {
          responseMimeType: "application/json",
          responseSchema,
          temperature: 0,
          maxOutputTokens: MAX_OUTPUT_TOKENS,
          thinkingConfig: { thinkingLevel: "minimal" },
        },
      }),
    },
  );
```

- [ ] **Step 4: Add timing instrumentation to the handler**

In `Deno.serve`, replace the `try { ... } catch` block at `index.ts:213-231` with:

```ts
  const startedAt = Date.now();
  try {
    const input: ParseInput = hasAudio
      ? {
          audioBase64: audioBase64 as string,
          audioMime: typeof audioMime === "string" && audioMime.trim() ? audioMime : "audio/aac",
        }
      : { transcript: transcript as string };
    // Audio has no client-supplied transcript to fall back on; heard_text then
    // comes from Gemini (or "" for a silent clip).
    const fallback = hasAudio ? "" : (transcript as string);
    const geminiStartedAt = Date.now();
    const raw = await parseSale(input, candidates as Candidate[]);
    const geminiMs = Date.now() - geminiStartedAt;
    // console.error so it lands in Supabase function logs regardless of log
    // level. This is how we confirm which segment dominates on a real noisy
    // failure instead of inferring it.
    console.error(
      `parse-sale timing: mode=${hasAudio ? "audio" : "text"} ` +
        `b64len=${hasAudio ? (audioBase64 as string).length : 0} ` +
        `gemini=${geminiMs}ms total=${Date.now() - startedAt}ms`,
    );
    return json(normalize(raw, candidates as Candidate[], fallback), 200);
  } catch (e) {
    // Genuine failures (bad key, Gemini outage, non-JSON reply, safety block,
    // or our own 20s abort) return 5xx so the app shows its error/retry state.
    // A real empty result is still a 200 with items: [] from normalize().
    console.error(`parse-sale failed after ${Date.now() - startedAt}ms:`, e);
    return json({ error: "parse failed" }, 502);
  }
```

- [ ] **Step 5: Deploy**

```bash
supabase functions deploy parse-sale
```

- [ ] **Step 6: Probe the happy path**

Send a known-good short transcript through the text path (no audio needed to prove the bounds work):

```bash
curl -sS -X POST "$SUPABASE_URL/functions/v1/parse-sale" \
  -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"transcript":"2 pepsi 1 litre","candidates":[{"id":"11111111-1111-1111-1111-111111111111","name":"Pepsi 1L","brand":"Pepsi","variant":"1L"}]}'
```

Expected: HTTP 200 with `heard_text` and an `items` array containing one entry whose `matches[0].product_id` is the candidate id. Confirm in `supabase functions logs parse-sale` that a `parse-sale timing:` line appears with a `gemini=` value well under 20000ms.

- [ ] **Step 7: Probe the deadline path**

Temporarily force the abort to prove it returns fast rather than hanging:

```bash
supabase secrets set GEMINI_VOICE_TIMEOUT_MS=1
supabase functions deploy parse-sale
```

Re-run the Step 6 curl. Expected: HTTP **502** `{"error":"parse failed"}` returned in about a second, and a `parse-sale failed after Nms:` log line naming a `TimeoutError`. Then restore:

```bash
supabase secrets unset GEMINI_VOICE_TIMEOUT_MS
supabase functions deploy parse-sale
```

Re-run the Step 6 curl once more and confirm it is back to 200.

- [ ] **Step 8: Commit**

```bash
git add supabase/functions/parse-sale/index.ts
git commit -m "fix(voice): bound the Gemini call so noise can't cause a 30s hang

Adds maxOutputTokens, a 20s server-side AbortSignal, a prompt rule to
ignore background speech, and timing logs. Contract unchanged."
```

---

### Task 2: Speech capture profile behind a fallback ladder

**Files:**
- Modify: `lib/features/voice/data/audio_recorder.dart` (whole file)
- Test: `test/audio_recorder_fallback_test.dart` (create)

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces:
  - `abstract class RecorderEngine` with `Future<bool> hasPermission()`, `Future<void> start(record_pkg.RecordConfig config, {required String path})`, `Future<String?> stop()`, `Future<void> cancel()`, `Future<void> dispose()`.
  - `class PackageRecorderEngine implements RecorderEngine`.
  - `const record_pkg.RecordConfig speechRecordConfig` and `const record_pkg.RecordConfig fallbackRecordConfig`.
  - `RecordAudioRecorder({RecorderEngine? engine, Future<Directory> Function()? temporaryDirectory})`.
  - `AudioRecorderPort` and `audioRecorderProvider` keep their existing shapes — Tasks 3 and 4 are unaffected.

`RecordAudioRecorder` currently constructs `record_pkg.AudioRecorder()` inline, which makes the ladder untestable. This task introduces the smallest seam that fixes that: a `RecorderEngine` interface plus an injectable temp-directory function (`getTemporaryDirectory` needs a platform channel that unit tests do not have).

- [ ] **Step 1: Write the failing test**

Create `test/audio_recorder_fallback_test.dart`:

```dart
import 'dart:io';

import 'package:ai_shopkeeper/features/voice/data/audio_recorder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart' as record_pkg;

/// Fake engine that records every config `start()` was attempted with and can
/// be told to reject the first N attempts -- standing in for a device whose
/// hardware refuses the 16kHz/mono profile (`PCMReader` throws in that case).
class _FakeEngine implements RecorderEngine {
  _FakeEngine({this.failFirstN = 0});

  final int failFirstN;
  final attempted = <record_pkg.RecordConfig>[];
  bool cancelled = false;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> start(
    record_pkg.RecordConfig config, {
    required String path,
  }) async {
    attempted.add(config);
    if (attempted.length <= failFirstN) {
      throw Exception('Recording config is not supported by the hardware');
    }
  }

  @override
  Future<String?> stop() async => null;

  @override
  Future<void> cancel() async => cancelled = true;

  @override
  Future<void> dispose() async {}
}

RecordAudioRecorder _recorder(_FakeEngine engine) => RecordAudioRecorder(
  engine: engine,
  temporaryDirectory: () async => Directory.systemTemp,
);

void main() {
  group('RecordAudioRecorder capture profile', () {
    test('uses the speech profile when the hardware accepts it', () async {
      final engine = _FakeEngine();

      await _recorder(engine).start();

      expect(engine.attempted, hasLength(1));
      final config = engine.attempted.single;
      expect(config.sampleRate, 16000);
      expect(config.numChannels, 1);
      expect(config.bitRate, 32000);
      expect(engine.cancelled, isFalse);
    });

    test('falls back to the default rates when the speech profile throws',
        () async {
      final engine = _FakeEngine(failFirstN: 1);

      await _recorder(engine).start();

      expect(engine.attempted, hasLength(2));
      final fallback = engine.attempted.last;
      expect(fallback.sampleRate, 44100);
      expect(fallback.numChannels, 2);
      expect(fallback.bitRate, 128000);
      // The partial session must be released before the retry.
      expect(engine.cancelled, isTrue);
    });

    test('the fallback keeps the effect flags, which never throw', () async {
      final engine = _FakeEngine(failFirstN: 1);

      await _recorder(engine).start();

      for (final config in engine.attempted) {
        expect(config.noiseSuppress, isTrue);
        expect(config.autoGain, isTrue);
        // Off on purpose: it targets playback bleed and lowers input volume.
        expect(config.echoCancel, isFalse);
        expect(
          config.androidConfig.audioSource,
          record_pkg.AndroidAudioSource.voiceRecognition,
        );
      }
    });

    test('a device that rejects both profiles propagates the failure',
        () async {
      final engine = _FakeEngine(failFirstN: 2);

      await expectLater(_recorder(engine).start(), throwsException);
      expect(engine.attempted, hasLength(2));
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/audio_recorder_fallback_test.dart`
Expected: FAIL to compile — `RecorderEngine` is undefined and `RecordAudioRecorder` has no named constructor parameters.

- [ ] **Step 3: Add the engine seam and the two configs**

In `lib/features/voice/data/audio_recorder.dart`, add these above `RecordAudioRecorder`:

```dart
/// Seam over `package:record`'s concrete `AudioRecorder` so the start-config
/// fallback ladder in [RecordAudioRecorder.start] is unit-testable without a
/// real microphone or platform channel.
abstract class RecorderEngine {
  Future<bool> hasPermission();
  Future<void> start(record_pkg.RecordConfig config, {required String path});
  Future<String?> stop();
  Future<void> cancel();
  Future<void> dispose();
}

/// The real engine: a thin pass-through to `package:record`.
class PackageRecorderEngine implements RecorderEngine {
  final _engine = record_pkg.AudioRecorder();

  @override
  Future<bool> hasPermission() => _engine.hasPermission();

  @override
  Future<void> start(
    record_pkg.RecordConfig config, {
    required String path,
  }) => _engine.start(config, path: path);

  @override
  Future<String?> stop() => _engine.stop();

  @override
  Future<void> cancel() => _engine.cancel();

  @override
  Future<void> dispose() => _engine.dispose();
}

/// Speech-tuned capture. Mono / 16kHz / 32kbps costs ~4 KB per second of
/// speech instead of the package defaults' ~16 KB/s, cutting upload time (and
/// therefore total latency) roughly 4x before base64's further 33%.
///
/// `sampleRate`/`numChannels`/`bitRate` are NOT universally supported --
/// `PCMReader.calculateBufferSize` throws when `AudioRecord.getMinBufferSize`
/// rejects the combination -- which is exactly why [RecordAudioRecorder.start]
/// falls back to [fallbackRecordConfig] rather than letting a rejection kill
/// the feature on that device.
///
/// The effect flags below are safe everywhere: `AudioEffectsManager.apply()`
/// guards each with `isAvailable()` and silently skips what the hardware lacks.
/// On iOS they are no-ops for file recording -- iOS's win here is the smaller
/// payload, not the flags.
const speechRecordConfig = record_pkg.RecordConfig(
  encoder: record_pkg.AudioEncoder.aacLc,
  sampleRate: 16000,
  numChannels: 1,
  bitRate: 32000,
  noiseSuppress: true,
  autoGain: true,
  // Deliberately off: echo cancellation targets speaker playback bleeding into
  // the mic (not a shop-noise problem) and the package documents that it
  // lowers recording volume -- pure cost here.
  echoCancel: false,
  androidConfig: record_pkg.AndroidRecordConfig(
    // Routes to the ASR-tuned capture path Google's own speech recognition
    // uses. Falls back to the default source on devices that don't implement
    // it, so it is safe to request unconditionally.
    audioSource: record_pkg.AndroidAudioSource.voiceRecognition,
  ),
);

/// Second rung of the ladder: today's rates (the package defaults), keeping the
/// effect flags since those can never throw. Worst case on an exotic device is
/// therefore exactly the behavior that shipped before this change.
const fallbackRecordConfig = record_pkg.RecordConfig(
  encoder: record_pkg.AudioEncoder.aacLc,
  noiseSuppress: true,
  autoGain: true,
  echoCancel: false,
  androidConfig: record_pkg.AndroidRecordConfig(
    audioSource: record_pkg.AndroidAudioSource.voiceRecognition,
  ),
);
```

- [ ] **Step 4: Rewrite `RecordAudioRecorder` to use the seam and the ladder**

Replace the class body's constructor, fields, `hasPermission`, `start`, `stop`, `cancel`, and `dispose` with:

```dart
class RecordAudioRecorder implements AudioRecorderPort {
  RecordAudioRecorder({
    RecorderEngine? engine,
    Future<Directory> Function()? temporaryDirectory,
  }) : _engine = engine ?? PackageRecorderEngine(),
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  final RecorderEngine _engine;
  final Future<Directory> Function() _temporaryDirectory;
  String? _pendingPath;

  @override
  Future<bool> hasPermission() => _engine.hasPermission();

  /// Two-rung ladder: ask for the speech profile, and if this device's hardware
  /// rejects those rates, release the partial session and retry once with the
  /// defaults. Only a failure of BOTH rungs propagates (the controller then
  /// reports `noSpeech`), so the optimization can never be the reason voice
  /// stops working on some phone we couldn't test.
  @override
  Future<void> start() async {
    try {
      await _startWith(speechRecordConfig);
    } catch (_) {
      await _cancelQuietly();
      await _startWith(fallbackRecordConfig);
    }
  }

  Future<void> _startWith(record_pkg.RecordConfig config) async {
    final dir = await _temporaryDirectory();
    final path =
        '${dir.path}/voice-sale-${DateTime.now().microsecondsSinceEpoch}.m4a';
    _pendingPath = path;
    await _engine.start(config, path: path);
  }

  @override
  Future<({Uint8List bytes, String mime})?> stop() async {
    final stoppedPath = await _engine.stop();
    final path = stoppedPath ?? _pendingPath;
    _pendingPath = null;
    if (path == null) return null;

    final file = File(path);
    try {
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      return (bytes: bytes, mime: 'audio/aac');
    } finally {
      await _deleteQuietly(file);
    }
  }

  @override
  Future<void> cancel() async {
    await _engine.cancel();
    final path = _pendingPath;
    _pendingPath = null;
    if (path != null) {
      await _deleteQuietly(File(path));
    }
  }

  @override
  Future<void> dispose() => _engine.dispose();

  /// Teardown between ladder rungs: the first rung may have left a partial
  /// session or temp file behind, and neither may block the retry, so every
  /// failure here is swallowed.
  Future<void> _cancelQuietly() async {
    try {
      await cancel();
    } catch (_) {
      // Best-effort: a failed cleanup must not mask the retry's own outcome.
    }
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best-effort cleanup: a stray temp file is a disk-space nit, not a
      // functional failure worth surfacing to the caller.
    }
  }
}
```

Replace the class's existing doc comment (the block starting `/// Adapts \`package:record\` (v7.1.1)...`) with one that describes the ladder:

```dart
/// Adapts `package:record` (v7.1.1) to [AudioRecorderPort], recording with a
/// speech-tuned profile and falling back to the package defaults on hardware
/// that rejects it.
///
/// The installed major requires a file path up front --
/// `AudioRecorder.start(config, path: ...)` writes straight to disk and
/// `stop()` returns that path (not bytes), so this wrapper picks a fresh
/// path in the platform temp directory (via `path_provider`) on every
/// [start], reads the bytes back on [stop], and always deletes the temp
/// file afterwards -- on [stop] once the bytes are safely read, and on
/// [cancel] (the plugin itself removes the file on cancel, but the delete
/// here is a harmless no-op if so and a real cleanup if the file survived).
/// Recording uses the AAC-LC encoder in an `.m4a` container, which is both
/// the plugin's default and the broadest-supported combination across
/// Android/iOS/Windows/macOS.
///
/// [RecorderEngine] and the temp-directory function are injectable so the
/// fallback ladder can be unit-tested without a microphone or a platform
/// channel; production wiring uses the real defaults.
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/audio_recorder_fallback_test.dart`
Expected: PASS, 4 tests.

- [ ] **Step 6: Verify nothing else regressed**

Run: `flutter test && flutter analyze`
Expected: all tests pass, analyze reports no issues.

- [ ] **Step 7: Commit**

```bash
dart format lib/features/voice/data/audio_recorder.dart test/audio_recorder_fallback_test.dart
git add lib/features/voice/data/audio_recorder.dart test/audio_recorder_fallback_test.dart
git commit -m "perf(voice): speech-tuned capture profile behind a fallback ladder

Mono/16kHz/32kbps cuts the upload ~4x. Because those fields can throw on
unsupported hardware, start() retries once with the previous defaults, so
the optimization can never break recording on an untested device."
```

---

### Task 3: Cap recording duration at 15 seconds

**Files:**
- Modify: `lib/features/voice/presentation/voice_controller.dart`
- Test: `test/voice_controller_test.dart` (extend)

**Interfaces:**
- Consumes: `AudioRecorderPort` / `audioRecorderProvider` from Task 2 (both unchanged).
- Produces: `final Provider<Duration> maxRecordingDurationProvider` — overridden in tests to keep them fast. No other task depends on it.

Nothing currently caps clip length, and in noise shopkeepers repeat themselves, so a clip can grow without bound and take the upload plus the parse with it. The cap is injected as a provider (rather than a hardcoded constant) purely so tests can shorten it without a fake-clock dependency.

- [ ] **Step 1: Write the failing tests**

In `test/voice_controller_test.dart`, first extend the existing `_makeContainer` helper to accept an override:

```dart
ProviderContainer _makeContainer({
  required AudioRecorderPort recorder,
  required VoiceSaleRepository repo,
  List<Product> products = const [],
  Duration? maxRecordingDuration,
}) {
  final container = ProviderContainer(
    overrides: [
      audioRecorderProvider.overrideWithValue(recorder),
      voiceSaleRepositoryProvider.overrideWithValue(repo),
      productsStreamProvider.overrideWith((ref) => Stream.value(products)),
      if (maxRecordingDuration != null)
        maxRecordingDurationProvider.overrideWithValue(maxRecordingDuration),
    ],
  );
  addTearDown(container.dispose);
  return container;
}
```

Then add these two tests at the end of the `VoiceController` group:

```dart
    test('recording auto-stops and parses once the duration cap elapses',
        () async {
      final recorder = _FakeAudioRecorder();
      final parsed = VoiceParseResult(
        heardText: 'sold 2 pepsi',
        items: [
          VoiceItem(
            heard: 'pepsi',
            quantity: 2,
            quantityAssumed: false,
            matches: const [VoiceMatch(productId: 'p1', confidence: 0.93)],
          ),
        ],
      );
      final c = _makeContainer(
        recorder: recorder,
        repo: _FakeVoiceRepo(Result.success(parsed)),
        products: [_product('p1')],
        maxRecordingDuration: const Duration(milliseconds: 20),
      );

      await c.read(voiceControllerProvider.notifier).startListening();
      expect(c.read(voiceControllerProvider).phase, VoicePhase.listening);

      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(recorder.stopped, isTrue);
      expect(c.read(voiceControllerProvider).phase, VoicePhase.reviewing);
      expect(c.read(voiceControllerProvider).lines, hasLength(1));
    });

    test('reset() before the cap elapses stops the auto-stop from firing',
        () async {
      final recorder = _FakeAudioRecorder();
      final c = _makeContainer(
        recorder: recorder,
        repo: _FakeVoiceRepo(const Result.success(VoiceParseResult())),
        maxRecordingDuration: const Duration(milliseconds: 20),
      );
      final notifier = c.read(voiceControllerProvider.notifier);

      await notifier.startListening();
      notifier.reset();

      await Future<void>.delayed(const Duration(milliseconds: 120));

      // A stale timer firing into a fresh session would re-enter stopAndParse.
      expect(recorder.stopped, isFalse);
      expect(c.read(voiceControllerProvider).phase, VoicePhase.idle);
    });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/voice_controller_test.dart`
Expected: FAIL to compile — `maxRecordingDurationProvider` is undefined.

- [ ] **Step 3: Add the provider**

At the bottom of `lib/features/voice/presentation/voice_controller.dart`, beside `voiceControllerProvider`, add:

```dart
/// How long a single recording may run before it auto-stops and parses.
/// Unbounded clips are a real latency risk: in a noisy shop people repeat
/// themselves, and every extra second is more to upload and more for the model
/// to transcribe. A provider (not a bare constant) so tests can shorten it.
final maxRecordingDurationProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 15),
);
```

Add `import 'dart:async' show Timer, unawaited;` — replacing the existing `import 'dart:async' show unawaited;` at line 1.

- [ ] **Step 4: Arm the timer on a successful start**

In `VoiceController`, add the field beside `_session`:

```dart
  /// Auto-stop for the current recording. Always cancelled before any
  /// transition out of `listening`, so a timer from an abandoned session can
  /// never fire into a later one.
  Timer? _capTimer;
```

Cancel it when the notifier itself goes away by replacing `build()`:

```dart
  @override
  VoiceSaleState build() {
    ref.onDispose(() => _capTimer?.cancel());
    return const VoiceSaleState();
  }
```

Then replace the tail of `startListening` (from `state = state.copyWith(phase: VoicePhase.listening);` to the end of the method) with:

```dart
    state = state.copyWith(phase: VoicePhase.listening);
    try {
      await recorder.start();
    } catch (_) {
      // The `record` plugin throws readily (mic held by another app, encoder
      // failure); nothing was captured, so this is the same user-facing
      // outcome as "no speech" -- and it's truthful, since nothing was heard.
      unawaited(recorder.cancel());
      if (_session != session) return; // superseded while awaiting start()
      state = state.copyWith(phase: VoicePhase.error, errorMessage: 'noSpeech');
      return;
    }
    if (_session != session) return; // superseded while awaiting start()

    _capTimer?.cancel();
    _capTimer = Timer(ref.read(maxRecordingDurationProvider), () {
      // Both guards matter: the session may have moved on, and the user may
      // have already stopped manually.
      if (_session == session && state.phase == VoicePhase.listening) {
        unawaited(stopAndParse());
      }
    });
```

- [ ] **Step 5: Cancel the timer on every exit from listening**

In `stopAndParse`, immediately after the `if (state.phase != VoicePhase.listening) return;` guard, add:

```dart
    _capTimer?.cancel();
    _capTimer = null;
```

Add the identical two lines as the first statements of `reparseFromText` (before `final text = ...`) and of `reset()` (before `_session++;`).

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/voice_controller_test.dart`
Expected: PASS, all tests in the file including the two new ones.

- [ ] **Step 7: Verify nothing else regressed**

Run: `flutter test && flutter analyze`
Expected: all tests pass, analyze reports no issues.

- [ ] **Step 8: Commit**

```bash
dart format lib/features/voice/presentation/voice_controller.dart test/voice_controller_test.dart
git add lib/features/voice/presentation/voice_controller.dart test/voice_controller_test.dart
git commit -m "fix(voice): auto-stop recording after 15s

Nothing capped clip length, so a noisy retry could grow unbounded and take
the upload and parse with it. The timer is cancelled on every exit from
listening so a stale session can never fire into a fresh one."
```

---

### Task 4: "Type it instead" escape hatch on the error pane

**Files:**
- Create: `lib/features/voice/presentation/voice_transcript_dialog.dart`
- Modify: `lib/features/voice/presentation/voice_review_sheet.dart:57-96` (remove `_editTranscript`), `:130` (call site)
- Modify: `lib/features/voice/presentation/voice_sale_sheet.dart:43-53`, `:242-285`
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_bn.arb`
- Test: `test/widgets/voice_error_type_instead_test.dart` (create)

**Interfaces:**
- Consumes: `voiceControllerProvider`, `VoiceController.reparseFromText` (Task 3 left both unchanged).
- Produces: `Future<void> showVoiceTranscriptDialog(BuildContext context, WidgetRef ref, String current)` — used by both `VoiceReviewSheet` and `_ErrorPane`.

`_ErrorPane` today offers only "Try again", which re-runs the same slow failure in the same noisy room. The transcript editor already exists as a private method on `VoiceReviewSheet`; lifting it to a shared function makes it reachable from the error state too.

- [ ] **Step 1: Write the failing test**

Create `test/widgets/voice_error_type_instead_test.dart`:

```dart
import 'dart:typed_data';

import 'package:ai_shopkeeper/core/config/theme.dart';
import 'package:ai_shopkeeper/core/error/failure.dart';
import 'package:ai_shopkeeper/core/error/result.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/inventory/presentation/inventory_controller.dart';
import 'package:ai_shopkeeper/features/voice/data/audio_recorder.dart';
import 'package:ai_shopkeeper/features/voice/data/voice_sale_repository.dart';
import 'package:ai_shopkeeper/features/voice/domain/voice_parse_result.dart';
import 'package:ai_shopkeeper/features/voice/presentation/voice_controller.dart';
import 'package:ai_shopkeeper/features/voice/presentation/voice_sale_sheet.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:ai_shopkeeper/shared/providers/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

class _FakeRecorder implements AudioRecorderPort {
  @override
  Future<bool> hasPermission() async => true;
  @override
  Future<void> start() async {}
  @override
  Future<({Uint8List bytes, String mime})?> stop() async =>
      (bytes: Uint8List.fromList(const [1]), mime: 'audio/m4a');
  @override
  Future<void> cancel() async {}
  @override
  Future<void> dispose() async {}
}

/// Audio parse fails the way a noisy-room timeout does; the typed text path
/// then succeeds.
class _FakeRepo implements VoiceSaleRepository {
  _FakeRepo(this.text);
  final Result<VoiceParseResult> text;

  @override
  Future<Result<VoiceParseResult>> parse({
    required Uint8List audioBytes,
    required String audioMime,
    required List<Map<String, dynamic>> candidates,
  }) async => const Result<VoiceParseResult>.failure(
    DatabaseFailure('Could not understand that right now. Please try again.'),
  );

  @override
  Future<Result<VoiceParseResult>> parseTranscript({
    required String transcript,
    required List<Map<String, dynamic>> candidates,
  }) async => text;
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('the error pane can recover by typing the sale instead',
      (tester) async {
    final typed = VoiceParseResult(
      heardText: '2 pepsi',
      items: [
        VoiceItem(
          heard: 'pepsi',
          quantity: 2,
          quantityAssumed: false,
          matches: const [VoiceMatch(productId: 'p1', confidence: 0.95)],
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        audioRecorderProvider.overrideWithValue(_FakeRecorder()),
        voiceSaleRepositoryProvider.overrideWithValue(
          _FakeRepo(Result.success(typed)),
        ),
        productsStreamProvider.overrideWith(
          (ref) => Stream.value(
            const [Product(id: 'p1', shopId: 's', name: 'Pepsi 1L', quantity: 9)],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final n = container.read(voiceControllerProvider.notifier);
    await n.startListening();
    await n.stopAndParse();
    expect(container.read(voiceControllerProvider).phase, VoicePhase.error);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('en'),
          supportedLocales: supportedAppLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const Scaffold(body: VoiceSaleSheet()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Type it instead'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, '2 pepsi');
    await tester.tap(find.text('Re-check'));
    await tester.pumpAndSettle();

    final state = container.read(voiceControllerProvider);
    expect(state.phase, VoicePhase.reviewing);
    expect(state.lines, hasLength(1));
    expect(state.lines.single.quantity, 2);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/widgets/voice_error_type_instead_test.dart`
Expected: FAIL — no widget found with text "Type it instead".

- [ ] **Step 3: Add the l10n strings**

In `lib/l10n/app_en.arb`, add after the `"voice_retry"` entry (add a comma to the `voice_retry` line):

```json
  "voice_typeInstead": "Type it instead"
```

In `lib/l10n/app_bn.arb`, add the matching key in the same position:

```json
  "voice_typeInstead": "লিখে দিন"
```

Regenerate: `flutter gen-l10n`

- [ ] **Step 4: Create the shared dialog**

Create `lib/features/voice/presentation/voice_transcript_dialog.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n_ext.dart';
import 'voice_controller.dart';

/// Opens a small editor prefilled with [current] transcript. On submit,
/// re-runs the AI on the corrected text via the controller. Empty submits are
/// ignored by the controller.
///
/// Shared by two callers: the review sheet (fix a mishear) and the error pane
/// (a noisy room defeated the mic entirely -- type the sale instead of
/// retrying into the same noise). From the error pane [current] is usually
/// empty, since nothing was heard.
Future<void> showVoiceTranscriptDialog(
  BuildContext context,
  WidgetRef ref,
  String current,
) async {
  final controller = TextEditingController(text: current);
  try {
    final edited = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.voice_heard),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onSubmitted: (v) => Navigator.of(dialogContext).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(dialogContext.l10n.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(dialogContext.l10n.voice_recheck),
          ),
        ],
      ),
    );
    if (edited != null) {
      await ref.read(voiceControllerProvider.notifier).reparseFromText(edited);
    }
  } finally {
    // Deferred a frame: the AlertDialog's exit-transition route is still
    // mounted (mid pop-animation) the instant `showDialog` resolves, so
    // disposing synchronously here can race the TextField's own teardown.
    // A post-frame callback runs after that route has actually been
    // removed from the tree.
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
  }
}
```

- [ ] **Step 5: Point the review sheet at the shared function**

In `lib/features/voice/presentation/voice_review_sheet.dart`, delete the entire `_editTranscript` method (lines 57-96, including its doc comment), add `import 'voice_transcript_dialog.dart';` beside the existing `import 'voice_controller.dart';`, and change the call site at line 130 to:

```dart
            onTap: () =>
                showVoiceTranscriptDialog(context, ref, state.heardText ?? ''),
```

- [ ] **Step 6: Add the action to the error pane**

In `lib/features/voice/presentation/voice_sale_sheet.dart`, add `import 'voice_transcript_dialog.dart';` beside the existing `import 'voice_review_sheet.dart';`.

Change the `VoicePhase.error` arm of the switch in `VoiceSaleSheet.build` to:

```dart
      VoicePhase.error => _ErrorPane(
        errorKey: state.errorMessage,
        onRetry: notifier.reset,
        // Retrying into the same noise repeats the same failure, so offer the
        // text path as a real way out. `context`/`ref` are available here, so
        // `_ErrorPane` stays a plain StatelessWidget.
        onTypeInstead: () =>
            showVoiceTranscriptDialog(context, ref, state.heardText ?? ''),
      ),
```

In `_ErrorPane`, add the field and constructor parameter:

```dart
class _ErrorPane extends StatelessWidget {
  const _ErrorPane({
    required this.errorKey,
    required this.onRetry,
    required this.onTypeInstead,
  });

  final String? errorKey;
  final VoidCallback onRetry;
  final VoidCallback onTypeInstead;
```

and replace the retry button in its `build` with both actions:

```dart
          FilledButton.tonal(onPressed: onRetry, child: Text(l10n.voice_retry)),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onTypeInstead,
            child: Text(l10n.voice_typeInstead),
          ),
```

- [ ] **Step 7: Run the test to verify it passes**

Run: `flutter test test/widgets/voice_error_type_instead_test.dart`
Expected: PASS.

- [ ] **Step 8: Verify nothing else regressed**

Run: `flutter test && flutter analyze`
Expected: all tests pass — in particular `test/widgets/voice_edit_transcript_test.dart`, which exercises the same dialog through the review sheet after the extraction — and analyze reports no issues.

- [ ] **Step 9: Commit**

```bash
dart format lib/features/voice/presentation/ lib/l10n/ test/widgets/voice_error_type_instead_test.dart
git add lib/features/voice/presentation/ lib/l10n/ test/widgets/voice_error_type_instead_test.dart
git commit -m "feat(voice): let the error pane fall back to typing the sale

'Try again' just repeats the same failure in the same noisy room. Lifts the
transcript editor out of the review sheet so the error state can reach it
and recover through the existing text-parse path."
```

---

## Final verification (after all four tasks)

- [ ] **Run the full suite**

Run: `flutter test && flutter analyze`
Expected: all tests pass, no analyzer issues.

- [ ] **On-device check (physical S22)**

```bash
flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```

Confirm, in this order:
1. **Quiet room, short sale** — voice still parses correctly and no faster-than-before regression in accuracy. The lower bitrate must not have cost recognition quality.
2. **Noisy setting, short sale** — returns within a usable time instead of hanging to 30s.
3. **Say nothing for 15s** — recording auto-stops on its own and moves to parsing.
4. **Force a failure** (airplane mode mid-parse) — the error pane shows both "Try again" and "Type it instead", and typing a sale recovers into the review sheet.
5. Check `supabase functions logs parse-sale` and confirm the `parse-sale timing:` lines show a smaller `b64len` than before Task 2 and a `gemini=` value inside the 20s budget.
