# Scan → Gemini 3.6 Flash Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the `recognize-product` Edge Function to identify product photos by calling Google's official Gemini API (`gemini-3.6-flash`) directly with structured-output JSON, removing the Frog/OpenAI gateway — with the app-facing request/response contract frozen.

**Architecture:** Single-file engine swap. The function keeps its name, input (`image_base64` + `candidates`), and output (`status`/`read_*`/`matches`) exactly. Internally, the one outbound call changes from Frog `chat/completions` (OpenAI vision format) to Gemini `generateContent` (image as `inline_data`, reply forced into a `responseSchema`). The `normalize()` trust boundary and HTTP status conventions are unchanged.

**Tech Stack:** Deno / TypeScript Supabase Edge Function; Google Gemini API (`generativelanguage.googleapis.com/v1beta`); deployed via Supabase Dashboard.

**Testing note:** There is no local Deno/Supabase-CLI toolchain on this machine, so the function cannot be unit-tested locally. Verification is by **direct HTTP probe against the deployed function** (happy path, no-match, forced-failure), matching how `parse-sale` was validated. Deploy is a manual Dashboard step performed by the user.

---

## File Structure

- **Modify (full rewrite):** `supabase/functions/recognize-product/index.ts` — the only code file. Frog config/call removed; Gemini config/call + `responseSchema` added; `extractJson()` deleted; `normalize()`, `json()`, and the `Deno.serve` handler kept (handler gains a missing-key 400 guard).
- **Modify:** `supabase/functions/recognize-product/README.md` — document the Gemini-direct flow, secrets, and probe tests (if a README exists; create if not).

No other files change. The Flutter app and `parse-sale` are untouched.

---

## Task 1: Rewrite `recognize-product/index.ts` to call Gemini directly

**Files:**
- Modify (full rewrite): `supabase/functions/recognize-product/index.ts`

- [ ] **Step 1: Replace the entire file with the Gemini implementation**

Overwrite `supabase/functions/recognize-product/index.ts` with exactly this content:

```typescript
// Supabase Edge Function: recognize-product
// Identifies a retail product from a photo by calling Google's official Gemini
// API directly (gemini-3.6-flash) and returns a normalized JSON match result.
//
// History: this function previously routed the image through the Frog gateway
// (OpenAI-compatible, serving GPT/Gemini). It now calls Gemini's generateContent
// endpoint directly — the image goes in as inline_data, and Gemini structured
// output (responseSchema) forces the reply into the exact JSON shape below, so
// there is no brace-scraping. Only GEMINI_API_KEY is required (shared with the
// voice function). MEMBER B owns prompt tuning.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

interface Candidate { id: string; name: string; brand?: string; variant?: string }

// Google Gemini config. Only GEMINI_API_KEY must be set. Model is pinned to
// gemini-3.6-flash but overridable via a secret so a future slug rename never
// needs a code change.
const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY") ?? "";
const MODEL = Deno.env.get("GEMINI_VISION_MODEL") ?? "gemini-3.6-flash";
// The app sends JPEG bytes today; the previous code hard-coded the same mime.
const IMAGE_MIME = "image/jpeg";

const instruction = (candidates: Candidate[]) =>
  `You are identifying a retail product from a photo for a shop's point-of-sale.
Below is the shop's product list (JSON). Decide which listed product(s) appear in the image.
Match the brand/name/size you can read on the packaging to the candidates.
Rank matches by confidence (highest first). If nothing matches, use status "none" and an empty matches array. Never invent an id that is not in the list.
Set read_brand/read_name/read_size to what you can read off the packaging, or null if unreadable.
Product list: ${JSON.stringify(candidates)}`;

// Gemini structured-output schema — forces the reply into the exact response
// contract shape instead of coaxing it via prompt text. (OpenAPI 3.0 subset that
// Gemini accepts: object/array/string/number, enum, nullable, required.)
const responseSchema = {
  type: "object",
  properties: {
    status: { type: "string", enum: ["match", "multiple", "none"] },
    read_brand: { type: "string", nullable: true },
    read_name: { type: "string", nullable: true },
    read_size: { type: "string", nullable: true },
    matches: {
      type: "array",
      items: {
        type: "object",
        properties: {
          product_id: { type: "string" },
          confidence: { type: "number" },
        },
        required: ["product_id", "confidence"],
      },
    },
  },
  required: ["status", "matches"],
};

// One call to Gemini generateContent: image in as inline_data, structured JSON
// out. Same res.ok guard-and-throw discipline as the voice function — a non-2xx
// (bad key -> 400, quota -> 429, outage -> 5xx) must surface as a 502, never a
// misleading empty status:"none".
async function recognize(imageB64: string, candidates: Candidate[]) {
  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": GEMINI_API_KEY },
      body: JSON.stringify({
        contents: [
          {
            role: "user",
            parts: [
              { text: instruction(candidates) },
              { inline_data: { mime_type: IMAGE_MIME, data: imageB64 } },
            ],
          },
        ],
        generationConfig: {
          responseMimeType: "application/json",
          responseSchema,
          temperature: 0,
        },
      }),
    },
  );
  if (!res.ok) {
    const detail = await res.text().catch(() => "");
    throw new Error(`gemini ${res.status}: ${detail.slice(0, 300)}`);
  }
  const body = await res.json();
  // A missing/empty candidates array or a non-array parts list is NOT a real
  // "no match" — it means a safety block, quota oddity, or API shape change and
  // must surface as a 502 (retry), never a silent status:"none".
  const parts = body?.candidates?.[0]?.content?.parts;
  if (!Array.isArray(body?.candidates) || body.candidates.length === 0 ||
      !Array.isArray(parts) || parts.length === 0) {
    throw new Error(`gemini: unexpected response shape: ${JSON.stringify(body).slice(0, 300)}`);
  }
  // Join every non-`thought` part's text (a thinking model may emit a thought
  // segment before the answer), then parse. Structured output should already be
  // clean JSON, but parse defensively — a safety truncation can still break it,
  // and a parse failure throws -> 502.
  const text = parts
    .filter((p: Record<string, unknown>) => !p?.thought)
    .map((p: Record<string, unknown>) => (typeof p?.text === "string" ? p.text : ""))
    .join("");
  return JSON.parse(text) as Record<string, unknown>;
}

function normalize(raw: Record<string, unknown>, candidates: Candidate[]) {
  const ids = new Set(candidates.map((c) => c.id));
  const matches = Array.isArray(raw.matches) ? raw.matches : [];
  const clean = matches
    .filter((m: Record<string, unknown>) => ids.has(m?.product_id as string))
    .map((m: Record<string, unknown>) => ({
      product_id: m.product_id,
      confidence: Math.max(0, Math.min(1, Number(m.confidence) || 0)),
    }));
  const status = clean.length === 0 ? "none" : (raw.status as string) ?? "match";
  return {
    status,
    read_brand: raw.read_brand ?? null,
    read_name: raw.read_name ?? null,
    read_size: raw.read_size ?? null,
    matches: clean,
  };
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  let imageB64: unknown;
  let candidates: unknown;
  try {
    const body = await req.json();
    imageB64 = body.image_base64;
    candidates = body.candidates;
  } catch (_e) {
    return json({ error: "invalid JSON body" }, 400);
  }
  if (!imageB64 || !Array.isArray(candidates)) {
    return json({ error: "image_base64 and candidates are required" }, 400);
  }
  // Fast-fail with a clear message rather than letting an unset key surface as a
  // downstream Gemini 401/403 (which would read as a generic 502).
  if (!GEMINI_API_KEY) {
    return json({ error: "GEMINI_API_KEY is not configured" }, 400);
  }
  try {
    const raw = await recognize(imageB64 as string, candidates as Candidate[]);
    return json(normalize(raw, candidates as Candidate[]), 200);
  } catch (e) {
    // Genuine failures (bad key, Gemini outage, non-JSON reply, safety block)
    // return 5xx so the app shows its error/retry state instead of a misleading
    // "no match". A real "nothing matched" is still a 200 with status:"none".
    console.error("recognize-product failed:", e);
    return json({ error: "recognition failed" }, 502);
  }
});
```

- [ ] **Step 2: Self-check the rewrite against the contract**

Read the new file top to bottom and confirm ALL of the following (there is no local Deno compiler here, so this read-through is the check):
- Request fields read are still `image_base64` and `candidates` (unchanged).
- `normalize()` return object still has keys `status`, `read_brand`, `read_name`, `read_size`, `matches` (unchanged).
- No remaining reference to `FROG`, `BASE_URL`, `API_KEY`, `PROVIDER`, `OPENAI_MODEL`, `VISION_PROVIDER`, `extractJson`, or `chat/completions`.
- The only outbound URL is `generativelanguage.googleapis.com/.../${MODEL}:generateContent`.
- Auth header is `x-goog-api-key`, not `Authorization: Bearer`.

Run this grep to prove the Frog bits are gone (expect **no output**):

```bash
grep -nEi "frog|chat/completions|extractJson|VISION_PROVIDER|Bearer" supabase/functions/recognize-product/index.ts
```
Expected: no matching lines.

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/recognize-product/index.ts
git commit -m "feat(scan): call Gemini 3.6 Flash directly with structured output; drop Frog"
```

---

## Task 2: Deploy the function and configure secrets (manual — user)

**Files:** none (Supabase Dashboard actions).

This task is performed by the user in the Supabase Dashboard because there is no CLI on this machine. The implementer hands the user these exact instructions and waits.

- [ ] **Step 1: Confirm the required secret exists**

In Supabase Dashboard → Project → Edge Functions → **Secrets**, confirm `GEMINI_API_KEY` is set to the official Google AI Studio key. (It was already set for the voice function; scan reuses it.)

- [ ] **Step 2 (optional): Confirm/override the model**

No action needed to use `gemini-3.6-flash` (the pinned default). Only if you want a different model, add a secret `GEMINI_VISION_MODEL` set to the exact slug (e.g. `gemini-flash-latest`).

- [ ] **Step 3: Deploy the function**

Deploy the updated `recognize-product` function via the Dashboard (Edge Functions → recognize-product → Deploy) or paste the new `index.ts` into the Dashboard editor and deploy. Confirm the deploy timestamp updates.

---

## Task 3: Probe the deployed function (verification)

**Files:**
- Create (scratch, not committed): a request-body JSON in the scratchpad dir.

Uses PowerShell (`Invoke-RestMethod`) against the deployed function. `$SUPABASE_URL` = `https://mlyjygkivdezzjbvzpfy.supabase.co`; the anon key is in `dart_defines.json` (`SUPABASE_ANON_KEY`).

- [ ] **Step 1: Build a happy-path probe body from a real product photo**

Ask the user for a path to a JPEG photo of a product that exists in a test shop, plus that shop's candidate list (id/name/brand/variant). Base64-encode the image and write the request body to the scratchpad (avoids shell-escaping a huge string). Example PowerShell:

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
```

- [ ] **Step 2: Send the happy-path probe**

```powershell
$anon = (Get-Content .\dart_defines.json | ConvertFrom-Json).SUPABASE_ANON_KEY
Invoke-RestMethod -Method Post `
  -Uri "https://mlyjygkivdezzjbvzpfy.supabase.co/functions/v1/recognize-product" `
  -Headers @{ Authorization = "Bearer $anon"; "Content-Type" = "application/json" } `
  -InFile "$env:TEMP\scan-probe.json"
```
Expected: HTTP 200 and a JSON object with keys `status`, `read_brand`, `read_name`, `read_size`, `matches`. For a clear photo of a listed product, `status` is `match` (or `multiple` if size is ambiguous) and `matches` contains that product's id with a plausible `confidence`. **Confirm the shape matches the frozen contract exactly** — this is the gate.

- [ ] **Step 3: No-match probe**

Rebuild the body with a photo of something NOT in the candidate list (or candidates that don't match the photo) and resend as in Step 2.
Expected: HTTP 200, `status: "none"`, `matches: []`.

- [ ] **Step 4: Forced-failure probe (proves failures are 502, not fake "none")**

Temporarily set the `GEMINI_VISION_MODEL` secret to a bogus slug (e.g. `gemini-does-not-exist`) in the Dashboard, redeploy is NOT needed for a secret change, then resend the Step 2 probe.
Expected: HTTP 502 with `{ "error": "recognition failed" }` (the bad model → Gemini 404 → thrown → 502). **Then set `GEMINI_VISION_MODEL` back** (delete it to return to the `gemini-3.6-flash` default, or set it to `gemini-3.6-flash`).

- [ ] **Step 5: On-device check**

Rebuild/run the app on the S22 and scan a real product. Confirm the scan confirmation UI receives the same shape and behaves exactly as before the migration (no app code changed, so this is a regression check).

---

## Task 4: Update the function README

**Files:**
- Modify/Create: `supabase/functions/recognize-product/README.md`

- [ ] **Step 1: Write the README to describe the Gemini-direct flow**

Replace (or create) `supabase/functions/recognize-product/README.md` with content covering:
- Purpose: photo + candidates → normalized match JSON.
- Flow: calls Google Gemini `generateContent` directly with the image as `inline_data`; structured output (`responseSchema`) guarantees the JSON shape.
- Secrets: `GEMINI_API_KEY` (required, shared with voice); `GEMINI_VISION_MODEL` (optional override, defaults to `gemini-3.6-flash`).
- Contract: the request (`image_base64`, `candidates`) and response (`status`, `read_brand`, `read_name`, `read_size`, `matches[]`) blocks.
- Status conventions: 400 bad input / missing key; 200 real result incl. `status:"none"`; 502 genuine failures and unexpected Gemini response shape.
- A probe example (the PowerShell from Task 3).
- A one-line note that Frog is no longer used by this function.

- [ ] **Step 2: Commit**

```bash
git add supabase/functions/recognize-product/README.md
git commit -m "docs(scan): document Gemini-direct recognize-product flow"
```

---

## Self-Review

**Spec coverage:**
- §1 goal (Gemini direct, drop Frog) → Task 1. ✅
- §2 frozen contract → Task 1 Step 2 self-check + Task 3 Step 2 shape gate. ✅
- §3 engine swap table (URL/auth/inline_data/model/structured output) → Task 1 Step 1 code. ✅
- §4 structured output + schema → Task 1 `responseSchema` + `generationConfig`. ✅
- §5 `normalize()` unchanged → Task 1 (carried verbatim). ✅
- §6 error handling parity + shape guard + non-thought join → Task 1 `recognize()` guards + serve catch; verified by Task 3 Steps 3–4. ✅
- §7 secrets (`GEMINI_API_KEY`, optional `GEMINI_VISION_MODEL`), Frog left in place → Task 2; no Frog refs verified in Task 1 Step 2 grep. ✅
- §8 testing (direct probe, no-match, failure, on-device) → Task 3. ✅ (Missing-key 400 guard from §8 included in Task 1 serve handler.)
- §9 out of scope (no app/voice/schema changes) → respected; only `recognize-product` files touched. ✅
- §10 rollback (single file) → true; revert Task 1 commit. ✅

**Placeholder scan:** No TBD/TODO. All code steps show full code. Task 4 Step 1 describes README content as a bcontent checklist (prose doc, not code) — acceptable.

**Type consistency:** `recognize()` returns `Record<string, unknown>`, consumed by `normalize(raw, candidates)` — matches original signature. `Candidate` interface unchanged. `responseSchema` property names (`status`, `read_brand`, `read_name`, `read_size`, `matches`/`product_id`/`confidence`) match `normalize()` output and the frozen contract. No naming drift.
