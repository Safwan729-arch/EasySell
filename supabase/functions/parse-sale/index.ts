// Supabase Edge Function: parse-sale
// Voice sale parser. Accepts either a TRANSCRIPT (on-device speech-to-text,
// our curl-testable path) or raw AUDIO (audio_base64 + audio_mime). Audio is
// transcribed by calling the Gemini API directly — Gemini, not Frog, does the
// "ears" here — then the resulting text is fed into the EXISTING Frog/GPT
// parse step below, unchanged. The shop's product candidates are matched
// against the sentence and returned as normalized JSON.
//
// Why Gemini, not Frog, for audio: the Frog gateway does NOT accept audio
// input — verified 2026-07-22, it rejects an input_audio content block with
// "Content blocks are expected to be either text or image_url type" and has
// no /audio/transcriptions endpoint. Gemini has a free tier and accepts audio
// directly via generateContent, so it does the transcription step, and Frog
// keeps doing exactly what it always has: turn TEXT into structured sale
// line items.
//
// Like recognize-product it calls **Frog API** for the parse step — an
// OpenAI-compatible gateway — so there is one base URL + one key for that
// half. Keys stay in Supabase secrets (never on the device). MEMBER B owns
// prompt tuning.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

interface Candidate {
  id: string;
  name: string;
  brand?: string;
  variant?: string;
  unit?: string;
}

// Gateway config. Base URL + model id default to Frog's values but stay
// overridable via secrets; only FROG_API_KEY must be set.
const BASE_URL = (Deno.env.get("FROG_BASE_URL") ?? "https://frogapi.app/v1").replace(/\/+$/, "");
const API_KEY = Deno.env.get("FROG_API_KEY") ?? "";
// Defaults to the SAME model the scan feature uses (OPENAI_MODEL, e.g.
// gpt-5.6-luna) so voice needs no new secret. Model slugs retire, so keep this
// overridable via a secret.
const MODEL = Deno.env.get("VOICE_MODEL") ?? Deno.env.get("OPENAI_MODEL") ?? "gpt-5.6-luna";

// Gemini config for the audio-transcription step only. Free-tier key, set by
// the user. Model defaults to a free, audio-capable Gemini model but stays
// overridable in case a slug retires.
const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY") ?? "";
const GEMINI_MODEL = Deno.env.get("GEMINI_TRANSCRIBE_MODEL") ?? "gemini-2.5-flash";

const instruction = (candidates: Candidate[]) =>
  `You turn a shopkeeper's spoken sentence (already transcribed to text) into sale
line items for a point-of-sale. The text may be English, Bengali, or a mix.

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
spoken for an item, omit "quantity".

Return ONLY minified JSON of this exact shape:
{"heard_text":string,"items":[{"heard":string,"quantity":number,"unit_heard":string|null,"matches":[{"product_id":"<id from the list>","confidence":<0..1>}]}]}
Set "heard_text" to the shopkeeper's sentence. Rank each item's matches by
confidence (highest first). If nothing sale-like was said, return an empty items
array. Product list: ${JSON.stringify(candidates)}`;

// Transcription prompt for the Gemini audio step. Only bare vocabulary (name +
// brand) is sent as context hints — never the full candidate JSON with ids;
// Gemini's job here is hearing words correctly, not matching products.
const transcribePrompt = (candidates: Candidate[]) => {
  const hints = [...new Set(
    candidates
      .flatMap((c) => [c.name, c.brand])
      .filter((v): v is string => typeof v === "string" && v.trim().length > 0),
  )];
  const hintLine = hints.length
    ? `\n\nThe shop sells these products — use them as hints for brand/product names you might hear: ${hints.join(", ")}.`
    : "";
  return `Transcribe EXACTLY what is said in this audio recording of a shopkeeper describing a sale. The speech may be Bengali, English, or a mix of both. Output ONLY the transcript text, nothing else — no commentary, no quotation marks, no labels.${hintLine}`;
};

function extractJson(text: string): Record<string, unknown> {
  const cleaned = text.trim().replace(/^```json/i, "").replace(/```$/, "").trim();
  const start = cleaned.indexOf("{");
  const end = cleaned.lastIndexOf("}");
  return JSON.parse(start >= 0 ? cleaned.slice(start, end + 1) : cleaned);
}

// One call to Gemini to turn audio into text, BEFORE the existing Frog parse
// step runs. Frog itself still cannot accept audio (see header comment).
// Same res.ok guard-and-throw discipline as parse() below, prefixed with
// "gemini" (vs. "gateway") so Dashboard logs show which provider failed.
async function transcribe(audioBase64: string, audioMime: string, candidates: Candidate[]) {
  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": GEMINI_API_KEY },
      body: JSON.stringify({
        contents: [
          {
            role: "user",
            parts: [
              { text: transcribePrompt(candidates) },
              { inline_data: { mime_type: audioMime, data: audioBase64 } },
            ],
          },
        ],
      }),
    },
  );
  // Same reasoning as the Frog res.ok guard: a non-2xx here (bad key -> 400,
  // quota -> 429, outage -> 5xx) must not be allowed to fall through to
  // res.json() and read as an empty transcript.
  if (!res.ok) {
    const detail = await res.text().catch(() => "");
    throw new Error(`gemini ${res.status}: ${detail.slice(0, 300)}`);
  }
  const body = await res.json();
  const text = body?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (typeof text !== "string") return "";
  // Gemini sometimes wraps the transcript in quotes or adds a trailing
  // newline; strip both before treating it as the transcript.
  return text.trim().replace(/^"([\s\S]*)"$/, "$1").trim();
}

// One OpenAI-compatible chat call through Frog. NOTE: no `temperature` is sent —
// newer models (GPT-5.6 tier) reject temperature:0 outright, and the default is
// fine for this extraction.
async function parse(transcript: string, candidates: Candidate[]) {
  const res = await fetch(`${BASE_URL}/chat/completions`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${API_KEY}` },
    body: JSON.stringify({
      model: MODEL,
      messages: [
        { role: "system", content: instruction(candidates) },
        { role: "user", content: transcript },
      ],
    }),
  });
  // A non-2xx from the gateway (bad key -> 401, rate limit -> 429, outage -> 5xx)
  // does not throw on its own; without this check res.json() would parse the
  // error body, find no choices, and fall through to a misleading empty 200.
  if (!res.ok) {
    const detail = await res.text().catch(() => "");
    throw new Error(`gateway ${res.status}: ${detail.slice(0, 300)}`);
  }
  const json = await res.json();
  return extractJson(json?.choices?.[0]?.message?.content ?? "{}");
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
  if (hasAudio && !GEMINI_API_KEY) {
    return json({ error: "audio_base64 was provided but GEMINI_API_KEY is not configured" }, 400);
  }

  try {
    let resolvedTranscript: string;
    if (hasAudio) {
      const mime = typeof audioMime === "string" && audioMime.trim() ? audioMime : "audio/m4a";
      const heard = await transcribe(audioBase64 as string, mime, candidates as Candidate[]);
      if (!heard.trim()) {
        // A silent/unintelligible clip is a real "nothing was said" result,
        // not a failure — same discipline as an empty Frog items array.
        return json({ heard_text: "", items: [] }, 200);
      }
      resolvedTranscript = heard;
    } else {
      resolvedTranscript = transcript as string;
    }
    const raw = await parse(resolvedTranscript, candidates as Candidate[]);
    return json(normalize(raw, candidates as Candidate[], resolvedTranscript), 200);
  } catch (e) {
    // Genuine failures (bad key, Gemini/Frog outage, non-JSON reply) return 5xx
    // so the app shows its error/retry state. A real empty result is still a
    // 200 with items: [] from normalize() or the early return above.
    console.error("parse-sale failed:", e);
    return json({ error: "parse failed" }, 502);
  }
});
