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

interface Candidate {
  id: string;
  name: string;
  brand?: string;
  variant?: string;
  unit?: string;
}

// Google Gemini config. Only GEMINI_API_KEY must be set. Model pinned to
// gemini-3.6-flash but overridable via a secret so a future slug rename never
// needs a code change.
const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY") ?? "";
const MODEL = Deno.env.get("GEMINI_VOICE_MODEL") ?? "gemini-3.6-flash";

const instruction = (candidates: Candidate[]) =>
  `You are a point-of-sale assistant. You receive a shopkeeper's spoken sentence,
either as audio or as already-transcribed text. The speech may be English,
Bengali, or a mix. Do TWO things:
1. Transcribe EXACTLY what was said into "heard_text" (verbatim, no commentary).
2. Turn it into sale line items matched against the shop's product list below.

CRITICAL RULE — quantity and size are DIFFERENT fields, never merge them:
- Count words (piece, pcs, packet, ta, টা, টি, পিস) give "quantity".
- Size words (500ml, 1 litre, kg, লিটার, কেজি) are part of "heard" and are used to
  pick the RIGHT product. A size must NEVER become the quantity.
  "pepsi 1 litre" => quantity 1, heard "pepsi 1 litre"  (matches the 1L product)
  "2 pepsi"       => quantity 2, heard "pepsi"

Match each spoken item against the shop's product list below. If the text does
NOT distinguish between two candidates (e.g. "pepsi" when both 500ml and 1L
exist), return BOTH with SIMILAR confidence — do NOT guess a winner; the app asks
the user. Never invent a product_id that is not in the list. If no count was
spoken for an item, OMIT "quantity" entirely (do not guess a number). If nothing
sale-like was said, return an empty items array.

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
      body: JSON.stringify({
        contents: [
          { role: "user", parts: [{ text: instruction(candidates) }, userPart] },
        ],
        generationConfig: {
          responseMimeType: "application/json",
          responseSchema,
          temperature: 0,
          // Disable the model's internal "thinking" — transcription + extraction
          // is a simple, structured job, and thinking adds several seconds of
          // latency for no quality gain here.
          thinkingConfig: { thinkingBudget: 0 },
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
  return JSON.parse(text) as Record<string, unknown>;
}

// Never trust the model's output shape. Drop invented ids, clamp confidences,
// and pass quantity through only when it is a real positive number (the app
// defaults a missing quantity to 1 and flags it, rather than us inventing one).
function normalize(raw: Record<string, unknown>, candidates: Candidate[], transcript: string) {
  const ids = new Set(candidates.map((c) => c.id));
  const rawItems = Array.isArray(raw.items) ? raw.items : [];
  const items = rawItems.map((it: Record<string, unknown>) => {
    const matches = Array.isArray(it?.matches) ? it.matches : [];
    return {
      heard: typeof it?.heard === "string" ? it.heard : "",
      quantity: typeof it?.quantity === "number" && it.quantity > 0 ? it.quantity : null,
      unit_heard: typeof it?.unit_heard === "string" ? it.unit_heard : null,
      matches: matches
        .filter((m: Record<string, unknown>) => ids.has(m?.product_id as string))
        .map((m: Record<string, unknown>) => ({
          product_id: m.product_id,
          confidence: Math.max(0, Math.min(1, Number(m.confidence) || 0)),
        })),
    };
  }).filter((it) => it.heard !== "" || it.matches.length > 0);
  // Fall back to the raw transcript so the review sheet can always show what was said.
  return { heard_text: (typeof raw.heard_text === "string" && raw.heard_text) || transcript, items };
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  let transcript: unknown;
  let audioBase64: unknown;
  let audioMime: unknown;
  let candidates: unknown;
  try {
    const body = await req.json();
    transcript = body.transcript;
    audioBase64 = body.audio_base64;
    audioMime = body.audio_mime;
    candidates = body.candidates;
  } catch (_e) {
    return json({ error: "invalid JSON body" }, 400);
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
  // Both paths now go to Gemini, so the key is always required.
  if (!GEMINI_API_KEY) {
    return json({ error: "GEMINI_API_KEY is not configured" }, 400);
  }

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
    const raw = await parseSale(input, candidates as Candidate[]);
    return json(normalize(raw, candidates as Candidate[], fallback), 200);
  } catch (e) {
    // Genuine failures (bad key, Gemini outage, non-JSON reply, safety block)
    // return 5xx so the app shows its error/retry state. A real empty result is
    // still a 200 with items: [] from normalize().
    console.error("parse-sale failed:", e);
    return json({ error: "parse failed" }, 502);
  }
});
