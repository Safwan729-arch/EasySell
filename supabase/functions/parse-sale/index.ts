// Supabase Edge Function: parse-sale
// Voice sale parser. Accepts either raw AUDIO (audio_base64 + audio_mime — what
// the app sends) or a TRANSCRIPT (a curl-testable text path kept for debugging).
// A SINGLE Google Gemini generateContent call both transcribes the audio AND
// turns it into structured sale line items matched against the shop's product
// candidates, returned as normalized JSON with a guaranteed shape (structured
// output / responseSchema).
//
// History: this function used to make two hops — Gemini transcribed the audio,
// then the Frog gateway (OpenAI-compatible GPT) parsed the text into items. It
// now does both in one Gemini call; Frog is no longer used by voice. Only
// GEMINI_API_KEY is required (shared with the scan function). MEMBER B owns
// prompt tuning.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { resolveItemQuantity } from "./quantity_words.ts";

interface Candidate {
  id?: string;
  /** List-index form (Task 8): a small integer instead of a 36-char uuid,
   *  cutting per-candidate tokens the same way the scan flow's does. Either
   *  `id` or `i` is present, never neither. */
  i?: number;
  name: string;
  brand?: string;
  variant?: string;
  /** How the shop sells it: "pcs" | "kg" | "g" | "litre" | "ml". Decides
   *  whether a spoken amount is a product size or the quantity itself. */
  unit?: string;
  /** Units sold in the last 30 days, when the app had the figure to hand. */
  recent?: number;
}

// Google Gemini config. Only GEMINI_API_KEY must be set. Voice is pinned to
// gemini-3.5-flash-lite -- the lowest-latency model in the family, chosen for
// this simple "hear a short sale sentence -> pick products" job so voice feels
// fast. Overridable via a secret (set GEMINI_VOICE_MODEL=gemini-3.6-flash if a
// heavier model is ever needed for tricky Bengali/mixed speech) so a slug swap
// never needs a code change. Scan stays on full Flash separately.
const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY") ?? "";
const MODEL = Deno.env.get("GEMINI_VOICE_MODEL") ?? "gemini-3.5-flash-lite";

// Hard ceiling on generated output. A model confused by shop noise tries to
// transcribe the whole room; without a cap it can generate until the model
// default, which is what produced the 30s client timeouts. A realistic 5-item
// sale is ~300 output tokens, so 1024 leaves headroom. NOTE: on Gemini 3.x
// thinking tokens count against this budget -- thinkingLevel "minimal" (set
// below) keeps that draw small. Hitting the cap truncates the JSON, which
// fails JSON.parse and surfaces as a fast 502 rather than a 30s hang.
const MAX_OUTPUT_TOKENS = (() => {
  const parsed = Number(Deno.env.get("GEMINI_VOICE_MAX_TOKENS") ?? "1024");
  // Guard against invalid env values (NaN, negative, zero). A malformed secret
  // must not silently become a 0-token budget (null in JSON) or break voice
  // while looking like a Gemini problem. Always fall back to the default.
  return Number.isFinite(parsed) && parsed > 0 ? parsed : 1024;
})();

// Server-side deadline for the Gemini call. Must leave enough of the app's 30s
// client timeout for upload (base64 audio) and Edge Function cold start on top
// of the Gemini call itself -- not merely "be below 30s". A 20s abort left
// only ~10s for everything else; on a weak connection the ~320KB base64
// payload from the fallback capture rung alone can exceed that, so the client
// gave up at 30s before the fast 502 this feature exists to produce ever
// arrived. 15s composes; the 25000 clamp on any override exists so a
// misconfigured secret can't silently reintroduce that failure mode.
const GEMINI_TIMEOUT_MS = (() => {
  const parsed = Number(Deno.env.get("GEMINI_VOICE_TIMEOUT_MS") ?? "15000");
  // Guard against invalid env values (NaN, negative, zero, or too large). A
  // malformed secret must not silently become a 0ms timeout that kills every
  // call instantly (looks like a Gemini outage) or a value large enough to
  // blow the composed 30s client-timeout budget again. Always fall back to
  // the default, and always clamp an override to the 25000 ceiling.
  if (!Number.isFinite(parsed) || parsed <= 0) return 15000;
  return Math.min(parsed, 25000);
})();

const instruction = (candidates: Candidate[]) =>
  `You are a point-of-sale assistant. You receive a shopkeeper's spoken sentence,
either as audio or as already-transcribed text. The speech may be English,
Bengali, or a mix. Do TWO things:
1. Transcribe EXACTLY what was said into "heard_text" (verbatim, no commentary).
2. Turn it into sale line items matched against the shop's product list below.

LANGUAGE — the shopkeeper may speak Bengali, English, or romanized Bengali
("Banglish": Bengali words typed in English letters, e.g. "arai kg khola chal").
Treat romanized Bengali as Bengali: resolve its words to meaning, do not read
them as English. Transcribe "heard_text" as spoken, but MATCH on meaning.

CRITICAL RULE — quantity and size are DIFFERENT fields, never merge them:
- Count words (piece, pcs, packet, ta, টা, টি, পিস) give "quantity".
- For a PACKAGED product (candidate "unit" is "pcs"), a size word
  (500ml, 1 litre, লিটার) identifies WHICH product. It is part of "heard" and
  must NEVER become the quantity.
  "pepsi 1 litre" => quantity 1, heard "pepsi 1 litre"  (matches the 1L product)
  "2 pepsi"       => quantity 2, heard "pepsi"
- For a LOOSE product sold by weight or volume (candidate "unit" is "kg", "g",
  "litre" or "ml"), the spoken amount in that unit IS the quantity, because the
  shop sells it by that unit. Put the NUMBER in "quantity".
  "আড়াই কেজি খোলা চাল" => quantity 2.5   (a kg product; 2.5 kg sold)
  "500 gram chini"      => quantity 500   (a g product)
  Include the amount in "heard" as well, verbatim.

BENGALI FRACTION RULE — Bengali says half-quantities as single irregular words.
These are NOT approximations; each has an exact value. Both scripts count:
  আধা / আধ / adha / adh / half      = 0.5
  দেড় / der / derh / dedh           = 1.5
  আড়াই / arai / aarai / adai / arhai = 2.5
And three modifiers that apply to the number AFTER them:
  সোয়া / shoya / soya  N  = N + 0.25   ("সোয়া দুই" = 2.25)
  সাড়ে / sare / share  N  = N + 0.5    ("সাড়ে তিন" = 3.5)
  পৌনে / poune / pone  N  = N - 0.25   ("পৌনে চার" = 3.75)
Never round these to a whole number. "arai kg rice" is quantity 2.5, NOT 2.
Bengali cardinals: এক/ek 1, দুই/dui 2, তিন/tin 3, চার/char 4, পাঁচ/pach 5,
ছয়/choy 6, সাত/sat 7, আট/at 8, নয়/noy 9, দশ/dosh 10.

CROSS-SCRIPT MATCHING — a shop's product names may be in English or Bengali,
and the shopkeeper may speak the other one. Match on MEANING, across scripts and
transliteration; never require the spoken words to look like the stored name.
  spoken "খোলা চাল" or "khola chal" => product named "Loose rice"  ✓
  spoken "loose rice"               => product named "খোলা চাল"    ✓
  spoken "chini" or "চিনি"          => product named "Sugar"       ✓
"খোলা" / "khola" / "খুচরা" mean loose/unpackaged, matching a by-weight product.

Match each spoken item against the shop's product list below. If the text does
NOT distinguish between two candidates (e.g. "pepsi" when both 500ml and 1L
exist), return BOTH with SIMILAR confidence — do NOT guess a winner; the app asks
the user. Never invent a product_id that is not in the list. If no count was
spoken for an item, OMIT "quantity" entirely (do not guess a number). If nothing
sale-like was said, return an empty items array.

NOISE RULE — the recording may come from a busy shop or street:
- Transcribe ONLY the primary speaker (the person closest to the microphone).
- IGNORE background chatter, other people's voices, traffic, music, and ambient
  noise. Do NOT transcribe them and do NOT turn them into items.
- "heard_text" must contain ONLY the sale sentence — never a description of the
  noise, never bystander speech. If the primary speaker said nothing sale-like,
  return an empty items array and a SHORT heard_text.

SALES-HISTORY RULE — a candidate may carry "recent" (units this shop sold in the
last 30 days). Absent means no recent sales. Use it ONLY to break a tie the words
themselves left open, never to override what was actually said:
- If two candidates are otherwise equally plausible and one's "recent" is at least
  5x the other's, give it a decisive lead (e.g. 0.88 vs 0.45) — the shopkeeper
  almost certainly meant the one they sell constantly.
- If the gap is smaller, give only a slight lean (e.g. 0.62 vs 0.55) so the app
  still asks.
- A spoken size, brand, or variant ALWAYS wins over "recent". Never prefer a
  high-selling 1L over a 500ml when "500ml" was said.

Rank each item's matches by confidence (highest first).
Product list: ${JSON.stringify(candidates)}`;

// Gemini structured-output schema — forces the reply into the exact response
// contract shape. "quantity" and "unit_heard" are intentionally NOT in an item's
// required list so Gemini can omit a count it never heard (the app then defaults
// it to 1 and flags it as assumed).
const responseSchema = {
  type: "object",
  properties: {
    heard_text: { type: "string" },
    items: {
      type: "array",
      items: {
        type: "object",
        properties: {
          heard: { type: "string" },
          quantity: { type: "number" },
          unit_heard: { type: "string", nullable: true },
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
        required: ["heard", "matches"],
      },
    },
  },
  required: ["heard_text", "items"],
};

type ParseInput =
  | { audioBase64: string; audioMime: string }
  | { transcript: string };

// One Gemini generateContent call: audio (or transcript text) + the product list
// in, structured {heard_text, items[...]} out. Same res.ok guard-and-throw
// discipline as the scan function — a non-2xx (bad key -> 400, quota -> 429,
// outage -> 5xx) must surface as a 502, never a misleading empty result.
async function parseSale(input: ParseInput, candidates: Candidate[]) {
  const userPart = "transcript" in input
    ? { text: input.transcript }
    : { inline_data: { mime_type: input.audioMime, data: input.audioBase64 } };
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
          // Minimize the model's internal "thinking" — transcription + extraction
          // is a simple, structured job. Gemini 3 flash can't turn thinking fully
          // off, so use the lowest level to cut latency. (thinkingBudget is the
          // retired 2.5 knob; 3.x uses thinkingLevel.)
          thinkingConfig: { thinkingLevel: "minimal" },
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
  // "nothing said" — it means a safety block, quota oddity, or API shape change
  // and must surface as a 502 (retry), never a silent empty result.
  const parts = body?.candidates?.[0]?.content?.parts;
  if (!Array.isArray(body?.candidates) || body.candidates.length === 0 ||
      !Array.isArray(parts) || parts.length === 0) {
    throw new Error(`gemini: unexpected response shape: ${JSON.stringify(body).slice(0, 300)}`);
  }
  // A thinking model may emit a thought segment before the answer; join every
  // non-`thought` part's text, then parse. Structured output should already be
  // clean JSON, but parse defensively — a parse failure throws -> 502.
  const text = parts
    .filter((p: Record<string, unknown>) => !p?.thought)
    .map((p: Record<string, unknown>) => (typeof p?.text === "string" ? p.text : ""))
    .join("");
  try {
    return JSON.parse(text) as Record<string, unknown>;
  } catch (e) {
    // A truncated reply (maxOutputTokens hit mid-JSON) throws the exact same
    // bare SyntaxError as a genuine Gemini outage. finishReason distinguishes
    // them in the logs: "MAX_TOKENS" means truncation, not a failure to reach
    // Gemini at all.
    const finishReason = body?.candidates?.[0]?.finishReason ?? "unknown";
    throw new Error(
      `gemini: JSON.parse failed (finishReason=${finishReason}): ${(e as Error).message}`,
    );
  }
}

// Never trust the model's output shape. Drop invented ids, clamp confidences,
// and pass quantity through only when it is a real positive number (the app
// defaults a missing quantity to 1 and flags it, rather than us inventing one).
function normalize(raw: Record<string, unknown>, candidates: Candidate[], transcript: string) {
  const ids = new Set(
    candidates.map((c) => c.id ?? String(c.i)).filter((k) => k !== "undefined"),
  );
  const rawItems = Array.isArray(raw.items) ? raw.items : [];
  // Fall back to the raw transcript so the review sheet can always show what was said.
  const heardText = (typeof raw.heard_text === "string" && raw.heard_text) || transcript;
  const soleItem = rawItems.length === 1;

  const items = rawItems.map((it: Record<string, unknown>) => {
    const matches = Array.isArray(it?.matches) ? it.matches : [];
    const heard = typeof it?.heard === "string" ? it.heard : "";
    const modelQuantity = typeof it?.quantity === "number" && it.quantity > 0
      ? it.quantity
      : null;
    // Bengali half-quantities ("আড়াই কেজি" = 2.5) are irregular single words
    // the model guesses at inconsistently -- it returned 2 for "arai kg" even
    // at temperature 0. This is a deterministic correction; it only ever fires
    // on an explicit fractional word and so cannot alter an ordinary count.
    const { quantity, corrected } = resolveItemQuantity({
      heard,
      transcript: heardText,
      modelQuantity,
      soleItem,
    });
    if (corrected) {
      console.error(
        `parse-sale quantity-fix: matched="${corrected.matched}" ` +
          `model=${modelQuantity} corrected=${quantity}`,
      );
    }
    return {
      heard,
      quantity,
      unit_heard: typeof it?.unit_heard === "string" ? it.unit_heard : null,
      matches: matches
        .filter((m: Record<string, unknown>) => ids.has(m?.product_id as string))
        .map((m: Record<string, unknown>) => ({
          product_id: m.product_id,
          confidence: Math.max(0, Math.min(1, Number(m.confidence) || 0)),
        })),
    };
  }).filter((it) => it.heard !== "" || it.matches.length > 0);

  return { heard_text: heardText, items };
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// Supabase checks the token's signature before a request reaches this code
// (JWT verification is on by default: never deploy with --no-verify-jwt). But
// the public anon key passes that check too, and it ships inside every APK, so
// anyone could unpack the app and spend the Gemini quota with no account.
// Only a signed-in user's token carries role "authenticated"; a guest
// (anonymous) session is refused too, since anyone can create one with the
// anon key.
function isSignedInUser(req: Request): boolean {
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const payload = token.split(".")[1];
  if (!payload) return false;
  try {
    const claims = JSON.parse(atob(payload.replace(/-/g, "+").replace(/_/g, "/")));
    return claims?.role === "authenticated" && claims?.is_anonymous !== true;
  } catch (_e) {
    return false;
  }
}

// Far above anything the app sends (15 s of 32 kbps audio is ~80 KB of
// base64; a big shop has a few thousand products), so these only stop
// requests that did not come from the app and would buy a dearer prompt.
const MAX_AUDIO_B64_CHARS = 2_000_000;
const MAX_TRANSCRIPT_CHARS = 2000;
const MAX_CANDIDATES = 5000;

Deno.serve(async (req) => {
  if (!isSignedInUser(req)) {
    return json({ error: "sign in required" }, 401);
  }
  // Hoisted above body parsing (not just above the Gemini call) so a slow/large
  // request body -- the exact thing the payload-size hypothesis is about --
  // is inside the measured window instead of invisible before the clock starts.
  const startedAt = Date.now();
  let transcript: unknown;
  let audioBase64: unknown;
  let audioMime: unknown;
  let candidates: unknown;
  let ping: unknown;
  try {
    const body = await req.json();
    transcript = body.transcript;
    audioBase64 = body.audio_base64;
    audioMime = body.audio_mime;
    candidates = body.candidates;
    ping = body.ping;
  } catch (_e) {
    return json({ error: "invalid JSON body" }, 400);
  }

  // Warm-up handshake. The app fires this the moment recording starts so the
  // container is already booted by the time real audio arrives -- the cold
  // start then overlaps the seconds the shopkeeper spends speaking instead of
  // landing after it. Answered before every validation branch below and before
  // any Gemini call, so a ping costs no tokens and needs no candidates.
  //
  // A deploy that predates this branch simply 400s on the ping; the client
  // swallows that, and the container is warm either way -- which is the entire
  // point. See `VoiceSaleRepository.warmUp`.
  if (ping === true) {
    return json({ ok: true, warm: true });
  }

  if (!Array.isArray(candidates)) {
    return json({ error: "candidates (array) is required" }, 400);
  }

  const hasTranscript = typeof transcript === "string" && transcript.trim().length > 0;
  const hasAudio = typeof audioBase64 === "string" && audioBase64.trim().length > 0;

  if (hasTranscript && hasAudio) {
    return json({ error: "provide exactly one of transcript or audio_base64, not both" }, 400);
  }
  if (!hasTranscript && !hasAudio) {
    return json({ error: "transcript (non-empty string) or audio_base64 is required" }, 400);
  }
  if (
    candidates.length > MAX_CANDIDATES ||
    (hasAudio && (audioBase64 as string).length > MAX_AUDIO_B64_CHARS) ||
    (hasTranscript && (transcript as string).length > MAX_TRANSCRIPT_CHARS)
  ) {
    return json({ error: "request too large" }, 413);
  }
  // Both paths now go to Gemini, so the key is always required.
  if (!GEMINI_API_KEY) {
    return json({ error: "GEMINI_API_KEY is not configured" }, 400);
  }

  // Set once the Gemini call actually starts (not just declared). Left
  // `undefined` if we fail before reaching it, so the catch block can log an
  // unambiguous "not-started" instead of a misleading 0ms/omitted segment.
  let geminiStartedAt: number | undefined;
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
    geminiStartedAt = Date.now();
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
    // or our own timeout abort) return 5xx so the app shows its error/retry
    // state. A real empty result is still a 200 with items: [] from normalize().
    // This is the noisy-shop-failure case the instrumentation exists to
    // diagnose, so it must emit the SAME mode/b64len/gemini fields as the
    // success path above -- a failure log with no payload size and no Gemini
    // segment defeats the point of adding this instrumentation.
    const geminiMs = geminiStartedAt === undefined
      ? "not-started"
      : `${Date.now() - geminiStartedAt}ms(unfinished)`;
    console.error(
      `parse-sale FAILED: mode=${hasAudio ? "audio" : "text"} ` +
        `b64len=${hasAudio ? (audioBase64 as string).length : 0} ` +
        `gemini=${geminiMs} total=${Date.now() - startedAt}ms`,
      e,
    );
    return json({ error: "parse failed" }, 502);
  }
});
